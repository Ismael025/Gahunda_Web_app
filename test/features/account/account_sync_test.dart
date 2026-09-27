import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gahunda/features/account/application/account_providers.dart';
import 'package:gahunda/features/account/data/drift_local_snapshot_store.dart';
import 'package:gahunda/features/account/domain/account_entities.dart';
import 'package:gahunda/features/account/domain/account_repository.dart';
import 'package:gahunda/features/planner/data/planning_database.dart';

void main() {
  final DateTime fixedNow = DateTime.utc(2026, 9, 9, 12);

  test('schema version 6 adds sync metadata without losing reviews', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'gahunda-sync-migration-',
    );
    final File file = File('${directory.path}/migration.sqlite');
    addTearDown(() => directory.delete(recursive: true));
    final PlanningDatabase setup = PlanningDatabase(NativeDatabase(file));
    await setup.executeStatement('''
      INSERT INTO period_reviews (
        id, cadence, period_starts_on_local, overall_rating, wins,
        challenges, lessons, next_focus, created_at_utc, updated_at_utc
      ) VALUES (
        'review-1', 'weekly', '2026-09-07', 4, 'Protected existing work',
        NULL, NULL, 'Keep going', '2026-09-09T12:00:00Z',
        '2026-09-09T12:00:00Z'
      )
    ''');
    await setup.executeStatement('DROP TABLE notification_preferences');
    await setup.executeStatement('DROP TABLE sync_metadata');
    await setup.executeStatement('PRAGMA user_version = 6');
    await setup.close();

    final PlanningDatabase upgraded = PlanningDatabase(NativeDatabase(file));
    final DriftLocalSnapshotStore store = DriftLocalSnapshotStore(
      upgraded,
      clock: () => fixedNow,
      deviceIdFactory: () => 'migration-device',
    );
    final LocalSyncMetadata metadata = await store.loadMetadata();

    expect(metadata.deviceId, 'migration-device');
    expect(
      await upgraded.readRows('SELECT * FROM period_reviews'),
      hasLength(1),
    );
    expect(
        await upgraded.readRows('SELECT * FROM sync_metadata'), hasLength(1));
    await upgraded.close();
  });

  test('a complete snapshot restores local records without touching ownership',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftLocalSnapshotStore store = DriftLocalSnapshotStore(
      database,
      clock: () => fixedNow,
      deviceIdFactory: () => 'roundtrip-device',
    );
    addTearDown(database.close);
    await store.claimOwner('user-1');
    await _insertGoal(database, 'Original title');
    final GahundaSnapshot snapshot = await store.exportSnapshot();

    await database.executeStatement(
      "UPDATE goals SET title = 'Changed locally' WHERE id = 'goal-1'",
    );
    await store.importSnapshot(snapshot);

    expect(await _goalTitle(database), 'Original title');
    expect((await store.loadMetadata()).ownerUserId, 'user-1');
    expect(snapshot.hasUserData, isTrue);
  });

  test('snapshot integrity rejects altered cloud records', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftLocalSnapshotStore store = DriftLocalSnapshotStore(
      database,
      clock: () => fixedNow,
      deviceIdFactory: () => 'integrity-device',
    );
    addTearDown(database.close);
    await _insertGoal(database, 'Trusted title');
    final GahundaSnapshot snapshot = await store.exportSnapshot();
    final Map<String, List<Map<String, Object?>>> altered =
        snapshot.tables.map<String, List<Map<String, Object?>>>(
      (String table, List<Map<String, Object?>> rows) =>
          MapEntry<String, List<Map<String, Object?>>>(
        table,
        rows
            .map<Map<String, Object?>>(
              (Map<String, Object?> row) => Map<String, Object?>.from(row),
            )
            .toList(growable: false),
      ),
    );
    altered['goals']!.single['title'] = 'Tampered title';

    await expectLater(
      store.importSnapshot(
        GahundaSnapshot(
          schemaVersion: snapshot.schemaVersion,
          tables: altered,
          fingerprint: snapshot.fingerprint,
          hasUserData: true,
        ),
      ),
      throwsFormatException,
    );
    expect(await _goalTitle(database), 'Trusted title');
  });

  test('first signed-in device uploads and an empty second device restores',
      () async {
    final _FakeRemoteGateway remote = _FakeRemoteGateway(clock: () => fixedNow);
    final PlanningDatabase firstDatabase =
        PlanningDatabase(NativeDatabase.memory());
    final DriftLocalSnapshotStore firstStore = DriftLocalSnapshotStore(
      firstDatabase,
      clock: () => fixedNow,
      deviceIdFactory: () => 'first-device',
    );
    await _insertGoal(firstDatabase, 'Shared goal');
    final _FakeAccountRepository firstAccount = _FakeAccountRepository(
      const AccountUser(id: 'user-1', email: 'user@example.com'),
    );
    final SyncController first = _controller(
      database: firstDatabase,
      store: firstStore,
      account: firstAccount,
      remote: remote,
      now: fixedNow,
    );
    await first.initialize();
    expect(first.state.phase, SyncPhase.synced);
    expect(remote.snapshot?.revision, 1);

    final PlanningDatabase secondDatabase =
        PlanningDatabase(NativeDatabase.memory());
    final DriftLocalSnapshotStore secondStore = DriftLocalSnapshotStore(
      secondDatabase,
      clock: () => fixedNow,
      deviceIdFactory: () => 'second-device',
    );
    final _FakeAccountRepository secondAccount = _FakeAccountRepository(
      const AccountUser(id: 'user-1', email: 'user@example.com'),
    );
    final SyncController second = _controller(
      database: secondDatabase,
      store: secondStore,
      account: secondAccount,
      remote: remote,
      now: fixedNow,
    );
    await second.initialize();

    expect(second.state.phase, SyncPhase.synced);
    expect(await _goalTitle(secondDatabase), 'Shared goal');
    expect(second.state.metadata?.remoteRevision, 1);

    first.dispose();
    second.dispose();
    await firstAccount.close();
    await secondAccount.close();
    await firstDatabase.close();
    await secondDatabase.close();
  });

  test('newer cloud data downloads when the local copy did not change',
      () async {
    final _SyncFixture fixture = await _SyncFixture.create(fixedNow);
    addTearDown(fixture.close);
    final GahundaSnapshot remoteUpdate =
        await _snapshotWithGoal(fixedNow, 'Changed on phone');
    fixture.remote.replaceFromOther(remoteUpdate);

    await fixture.controller.syncNow();

    expect(fixture.controller.state.phase, SyncPhase.synced);
    expect(await _goalTitle(fixture.database), 'Changed on phone');
    expect(fixture.controller.state.metadata?.remoteRevision, 2);
  });

  test('simultaneous changes require an explicit conflict decision', () async {
    final _SyncFixture fixture = await _SyncFixture.create(fixedNow);
    addTearDown(fixture.close);
    await fixture.database.executeStatement(
      "UPDATE goals SET title = 'Changed on this device', "
      "updated_at_utc = '2026-09-09T13:00:00Z' WHERE id = 'goal-1'",
    );
    fixture.remote.replaceFromOther(
      await _snapshotWithGoal(fixedNow, 'Changed on another device'),
    );

    await fixture.controller.syncNow();
    expect(fixture.controller.state.phase, SyncPhase.conflict);
    expect(await _goalTitle(fixture.database), 'Changed on this device');

    await fixture.controller.keepDeviceCopy();
    expect(fixture.controller.state.phase, SyncPhase.synced);
    expect(
      fixture.remote.snapshot!.snapshot.tables['goals']!.single['title'],
      'Changed on this device',
    );
  });

  test('use cloud resolution replaces the local working copy only after choice',
      () async {
    final _SyncFixture fixture = await _SyncFixture.create(fixedNow);
    addTearDown(fixture.close);
    await fixture.database.executeStatement(
      "UPDATE goals SET title = 'Local edit', "
      "updated_at_utc = '2026-09-09T13:00:00Z' WHERE id = 'goal-1'",
    );
    fixture.remote.replaceFromOther(
      await _snapshotWithGoal(fixedNow, 'Cloud edit'),
    );
    await fixture.controller.syncNow();

    await fixture.controller.useCloudCopy();

    expect(fixture.controller.state.phase, SyncPhase.synced);
    expect(await _goalTitle(fixture.database), 'Cloud edit');
  });

  test('a different signed-in account cannot open linked device data',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftLocalSnapshotStore store = DriftLocalSnapshotStore(
      database,
      clock: () => fixedNow,
      deviceIdFactory: () => 'owned-device',
    );
    await store.claimOwner('owner-user');
    final _FakeAccountRepository account = _FakeAccountRepository(
      const AccountUser(id: 'other-user', email: 'other@example.com'),
    );
    final SyncController controller = _controller(
      database: database,
      store: store,
      account: account,
      remote: _FakeRemoteGateway(clock: () => fixedNow),
      now: fixedNow,
    );

    await controller.initialize();

    expect(controller.state.phase, SyncPhase.accountMismatch);
    controller.dispose();
    await account.close();
    await database.close();
  });
}

SyncController _controller({
  required PlanningDatabase database,
  required LocalSnapshotStore store,
  required AccountRepository account,
  required SyncRemoteGateway remote,
  required DateTime now,
}) {
  return SyncController(
    configuration: const CloudConfiguration(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    ),
    database: database,
    accountRepository: account,
    localStore: store,
    remoteGateway: remote,
    clock: () => now,
    autoSyncDelay: const Duration(days: 1),
  );
}

Future<void> _insertGoal(PlanningDatabase database, String title) {
  return database.executeStatement(
    '''
      INSERT INTO goals (
        id, title, description, scope, parent_goal_id, starts_at_utc,
        due_at_utc, status, created_at_utc, updated_at_utc, archived_at_utc
      ) VALUES (
        'goal-1', ?, NULL, 'annual', NULL, NULL, NULL, 'active',
        '2026-09-09T12:00:00Z', '2026-09-09T12:00:00Z', NULL
      )
    ''',
    <Object?>[title],
  );
}

Future<String> _goalTitle(PlanningDatabase database) async {
  return (await database
          .readRows("SELECT title FROM goals WHERE id = 'goal-1'"))
      .single
      .read<String>('title');
}

Future<GahundaSnapshot> _snapshotWithGoal(DateTime now, String title) async {
  final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
  final DriftLocalSnapshotStore store = DriftLocalSnapshotStore(
    database,
    clock: () => now,
    deviceIdFactory: () => 'other-device',
  );
  await _insertGoal(database, title);
  final GahundaSnapshot snapshot = await store.exportSnapshot();
  await database.close();
  return snapshot;
}

final class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository(this._user);

  AccountUser? _user;
  final StreamController<AccountUser?> _changes =
      StreamController<AccountUser?>.broadcast();

  @override
  AccountUser? get currentUser => _user;

  @override
  Stream<AccountUser?> watchUser() => _changes.stream;

  @override
  Future<AccountUser> signIn({
    required String email,
    required String password,
  }) async {
    final AccountUser user = AccountUser(id: 'user-1', email: email);
    _user = user;
    _changes.add(user);
    return user;
  }

  @override
  Future<AccountSignUpResult> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final AccountUser user = AccountUser(
      id: 'user-1',
      email: email,
      displayName: displayName,
    );
    _user = user;
    _changes.add(user);
    return AccountSignUpResult(user: user, emailConfirmationRequired: false);
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _changes.add(null);
  }

  Future<void> close() => _changes.close();
}

final class _FakeRemoteGateway implements SyncRemoteGateway {
  _FakeRemoteGateway({required DateTime Function() clock}) : _clock = clock;

  final DateTime Function() _clock;
  CloudSnapshot? snapshot;

  @override
  Future<CloudSnapshot?> fetchSnapshot() async => snapshot;

  @override
  Future<CloudSnapshot> saveSnapshot({
    required GahundaSnapshot snapshot,
    required int expectedRevision,
    required String deviceId,
  }) async {
    final int currentRevision = this.snapshot?.revision ?? 0;
    if (expectedRevision != currentRevision) {
      throw const SyncConflictException('Revision conflict.');
    }
    final CloudSnapshot saved = CloudSnapshot(
      revision: currentRevision + 1,
      snapshot: snapshot,
      deviceId: deviceId,
      updatedAtUtc: _clock(),
    );
    this.snapshot = saved;
    return saved;
  }

  void replaceFromOther(GahundaSnapshot replacement) {
    snapshot = CloudSnapshot(
      revision: (snapshot?.revision ?? 0) + 1,
      snapshot: replacement,
      deviceId: 'other-device',
      updatedAtUtc: _clock(),
    );
  }
}

final class _SyncFixture {
  _SyncFixture({
    required this.database,
    required this.account,
    required this.remote,
    required this.controller,
  });

  static Future<_SyncFixture> create(DateTime now) async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftLocalSnapshotStore store = DriftLocalSnapshotStore(
      database,
      clock: () => now,
      deviceIdFactory: () => 'fixture-device',
    );
    await _insertGoal(database, 'Initial goal');
    final _FakeAccountRepository account = _FakeAccountRepository(
      const AccountUser(id: 'user-1', email: 'user@example.com'),
    );
    final _FakeRemoteGateway remote = _FakeRemoteGateway(clock: () => now);
    final SyncController controller = _controller(
      database: database,
      store: store,
      account: account,
      remote: remote,
      now: now,
    );
    await controller.initialize();
    return _SyncFixture(
      database: database,
      account: account,
      remote: remote,
      controller: controller,
    );
  }

  final PlanningDatabase database;
  final _FakeAccountRepository account;
  final _FakeRemoteGateway remote;
  final SyncController controller;

  Future<void> close() async {
    controller.dispose();
    await account.close();
    await database.close();
  }
}
