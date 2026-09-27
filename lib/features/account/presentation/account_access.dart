import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../application/account_providers.dart';
import '../domain/account_entities.dart';
import '../domain/account_repository.dart';

Future<void> showAccountPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) => const _AccountPanel(),
  );
}

class AccountGate extends ConsumerWidget {
  const AccountGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SyncState sync = ref.watch(syncControllerProvider);
    if (sync.phase == SyncPhase.starting) {
      return const _AccountSplash();
    }
    if (sync.phase == SyncPhase.error && sync.metadata == null) {
      return _AccountStartupError(message: sync.message);
    }
    final String? owner = sync.metadata?.ownerUserId;
    final bool locked = owner != null && sync.user?.id != owner;
    if (locked) return _LockedAccountPage(sync: sync);
    return child;
  }
}

class AccountAvatarButton extends ConsumerWidget {
  const AccountAvatarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SyncState sync = ref.watch(syncControllerProvider);
    final String initials = _initials(sync.user);
    final bool needsAttention = sync.phase == SyncPhase.conflict ||
        sync.phase == SyncPhase.error ||
        sync.phase == SyncPhase.accountMismatch;
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 12),
      child: IconButton(
        tooltip: 'Account and sync',
        onPressed: () => showAccountPanel(context),
        icon: Badge(
          isLabelVisible: needsAttention,
          backgroundColor: AppColors.danger,
          smallSize: 8,
          child: CircleAvatar(
            radius: 18,
            child: Text(initials),
          ),
        ),
      ),
    );
  }
}

class _AccountSplash extends StatelessWidget {
  const _AccountSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              child: Text(
                'G',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
            ),
            SizedBox(height: 18),
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Opening your local Gahunda data…'),
          ],
        ),
      ),
    );
  }
}

class _AccountStartupError extends StatelessWidget {
  const _AccountStartupError({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.danger,
                      size: 42,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Gahunda could not open safely',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your feature data has not been deleted. Close and reopen the app. If this continues, keep the database file and report the message below.',
                      textAlign: TextAlign.center,
                    ),
                    if (message != null) ...<Widget>[
                      const SizedBox(height: 12),
                      SelectableText(
                        message!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LockedAccountPage extends ConsumerWidget {
  const _LockedAccountPage({required this.sync});

  final SyncState sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool mismatch = sync.phase == SyncPhase.accountMismatch ||
        (sync.user != null &&
            sync.metadata?.ownerUserId != null &&
            sync.user!.id != sync.metadata!.ownerUserId);
    final bool configured = ref.watch(cloudConfigurationProvider).isConfigured;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          child: Text(
                            'G',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        mismatch
                            ? 'Different account detected'
                            : 'Your local data is protected',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mismatch
                            ? 'This device is linked to another Gahunda account. Sign out, then use the account that owns this local data.'
                            : 'Sign in with the account linked to this device. Signing out did not delete your information.',
                      ),
                      const SizedBox(height: 22),
                      if (mismatch)
                        FilledButton.icon(
                          onPressed: () => ref
                              .read(syncControllerProvider.notifier)
                              .signOut(),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Sign out different account'),
                        )
                      else if (!configured)
                        const _CloudSetupNotice()
                      else
                        const _AccountAccessForm(
                          compact: false,
                          allowCreateAccount: false,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountPanel extends ConsumerWidget {
  const _AccountPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SyncState sync = ref.watch(syncControllerProvider);
    final bool configured = ref.watch(cloudConfigurationProvider).isConfigured;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Account and sync',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Your SQLite database remains the working copy. Cloud sync adds backup and safe movement between devices.',
                ),
                const SizedBox(height: 20),
                if (!configured)
                  const _CloudSetupNotice()
                else if (sync.user == null)
                  const _AccountAccessForm(
                    compact: true,
                    allowCreateAccount: true,
                  )
                else
                  _SignedInPanel(sync: sync),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloudSetupNotice extends StatelessWidget {
  const _CloudSetupNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.cloud_off_outlined),
          SizedBox(height: 10),
          Text(
            'Local-only mode',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 5),
          Text(
            'Everything continues to save on this device. Configure the Supabase URL and publishable key when launching the app to enable accounts and cloud sync.',
          ),
        ],
      ),
    );
  }
}

enum _AccessMode { signIn, createAccount }

class _AccountAccessForm extends ConsumerStatefulWidget {
  const _AccountAccessForm({
    required this.compact,
    required this.allowCreateAccount,
  });

  final bool compact;
  final bool allowCreateAccount;

  @override
  ConsumerState<_AccountAccessForm> createState() => _AccountAccessFormState();
}

class _AccountAccessFormState extends ConsumerState<_AccountAccessForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  _AccessMode _mode = _AccessMode.signIn;
  bool _busy = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final AccountRepository repository = ref.read(accountRepositoryProvider);
      if (_mode == _AccessMode.signIn) {
        await repository.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
        _showMessage('Signed in. Gahunda is checking cloud changes.');
      } else {
        final AccountSignUpResult result = await repository.signUp(
          email: _emailController.text,
          password: _passwordController.text,
          displayName: _nameController.text,
        );
        if (result.emailConfirmationRequired) {
          _passwordController.clear();
          setState(() => _mode = _AccessMode.signIn);
          _showMessage(
            'Check your email and confirm the account. The link will return to Gahunda.',
          );
        } else {
          _showMessage('Account created. Your first sync is starting.');
        }
      }
    } on Object catch (error) {
      _showMessage(_accountError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool create = _mode == _AccessMode.createAccount;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.allowCreateAccount) ...<Widget>[
            SegmentedButton<_AccessMode>(
              segments: const <ButtonSegment<_AccessMode>>[
                ButtonSegment<_AccessMode>(
                  value: _AccessMode.signIn,
                  label: Text('Sign in'),
                  icon: Icon(Icons.login_rounded),
                ),
                ButtonSegment<_AccessMode>(
                  value: _AccessMode.createAccount,
                  label: Text('Create account'),
                  icon: Icon(Icons.person_add_alt_1_rounded),
                ),
              ],
              selected: <_AccessMode>{_mode},
              onSelectionChanged: _busy
                  ? null
                  : (Set<_AccessMode> values) {
                      setState(() => _mode = values.single);
                    },
            ),
            const SizedBox(height: 18),
          ],
          if (create) ...<Widget>[
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (String? value) {
                if ((value ?? '').trim().length < 2) {
                  return 'Enter your name.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (String? value) => _validEmail(value ?? '')
                ? null
                : 'Enter a valid email address.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: create ? 'Use at least 8 characters.' : null,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (String? value) {
              if ((value ?? '').isEmpty) return 'Enter your password.';
              if (create && (value ?? '').length < 8) {
                return 'Password must contain at least 8 characters.';
              }
              return null;
            },
            onFieldSubmitted: (_) => _busy ? null : _submit(),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(create ? Icons.person_add_rounded : Icons.login_rounded),
            label: Text(create ? 'Create account' : 'Sign in securely'),
          ),
          if (widget.compact) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'You can close this panel and continue locally without creating an account.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _SignedInPanel extends ConsumerWidget {
  const _SignedInPanel({required this.sync});

  final SyncState sync;

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref, {
    required bool useCloud,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(useCloud ? 'Use cloud copy?' : 'Keep this device copy?'),
        content: Text(
          useCloud
              ? 'The current local working data will be replaced by the latest cloud backup. The cloud copy will not be changed.'
              : 'The latest cloud backup will be replaced by the data currently on this device.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(useCloud ? 'Use cloud copy' : 'Keep device copy'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final SyncController controller = ref.read(syncControllerProvider.notifier);
    if (useCloud) {
      await controller.useCloudCopy();
    } else {
      await controller.keepDeviceCopy();
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your local data will remain on this device and will be locked until this account signs in again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(syncControllerProvider.notifier).signOut();
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AccountUser user = sync.user!;
    final LocalSyncMetadata? metadata = sync.metadata;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(child: Text(_initials(user))),
          title: Text(
            user.displayName ?? user.email,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: user.displayName == null ? null : Text(user.email),
          trailing: _SyncStatusIcon(phase: sync.phase),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _syncTitle(sync.phase),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(sync.message ?? 'Ready to synchronize.'),
              if (metadata?.lastSyncedAtUtc != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  'Last sync: ${_localTimestamp(metadata!.lastSyncedAtUtc!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        if (sync.phase == SyncPhase.conflict) ...<Widget>[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Choose carefully. “Keep device” replaces the cloud backup. “Use cloud” replaces the local working copy.',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton(
                onPressed: () => _resolve(context, ref, useCloud: false),
                child: const Text('Keep device copy'),
              ),
              OutlinedButton(
                onPressed: () => _resolve(context, ref, useCloud: true),
                child: const Text('Use cloud copy'),
              ),
            ],
          ),
        ] else ...<Widget>[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: sync.phase == SyncPhase.syncing
                ? null
                : () => ref.read(syncControllerProvider.notifier).syncNow(),
            icon: sync.phase == SyncPhase.syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(
              sync.phase == SyncPhase.syncing ? 'Syncing…' : 'Sync now',
            ),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _signOut(context, ref),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

class _SyncStatusIcon extends StatelessWidget {
  const _SyncStatusIcon({required this.phase});

  final SyncPhase phase;

  @override
  Widget build(BuildContext context) {
    final (IconData, Color) appearance = switch (phase) {
      SyncPhase.synced => (Icons.cloud_done_outlined, AppColors.secondary),
      SyncPhase.syncing => (Icons.sync_rounded, AppColors.primary),
      SyncPhase.conflict || SyncPhase.error || SyncPhase.accountMismatch => (
          Icons.warning_amber_rounded,
          AppColors.danger
        ),
      _ => (Icons.cloud_outlined, Theme.of(context).colorScheme.outline),
    };
    return Icon(appearance.$1, color: appearance.$2);
  }
}

bool _validEmail(String value) {
  final String email = value.trim();
  final int at = email.indexOf('@');
  return at > 0 && at < email.length - 3 && email.indexOf('.', at) > at + 1;
}

String _accountError(Object error) {
  if (error is AuthException) return error.message;
  if (error is PostgrestException) return error.message;
  return error.toString().replaceFirst('Exception: ', '');
}

String _initials(AccountUser? user) {
  final String source = user?.displayName?.trim().isNotEmpty == true
      ? user!.displayName!
      : user?.email ?? 'Local';
  final List<String> parts = source
      .split(RegExp(r'\s+'))
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
  return source.substring(0, source.length >= 2 ? 2 : 1).toUpperCase();
}

String _syncTitle(SyncPhase phase) => switch (phase) {
      SyncPhase.syncing => 'Synchronizing',
      SyncPhase.synced => 'Up to date',
      SyncPhase.conflict => 'Your copies need a decision',
      SyncPhase.error => 'Sync needs attention',
      SyncPhase.ready => 'Ready to sync',
      _ => 'Cloud backup',
    };

String _localTimestamp(DateTime value) {
  final DateTime local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
