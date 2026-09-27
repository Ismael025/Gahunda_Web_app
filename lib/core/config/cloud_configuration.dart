import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/account/domain/account_entities.dart';

abstract final class GahundaCloudBootstrap {
  static const String _url = String.fromEnvironment('SUPABASE_URL');
  static const String _publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static SupabaseClient? _client;

  static CloudConfiguration get configuration => const CloudConfiguration(
        url: _url,
        publishableKey: _publishableKey,
      );

  static SupabaseClient? get client => _client;

  static Future<void> initialize() async {
    if (!configuration.isConfigured) return;
    await Supabase.initialize(
      url: _url,
      publishableKey: _publishableKey,
    );
    _client = Supabase.instance.client;
  }
}
