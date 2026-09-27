enum AccountAvailability { localOnly, cloudReady }

class CloudConfiguration {
  const CloudConfiguration({required this.url, required this.publishableKey});

  const CloudConfiguration.localOnly()
      : url = '',
        publishableKey = '';

  final String url;
  final String publishableKey;

  bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;

  AccountAvailability get availability => isConfigured
      ? AccountAvailability.cloudReady
      : AccountAvailability.localOnly;
}

class AccountUser {
  const AccountUser({
    required this.id,
    required this.email,
    this.displayName,
  });

  final String id;
  final String email;
  final String? displayName;
}

class AccountSignUpResult {
  const AccountSignUpResult({
    required this.emailConfirmationRequired,
    this.user,
  });

  final AccountUser? user;
  final bool emailConfirmationRequired;
}

class GahundaSnapshot {
  const GahundaSnapshot({
    required this.schemaVersion,
    required this.tables,
    required this.fingerprint,
    required this.hasUserData,
  });

  factory GahundaSnapshot.fromPayload(Map<String, Object?> payload) {
    final Object? schemaValue = payload['schema_version'];
    final Object? tablesValue = payload['tables'];
    final Object? fingerprintValue = payload['fingerprint'];
    if (schemaValue is! int || tablesValue is! Map<Object?, Object?>) {
      throw const FormatException('The cloud backup has an invalid format.');
    }
    final Map<String, List<Map<String, Object?>>> tables =
        <String, List<Map<String, Object?>>>{};
    for (final MapEntry<Object?, Object?> entry in tablesValue.entries) {
      final Object? rawTableName = entry.key;
      final Object? rawTableRows = entry.value;
      if (rawTableName is! String || rawTableRows is! List<Object?>) {
        throw const FormatException('The cloud backup contains invalid rows.');
      }
      tables[rawTableName] =
          rawTableRows.map<Map<String, Object?>>((Object? value) {
        if (value is! Map<Object?, Object?>) {
          throw const FormatException(
            'The cloud backup contains an invalid record.',
          );
        }
        return value.map<String, Object?>(
          (Object? key, Object? item) {
            if (key is! String) {
              throw const FormatException(
                'The cloud backup contains an invalid column.',
              );
            }
            return MapEntry<String, Object?>(key, item);
          },
        );
      }).toList(growable: false);
    }
    return GahundaSnapshot(
      schemaVersion: schemaValue,
      tables: Map<String, List<Map<String, Object?>>>.unmodifiable(tables),
      fingerprint: fingerprintValue is String ? fingerprintValue : '',
      hasUserData: payload['has_user_data'] == true,
    );
  }

  final int schemaVersion;
  final Map<String, List<Map<String, Object?>>> tables;
  final String fingerprint;
  final bool hasUserData;

  Map<String, Object?> toPayload() => <String, Object?>{
        'schema_version': schemaVersion,
        'fingerprint': fingerprint,
        'has_user_data': hasUserData,
        'tables': tables,
      };
}

class CloudSnapshot {
  const CloudSnapshot({
    required this.revision,
    required this.snapshot,
    required this.deviceId,
    required this.updatedAtUtc,
  });

  final int revision;
  final GahundaSnapshot snapshot;
  final String deviceId;
  final DateTime updatedAtUtc;
}

class LocalSyncMetadata {
  const LocalSyncMetadata({
    required this.deviceId,
    required this.remoteRevision,
    this.ownerUserId,
    this.baseFingerprint,
    this.lastSyncedAtUtc,
    this.lastError,
  });

  final String? ownerUserId;
  final String deviceId;
  final int remoteRevision;
  final String? baseFingerprint;
  final DateTime? lastSyncedAtUtc;
  final String? lastError;

  LocalSyncMetadata copyWith({
    String? ownerUserId,
    String? deviceId,
    int? remoteRevision,
    String? baseFingerprint,
    DateTime? lastSyncedAtUtc,
    String? lastError,
    bool clearError = false,
  }) {
    return LocalSyncMetadata(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      deviceId: deviceId ?? this.deviceId,
      remoteRevision: remoteRevision ?? this.remoteRevision,
      baseFingerprint: baseFingerprint ?? this.baseFingerprint,
      lastSyncedAtUtc: lastSyncedAtUtc ?? this.lastSyncedAtUtc,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

enum SyncPhase {
  starting,
  localOnly,
  signedOut,
  ready,
  syncing,
  synced,
  conflict,
  accountMismatch,
  error,
}

class SyncState {
  const SyncState({
    required this.phase,
    this.metadata,
    this.user,
    this.message,
    this.cloudConflict,
  });

  const SyncState.starting()
      : phase = SyncPhase.starting,
        metadata = null,
        user = null,
        message = null,
        cloudConflict = null;

  final SyncPhase phase;
  final LocalSyncMetadata? metadata;
  final AccountUser? user;
  final String? message;
  final CloudSnapshot? cloudConflict;

  bool get isLocked =>
      phase == SyncPhase.signedOut || phase == SyncPhase.accountMismatch;
}

class SyncConflictException implements Exception {
  const SyncConflictException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AccountMismatchException implements Exception {
  const AccountMismatchException();

  @override
  String toString() => 'This device is linked to a different Gahunda account.';
}

class CloudNotConfiguredException implements Exception {
  const CloudNotConfiguredException();

  @override
  String toString() => 'Cloud synchronization has not been configured.';
}
