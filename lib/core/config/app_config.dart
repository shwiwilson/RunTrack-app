import 'dart:convert';

/// Browser configuration contains only a public Supabase key. Secrets are
/// rejected here as a second guard against an accidental deployment mistake.
class AppConfig {
  const AppConfig({required this.supabaseUrl, required this.publishableKey});

  factory AppConfig.fromEnvironment() => const AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    publishableKey: String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
    ),
  );

  final String supabaseUrl;
  final String publishableKey;

  String? get validationError {
    final uri = Uri.tryParse(supabaseUrl);
    final local = uri?.host == 'localhost' || uri?.host == '127.0.0.1';
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && !(local && uri.scheme == 'http'))) {
      return 'RunTrack needs its Supabase project URL before it can open. '
          'Follow the deployment guide to configure this website.';
    }
    if (publishableKey.startsWith('sb_publishable_')) return null;
    try {
      final segments = publishableKey.split('.');
      if (segments.length == 3) {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
        );
        if (payload is Map && payload['role'] == 'anon') return null;
      }
    } catch (_) {
      // An invalid key is a deployment error, never a reason to use fake data.
    }
    return 'RunTrack needs a Supabase publishable key. Secret and service-role '
        'keys must never be used in the website.';
  }
}
