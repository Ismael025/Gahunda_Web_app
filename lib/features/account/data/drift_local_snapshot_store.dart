import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../planner/data/planning_database.dart';
import '../domain/account_entities.dart';
import '../domain/account_repository.dart';

typedef SyncUtcClock = DateTime Function();
typedef DeviceIdFactory = String Function();

final class DriftLocalSnapshotStore implements LocalSnapshotStore {
  DriftLocalSnapshotStore(
    this._database, {
    SyncUtcClock? clock,
    DeviceIdFactory? deviceIdFactory,
  })  : _clock = clock ?? DateTime.now,
        _deviceIdFactory = deviceIdFactory;

  static const int snapshotSchemaVersion = 7;

  static const List<String> _tableOrder = <String>[
    'goals',
    'plan_periods',
    'milestones',
    'academic_terms',
    'subjects',
    'planning_tasks',
    'time_blocks',
    'daily_closures',
    'class_sessions',
    'school_assignments',
    'exams',
    'habits',
    'habit_check_ins',
    'money_accounts',
    'money_categories',
    'money_transactions',
    'money_budgets',
    'savings_goals',
    'savings_movements',
    'period_reviews',
  ];

  static final List<String> _deleteOrder =
      _tableOrder.reversed.toList(growable: false);

  final PlanningDatabase _database;
  final SyncUtcClock _clock;
  final DeviceIdFactory? _deviceIdFactory;
  final Random _random = Random.secure();

  @override
  Future<LocalSyncMetadata> loadMetadata() async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM sync_metadata WHERE singleton_id = 1',
    );
    if (rows.isNotEmpty) return _metadataFromRow(rows.single);

    final DateTime now = _clock().toUtc();
    final String deviceId = _deviceIdFactory?.call() ?? _newDeviceId(now);
    await _database.executeStatement(
      '''
        INSERT INTO sync_metadata (
          singleton_id, owner_user_id, device_id, remote_revision,
          base_fingerprint, last_synced_at_utc, last_error, updated_at_utc
        ) VALUES (1, NULL, ?, 0, NULL, NULL, NULL, ?)
      ''',
      <Object?>[deviceId, now.toIso8601String()],
    );
    return LocalSyncMetadata(deviceId: deviceId, remoteRevision: 0);
  }

  @override
  Future<LocalSyncMetadata> claimOwner(String userId) async {
    final LocalSyncMetadata metadata = await loadMetadata();
    final String normalized = userId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User ID cannot be empty.');
    }
    if (metadata.ownerUserId != null && metadata.ownerUserId != normalized) {
      throw const AccountMismatchException();
    }
    if (metadata.ownerUserId == normalized) return metadata;
    final LocalSyncMetadata claimed =
        metadata.copyWith(ownerUserId: normalized);
    await saveMetadata(claimed);
    return claimed;
  }

  @override
  Future<void> saveMetadata(LocalSyncMetadata metadata) {
    return _database.executeStatement(
      '''
        INSERT INTO sync_metadata (
          singleton_id, owner_user_id, device_id, remote_revision,
          base_fingerprint, last_synced_at_utc, last_error, updated_at_utc
        ) VALUES (1, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(singleton_id) DO UPDATE SET
          owner_user_id = excluded.owner_user_id,
          device_id = excluded.device_id,
          remote_revision = excluded.remote_revision,
          base_fingerprint = excluded.base_fingerprint,
          last_synced_at_utc = excluded.last_synced_at_utc,
          last_error = excluded.last_error,
          updated_at_utc = excluded.updated_at_utc
      ''',
      <Object?>[
        metadata.ownerUserId,
        metadata.deviceId,
        metadata.remoteRevision,
        metadata.baseFingerprint,
        metadata.lastSyncedAtUtc?.toUtc().toIso8601String(),
        metadata.lastError,
        _clock().toUtc().toIso8601String(),
      ],
    );
  }

  @override
  Future<GahundaSnapshot> exportSnapshot() async {
    final Map<String, List<Map<String, Object?>>> tables =
        <String, List<Map<String, Object?>>>{};
    for (final String table in _tableOrder) {
      final List<QueryRow> rows = await _database.readRows(
        'SELECT * FROM ${_identifier(table)} ORDER BY id',
      );
      tables[table] = rows
          .map<Map<String, Object?>>(
            (QueryRow row) => Map<String, Object?>.from(row.data),
          )
          .toList(growable: false);
    }
    return GahundaSnapshot(
      schemaVersion: snapshotSchemaVersion,
      tables: Map<String, List<Map<String, Object?>>>.unmodifiable(tables),
      fingerprint: _fingerprint(tables),
      hasUserData: _containsUserData(tables),
    );
  }

  @override
  Future<void> importSnapshot(GahundaSnapshot snapshot) async {
    if (snapshot.schemaVersion != snapshotSchemaVersion) {
      throw StateError(
        'Cloud backup schema ${snapshot.schemaVersion} is not compatible with '
        'local schema $snapshotSchemaVersion.',
      );
    }
    if (snapshot.tables.length != _tableOrder.length ||
        !_tableOrder.every(snapshot.tables.containsKey)) {
      throw const FormatException(
        'The cloud backup does not contain the expected Gahunda tables.',
      );
    }
    final String calculated = _fingerprint(snapshot.tables);
    if (snapshot.fingerprint != calculated) {
      throw const FormatException('The cloud backup integrity check failed.');
    }

    final Map<String, List<String>> columns = <String, List<String>>{};
    for (final String table in _tableOrder) {
      final List<QueryRow> info = await _database.readRows(
        'PRAGMA table_info(${_identifier(table)})',
      );
      columns[table] = info
          .map<String>((QueryRow row) => row.read<String>('name'))
          .toList(growable: false);
    }

    await _database.executeStatement('PRAGMA foreign_keys = OFF');
    try {
      await _database.transaction(() async {
        for (final String table in _deleteOrder) {
          await _database.executeStatement('DELETE FROM ${_identifier(table)}');
        }
        for (final String table in _tableOrder) {
          final List<String> tableColumns = columns[table]!;
          final String columnSql = tableColumns.map(_identifier).join(', ');
          final String placeholders =
              List<String>.filled(tableColumns.length, '?').join(', ');
          for (final Map<String, Object?> row in snapshot.tables[table]!) {
            if (row.length != tableColumns.length ||
                !tableColumns.every(row.containsKey)) {
              throw FormatException(
                'The cloud backup contains invalid columns for $table.',
              );
            }
            await _database.executeStatement(
              'INSERT INTO ${_identifier(table)} ($columnSql) '
              'VALUES ($placeholders)',
              tableColumns.map<Object?>((String name) => row[name]).toList(),
            );
          }
        }
        final List<QueryRow> foreignKeyProblems =
            await _database.readRows('PRAGMA foreign_key_check');
        if (foreignKeyProblems.isNotEmpty) {
          throw const FormatException(
            'The cloud backup contains broken record relationships.',
          );
        }
      });
    } finally {
      await _database.executeStatement('PRAGMA foreign_keys = ON');
    }
    _database.notifyChanged();
  }

  LocalSyncMetadata _metadataFromRow(QueryRow row) {
    final String? lastSynced = row.readNullable<String>('last_synced_at_utc');
    return LocalSyncMetadata(
      ownerUserId: row.readNullable<String>('owner_user_id'),
      deviceId: row.read<String>('device_id'),
      remoteRevision: row.read<int>('remote_revision'),
      baseFingerprint: row.readNullable<String>('base_fingerprint'),
      lastSyncedAtUtc:
          lastSynced == null ? null : DateTime.parse(lastSynced).toUtc(),
      lastError: row.readNullable<String>('last_error'),
    );
  }

  String _newDeviceId(DateTime now) {
    final String time = now.microsecondsSinceEpoch.toRadixString(36);
    final String random = _random.nextInt(0x7fffffff).toRadixString(36);
    return 'device-$time-$random';
  }
}

bool _containsUserData(Map<String, List<Map<String, Object?>>> tables) {
  for (final MapEntry<String, List<Map<String, Object?>>> entry
      in tables.entries) {
    if (entry.key == 'money_categories') {
      if (entry.value
          .any((Map<String, Object?> row) => row['is_system'] != 1)) {
        return true;
      }
    } else if (entry.value.isNotEmpty) {
      return true;
    }
  }
  return false;
}

String _fingerprint(Map<String, List<Map<String, Object?>>> tables) {
  final Map<String, Object?> canonical = <String, Object?>{};
  final List<String> tableNames = tables.keys.toList()..sort();
  for (final String table in tableNames) {
    final List<Map<String, Object?>> rows = tables[table]!
        .map<Map<String, Object?>>(_sortedMap)
        .toList(growable: false)
      ..sort(
        (Map<String, Object?> left, Map<String, Object?> right) =>
            jsonEncode(left).compareTo(jsonEncode(right)),
      );
    canonical[table] = rows;
  }
  final List<int> bytes = utf8.encode(jsonEncode(canonical));
  return sha256.convert(bytes).toString();
}

Map<String, Object?> _sortedMap(Map<String, Object?> source) {
  final List<String> keys = source.keys.toList()..sort();
  return <String, Object?>{for (final String key in keys) key: source[key]};
}

String _identifier(String value) => '"${value.replaceAll('"', '""')}"';
