class LocalBackendConfig {
  const LocalBackendConfig._();

  static const bool enabled = bool.fromEnvironment(
    'LOCAL_BACKEND_ENABLED',
    defaultValue: false,
  );

  static const String httpBaseUrl = String.fromEnvironment(
    'LOCAL_BACKEND_HTTP_URL',
    defaultValue: '',
  );

  static const String wsBaseUrl = String.fromEnvironment(
    'LOCAL_BACKEND_WS_URL',
    defaultValue: '',
  );

  static bool get hasHttp => enabled && httpBaseUrl.trim().isNotEmpty;
  static bool get hasWebSocket => enabled && wsBaseUrl.trim().isNotEmpty;

  static Uri? apiUri(String path) {
    if (!hasHttp) return null;
    final normalizedBase = httpBaseUrl.endsWith('/')
        ? httpBaseUrl
        : '$httpBaseUrl/';
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse(normalizedBase).resolve(normalizedPath);
  }

  static String? websocketUrlForDevice(String deviceId) {
    if (!hasWebSocket) return null;
    final uri = Uri.tryParse(wsBaseUrl.trim());
    if (uri == null) return null;

    final query = Map<String, String>.from(uri.queryParameters);
    query['deviceId'] = deviceId;
    return uri.replace(queryParameters: query).toString();
  }
}
