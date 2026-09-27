import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/account_entities.dart';
import '../domain/account_repository.dart';

final class SupabaseAccountRepository implements AccountRepository {
  const SupabaseAccountRepository(this._client);

  final SupabaseClient _client;

  @override
  AccountUser? get currentUser =>
      _accountUser(_client.auth.currentSession?.user);

  @override
  Stream<AccountUser?> watchUser() {
    return _client.auth.onAuthStateChange.map(
      (AuthState state) => _accountUser(state.session?.user),
    );
  }

  @override
  Future<AccountSignUpResult> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final AuthResponse response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: _emailRedirectTo(),
      data: <String, Object?>{'display_name': displayName.trim()},
    );
    return AccountSignUpResult(
      user: _accountUser(response.user),
      emailConfirmationRequired: response.session == null,
    );
  }

  @override
  Future<AccountUser> signIn({
    required String email,
    required String password,
  }) async {
    final AuthResponse response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final AccountUser? user = _accountUser(response.user);
    if (user == null) throw StateError('Sign-in completed without a user.');
    return user;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}

String _emailRedirectTo() {
  if (!kIsWeb) return 'io.gahunda.app://login-callback/';
  return Uri.base.replace(query: null, fragment: null).toString();
}

final class LocalOnlyAccountRepository implements AccountRepository {
  const LocalOnlyAccountRepository();

  @override
  AccountUser? get currentUser => null;

  @override
  Stream<AccountUser?> watchUser() => Stream<AccountUser?>.value(null);

  @override
  Future<AccountSignUpResult> signUp({
    required String email,
    required String password,
    required String displayName,
  }) {
    throw const CloudNotConfiguredException();
  }

  @override
  Future<AccountUser> signIn({
    required String email,
    required String password,
  }) {
    throw const CloudNotConfiguredException();
  }

  @override
  Future<void> signOut() async {}
}

AccountUser? _accountUser(User? user) {
  if (user == null) return null;
  final Object? rawName = user.userMetadata?['display_name'];
  final String? name =
      rawName is String && rawName.trim().isNotEmpty ? rawName.trim() : null;
  return AccountUser(
    id: user.id,
    email: user.email ?? 'Unknown email',
    displayName: name,
  );
}
