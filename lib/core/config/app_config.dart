class AppConfig {
  const AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const youtubeApiKey = String.fromEnvironment('YOUTUBE_API_KEY');

  static bool get hasSupabase =>
      supabaseUrl.startsWith('https://') && supabasePublishableKey.isNotEmpty;
}
