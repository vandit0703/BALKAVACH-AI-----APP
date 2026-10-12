import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time client configuration.
///
/// Only non-secret values belong here. Pass overrides with
/// `--dart-define=API_BASE_URL=https://...`.
class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() {
    const raw = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: defaultApiBaseUrl,
    );
    return AppConfig(apiBaseUrl: normalizeBaseUrl(raw));
  }

  static const defaultApiBaseUrl = 'https://balkavach-ai-app.onrender.com';

  /// Server origin without a trailing slash, e.g. `https://host`.
  final String apiBaseUrl;

  String get apiV1BaseUrl => '$apiBaseUrl/api/v1';

  /// Trims whitespace and trailing slashes and rejects non-http(s) URLs.
  static String normalizeBaseUrl(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.host.isEmpty) {
      throw ArgumentError.value(raw, 'API_BASE_URL', 'must be an http(s) URL');
    }
    return value;
  }
}

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);
