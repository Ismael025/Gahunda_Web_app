import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/account_entities.dart';
import '../domain/account_repository.dart';

final class SupabaseSyncRemoteGateway implements SyncRemoteGateway {
  const SupabaseSyncRemoteGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<CloudSnapshot?> fetchSnapshot() async {
    final Map<String, dynamic>? row = await _client
        .from('gahunda_user_snapshots')
        .select('revision, payload, device_id, updated_at')
        .maybeSingle();
    return row == null ? null : _snapshotFromRow(row);
  }

  @override
  Future<CloudSnapshot> saveSnapshot({
    required GahundaSnapshot snapshot,
    required int expectedRevision,
    required String deviceId,
  }) async {
    try {
      final Object? response = await _client.rpc(
        'save_gahunda_snapshot',
        params: <String, Object?>{
          'p_expected_revision': expectedRevision,
          'p_payload': snapshot.toPayload(),
          'p_device_id': deviceId,
        },
      );
      return _snapshotFromRow(_responseRow(response));
    } on PostgrestException catch (error) {
      if (error.code == '40001' ||
          error.message.contains('gahunda_revision_conflict')) {
        throw const SyncConflictException(
          'The cloud copy changed on another device.',
        );
      }
      rethrow;
    }
  }
}

final class LocalOnlySyncRemoteGateway implements SyncRemoteGateway {
  const LocalOnlySyncRemoteGateway();

  @override
  Future<CloudSnapshot?> fetchSnapshot() {
    throw const CloudNotConfiguredException();
  }

  @override
  Future<CloudSnapshot> saveSnapshot({
    required GahundaSnapshot snapshot,
    required int expectedRevision,
    required String deviceId,
  }) {
    throw const CloudNotConfiguredException();
  }
}

Map<String, dynamic> _responseRow(Object? response) {
  if (response is Map<String, dynamic>) return response;
  if (response is List<Object?> && response.isNotEmpty) {
    final Object? first = response.first;
    if (first is Map<String, dynamic>) return first;
  }
  throw const FormatException('Supabase returned an invalid sync response.');
}

CloudSnapshot _snapshotFromRow(Map<String, dynamic> row) {
  final Object? revisionValue = row['revision'];
  final Object? payloadValue = row['payload'];
  final Object? deviceValue = row['device_id'];
  final Object? updatedValue = row['updated_at'];
  if (revisionValue is! num ||
      payloadValue is! Map<Object?, Object?> ||
      deviceValue is! String ||
      updatedValue is! String) {
    throw const FormatException('The cloud snapshot has an invalid format.');
  }
  final Map<String, Object?> payload = payloadValue.map<String, Object?>(
    (Object? key, Object? value) {
      if (key is! String) {
        throw const FormatException('The cloud snapshot has invalid keys.');
      }
      return MapEntry<String, Object?>(key, value);
    },
  );
  return CloudSnapshot(
    revision: revisionValue.toInt(),
    snapshot: GahundaSnapshot.fromPayload(payload),
    deviceId: deviceValue,
    updatedAtUtc: DateTime.parse(updatedValue).toUtc(),
  );
}
