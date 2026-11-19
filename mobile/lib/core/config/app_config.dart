/// Environment / flavor configuration for the mobile app.
library aph_mobile.core.config;

class AppConfig {
  AppConfig._();

  /// Supabase URL (loaded from environment / .env via dart-define in production).
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://placeholder.supabase.co',
  );

  /// Supabase public anon key (safe to ship in the client).
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'PLACEHOLDER_PUBLIC_ANON_KEY',
  );

  /// Backend API base URL.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.abdulmajeedpharma.example',
  );

  /// Never ship service-role keys in the mobile client.
  static const bool kIsProduction = bool.fromEnvironment(
    'dart.vm.product',
    defaultValue: false,
  );
}
