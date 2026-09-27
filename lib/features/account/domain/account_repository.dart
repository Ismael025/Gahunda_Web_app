import 'account_entities.dart';

abstract interface class AccountRepository {
  AccountUser? get currentUser;

  Stream<AccountUser?> watchUser();

  Future<AccountSignUpResult> signUp({
    required String email,
    required String password,
    required String displayName,
  });

  Future<AccountUser> signIn({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

abstract interface class SyncRemoteGateway {
  Future<CloudSnapshot?> fetchSnapshot();

  Future<CloudSnapshot> saveSnapshot({
    required GahundaSnapshot snapshot,
    required int expectedRevision,
    required String deviceId,
  });
}

abstract interface class LocalSnapshotStore {
  Future<LocalSyncMetadata> loadMetadata();

  Future<LocalSyncMetadata> claimOwner(String userId);

  Future<void> saveMetadata(LocalSyncMetadata metadata);

  Future<GahundaSnapshot> exportSnapshot();

  Future<void> importSnapshot(GahundaSnapshot snapshot);
}
