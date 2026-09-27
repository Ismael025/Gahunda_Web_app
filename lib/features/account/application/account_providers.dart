import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/cloud_configuration.dart';
import '../../planner/application/planning_providers.dart';
import '../../planner/data/planning_database.dart';
import '../data/drift_local_snapshot_store.dart';
import '../data/supabase_account_repository.dart';
import '../data/supabase_sync_remote_gateway.dart';
import '../domain/account_entities.dart';
import '../domain/account_repository.dart';

final Provider<CloudConfiguration> cloudConfigurationProvider =
    Provider<CloudConfiguration>((Ref ref) {
  return GahundaCloudBootstrap.configuration;
});

final Provider<SupabaseClient?> supabaseClientProvider =
    Provider<SupabaseClient?>((Ref ref) {
  return GahundaCloudBootstrap.client;
});

final Provider<AccountRepository> accountRepositoryProvider =
    Provider<AccountRepository>((Ref ref) {
  final SupabaseClient? client = ref.watch(supabaseClientProvider);
  return client == null
      ? const LocalOnlyAccountRepository()
      : SupabaseAccountRepository(client);
});

final Provider<LocalSnapshotStore> localSnapshotStoreProvider =
    Provider<LocalSnapshotStore>((Ref ref) {
  return DriftLocalSnapshotStore(ref.watch(planningDatabaseProvider));
});

final Provider<SyncRemoteGateway> syncRemoteGatewayProvider =
    Provider<SyncRemoteGateway>((Ref ref) {
  final SupabaseClient? client = ref.watch(supabaseClientProvider);
  return client == null
      ? const LocalOnlySyncRemoteGateway()
      : SupabaseSyncRemoteGateway(client);
});

final StateNotifierProvider<SyncController, SyncState> syncControllerProvider =
    StateNotifierProvider<SyncController, SyncState>((Ref ref) {
  final SyncController controller = SyncController(
    configuration: ref.watch(cloudConfigurationProvider),
    database: ref.watch(planningDatabaseProvider),
    accountRepository: ref.watch(accountRepositoryProvider),
    localStore: ref.watch(localSnapshotStoreProvider),
    remoteGateway: ref.watch(syncRemoteGatewayProvider),
  );
  unawaited(controller.initialize());
  return controller;
});

final class SyncController extends StateNotifier<SyncState> {
  SyncController({
    required CloudConfiguration configuration,
    required PlanningDatabase database,
    required AccountRepository accountRepository,
    required LocalSnapshotStore localStore,
    required SyncRemoteGateway remoteGateway,
    DateTime Function()? clock,
    Duration autoSyncDelay = const Duration(seconds: 2),
  })  : _configuration = configuration,
        _database = database,
        _accountRepository = accountRepository,
        _localStore = localStore,
        _remoteGateway = remoteGateway,
        _clock = clock ?? DateTime.now,
        _autoSyncDelay = autoSyncDelay,
        super(const SyncState.starting());

  final CloudConfiguration _configuration;
  final PlanningDatabase _database;
  final AccountRepository _accountRepository;
  final LocalSnapshotStore _localStore;
  final SyncRemoteGateway _remoteGateway;
  final DateTime Function() _clock;
  final Duration _autoSyncDelay;

  StreamSubscription<AccountUser?>? _authSubscription;
  StreamSubscription<void>? _databaseSubscription;
  Timer? _autoSyncTimer;
  LocalSyncMetadata? _metadata;
  AccountUser? _user;
  bool _syncing = false;
  bool _disposed = false;

  Future<void> initialize() async {
    try {
      _metadata = await _localStore.loadMetadata();
      _databaseSubscription = _database.changes.listen((_) {
        if (_syncing || _user == null || state.phase == SyncPhase.conflict) {
          return;
        }
        _autoSyncTimer?.cancel();
        _autoSyncTimer = Timer(_autoSyncDelay, () => unawaited(syncNow()));
      });
      _authSubscription = _accountRepository.watchUser().listen(
        (AccountUser? user) => unawaited(_handleUser(user)),
        onError: (Object error, StackTrace _) {
          _setError(_friendlyError(error));
        },
      );
      await _handleUser(_accountRepository.currentUser);
    } on Object catch (error) {
      _setError(_friendlyError(error));
    }
  }

  Future<void> syncNow() async {
    if (_syncing || _disposed) return;
    final AccountUser? user = _user;
    LocalSyncMetadata? metadata = _metadata;
    if (!_configuration.isConfigured) {
      _set(
        SyncState(
          phase: SyncPhase.localOnly,
          metadata: metadata,
          message: 'Cloud sync is not configured. Local data is still active.',
        ),
      );
      return;
    }
    if (user == null) {
      _set(
        SyncState(
          phase: metadata?.ownerUserId == null
              ? SyncPhase.localOnly
              : SyncPhase.signedOut,
          metadata: metadata,
          message: metadata?.ownerUserId == null
              ? 'Using this device without an account.'
              : 'Sign in to unlock the data saved on this device.',
        ),
      );
      return;
    }

    _syncing = true;
    _autoSyncTimer?.cancel();
    _set(SyncState(phase: SyncPhase.syncing, metadata: metadata, user: user));
    try {
      metadata = await _localStore.claimOwner(user.id);
      _metadata = metadata;
      final GahundaSnapshot local = await _localStore.exportSnapshot();
      final CloudSnapshot? cloud = await _remoteGateway.fetchSnapshot();

      if (cloud == null) {
        final CloudSnapshot saved = await _remoteGateway.saveSnapshot(
          snapshot: local,
          expectedRevision: 0,
          deviceId: metadata.deviceId,
        );
        await _completeSync(saved.revision, local.fingerprint);
        return;
      }

      final bool localChanged = metadata.baseFingerprint == null ||
          local.fingerprint != metadata.baseFingerprint;
      final bool remoteChanged = cloud.revision != metadata.remoteRevision;

      if (metadata.remoteRevision == 0) {
        if (local.fingerprint == cloud.snapshot.fingerprint) {
          await _completeSync(cloud.revision, local.fingerprint);
        } else if (!local.hasUserData) {
          await _useCloudSnapshot(cloud);
        } else {
          _showConflict(metadata, user, cloud);
        }
        return;
      }

      if (!remoteChanged) {
        if (!localChanged) {
          await _completeSync(cloud.revision, local.fingerprint);
        } else {
          final CloudSnapshot saved = await _remoteGateway.saveSnapshot(
            snapshot: local,
            expectedRevision: cloud.revision,
            deviceId: metadata.deviceId,
          );
          await _completeSync(saved.revision, local.fingerprint);
        }
        return;
      }

      if (!localChanged) {
        await _useCloudSnapshot(cloud);
      } else if (local.fingerprint == cloud.snapshot.fingerprint) {
        await _completeSync(cloud.revision, local.fingerprint);
      } else {
        _showConflict(metadata, user, cloud);
      }
    } on AccountMismatchException catch (error) {
      _set(
        SyncState(
          phase: SyncPhase.accountMismatch,
          metadata: _metadata,
          user: user,
          message: error.toString(),
        ),
      );
    } on SyncConflictException {
      await _refreshConflict(user);
    } on Object catch (error) {
      await _recordError(user, error);
    } finally {
      _syncing = false;
    }
  }

  Future<void> keepDeviceCopy() async {
    await _resolveConflict(useCloud: false);
  }

  Future<void> useCloudCopy() async {
    await _resolveConflict(useCloud: true);
  }

  Future<void> signOut() => _accountRepository.signOut();

  Future<void> _resolveConflict({required bool useCloud}) async {
    if (_syncing || _disposed) return;
    final AccountUser? user = _user;
    final LocalSyncMetadata? metadata = _metadata;
    if (user == null || metadata == null) return;
    _syncing = true;
    _set(SyncState(phase: SyncPhase.syncing, metadata: metadata, user: user));
    try {
      final CloudSnapshot? cloud = await _remoteGateway.fetchSnapshot();
      if (useCloud) {
        if (cloud == null) {
          throw StateError('The cloud copy is no longer available.');
        }
        await _useCloudSnapshot(cloud);
      } else {
        final GahundaSnapshot local = await _localStore.exportSnapshot();
        final CloudSnapshot saved = await _remoteGateway.saveSnapshot(
          snapshot: local,
          expectedRevision: cloud?.revision ?? 0,
          deviceId: metadata.deviceId,
        );
        await _completeSync(saved.revision, local.fingerprint);
      }
    } on SyncConflictException {
      await _refreshConflict(user);
    } on Object catch (error) {
      await _recordError(user, error);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _handleUser(AccountUser? user) async {
    if (_disposed) return;
    _user = user;
    final LocalSyncMetadata? metadata = _metadata;
    if (metadata == null) return;
    if (!_configuration.isConfigured) {
      _set(
        SyncState(
          phase: metadata.ownerUserId == null
              ? SyncPhase.localOnly
              : SyncPhase.signedOut,
          metadata: metadata,
          message: 'Cloud sync is not configured.',
        ),
      );
      return;
    }
    if (user == null) {
      _set(
        SyncState(
          phase: metadata.ownerUserId == null
              ? SyncPhase.localOnly
              : SyncPhase.signedOut,
          metadata: metadata,
          message: metadata.ownerUserId == null
              ? 'Using this device without an account.'
              : 'Sign in to unlock the data saved on this device.',
        ),
      );
      return;
    }
    if (metadata.ownerUserId != null && metadata.ownerUserId != user.id) {
      _set(
        SyncState(
          phase: SyncPhase.accountMismatch,
          metadata: metadata,
          user: user,
          message: const AccountMismatchException().toString(),
        ),
      );
      return;
    }
    _set(SyncState(phase: SyncPhase.ready, metadata: metadata, user: user));
    await syncNow();
  }

  Future<void> _useCloudSnapshot(CloudSnapshot cloud) async {
    await _localStore.importSnapshot(cloud.snapshot);
    await _completeSync(cloud.revision, cloud.snapshot.fingerprint);
  }

  Future<void> _completeSync(int revision, String fingerprint) async {
    final LocalSyncMetadata current = _metadata!;
    final LocalSyncMetadata next = LocalSyncMetadata(
      ownerUserId: current.ownerUserId,
      deviceId: current.deviceId,
      remoteRevision: revision,
      baseFingerprint: fingerprint,
      lastSyncedAtUtc: _clock().toUtc(),
    );
    await _localStore.saveMetadata(next);
    _metadata = next;
    _set(
      SyncState(
        phase: SyncPhase.synced,
        metadata: next,
        user: _user,
        message: 'This device and cloud are up to date.',
      ),
    );
  }

  void _showConflict(
    LocalSyncMetadata metadata,
    AccountUser user,
    CloudSnapshot cloud,
  ) {
    _set(
      SyncState(
        phase: SyncPhase.conflict,
        metadata: metadata,
        user: user,
        cloudConflict: cloud,
        message:
            'This device and another device both changed since the last sync.',
      ),
    );
  }

  Future<void> _refreshConflict(AccountUser user) async {
    try {
      final CloudSnapshot? cloud = await _remoteGateway.fetchSnapshot();
      if (cloud == null) {
        await _recordError(
          user,
          StateError('The cloud copy could not be found.'),
        );
        return;
      }
      _showConflict(_metadata!, user, cloud);
    } on Object catch (error) {
      await _recordError(user, error);
    }
  }

  Future<void> _recordError(AccountUser user, Object error) async {
    final String message = _friendlyError(error);
    final LocalSyncMetadata? metadata = _metadata;
    if (metadata != null) {
      final LocalSyncMetadata failed = LocalSyncMetadata(
        ownerUserId: metadata.ownerUserId,
        deviceId: metadata.deviceId,
        remoteRevision: metadata.remoteRevision,
        baseFingerprint: metadata.baseFingerprint,
        lastSyncedAtUtc: metadata.lastSyncedAtUtc,
        lastError: message,
      );
      await _localStore.saveMetadata(failed);
      _metadata = failed;
    }
    _set(
      SyncState(
        phase: SyncPhase.error,
        metadata: _metadata,
        user: user,
        message: message,
      ),
    );
  }

  void _setError(String message) {
    _set(
      SyncState(
        phase: SyncPhase.error,
        metadata: _metadata,
        user: _user,
        message: message,
      ),
    );
  }

  void _set(SyncState next) {
    if (!_disposed) state = next;
  }

  @override
  void dispose() {
    _disposed = true;
    _autoSyncTimer?.cancel();
    unawaited(_authSubscription?.cancel());
    unawaited(_databaseSubscription?.cancel());
    super.dispose();
  }
}

String _friendlyError(Object error) {
  if (error is AuthException) return error.message;
  if (error is PostgrestException) return error.message;
  return error.toString().replaceFirst('Exception: ', '');
}
