import 'package:flutter/foundation.dart';

/// Single source of truth for DTF API host and versions.
///
/// If DTF bumps an API version or moves the host, change it HERE only — every
/// request is built through [url]. Versions are intentionally per-feature
/// because DTF serves different routes on different versions.
class ApiConfig {
  static const _environment = String.fromEnvironment('ENV');
  static const _directHost = 'https://api.dtf.ru';
  static const _webProxyHost =
      'https://dtf-api-proxy.testg-dtf-by-vino.workers.dev';

  // Per-feature API versions (as observed in the DTF web client).
  static const vDefault = 'v2.31'; // feed, content, profile, search, bookmarks…
  static const vComments = 'v2.10'; // comments tree, reactions (react)
  static const vAssets = 'v2.9'; // reaction image registry
  static const vEditor =
      'v2.11'; // editor (POST editor, POST editor/{id}/publish)
  static const vMessenger =
      'v2.1'; // direct messages (/m/channels, /m/messages, /m/send)

  // Network behaviour
  static const timeout = Duration(seconds: 20);
  static const userAgent = 'dtf-app/2.0.0 (Android; ru)';

  /// Build a full URL: [path] is the route after the version, e.g. 'feed?count=10'.
  static Uri url(
    String path, {
    String version = vDefault,
    bool useDevWebProxy = false,
  }) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    final host = useDevWebProxy && kIsWeb && _environment == 'dev'
        ? _webProxyHost
        : _directHost;
    return Uri.parse('$host/$version/$clean');
  }
}
