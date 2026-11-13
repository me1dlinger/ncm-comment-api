import 'dart:io';

/// Where the NetEase cloud music API lives, which port this service listens on
/// and what credentials a caller has to present.
///
/// The keys are review_api's config.conf keys (`wyy_api_base_url`,
/// `default_port`, `username`, `password`), so an existing deployment's file
/// keeps working. A few extra keys are optional and were not in that file:
/// `upstream_timeout` (seconds, default 30), `max_replies_per_comment`
/// (default 500) and `cache_ttl` (seconds, default 60, 0 disables the cache).
///
/// Environment variables win over the file, same as in review_api:
/// `WYY_API_BASE_URL`, `PORT`, `API_USERNAME`, `API_PASSWORD`, plus
/// `UPSTREAM_TIMEOUT`, `MAX_REPLIES_PER_COMMENT` and `CACHE_TTL`.
class AppConfig {
  /// Base URL of the api-enhanced instance, without a trailing slash.
  final String wyyApiBaseUrl;
  final int port;
  final String username;
  final String password;

  /// How long one upstream request may take.
  final Duration upstreamTimeout;

  /// Upper bound on how many second level replies one request may fetch for
  /// every top level comment on the page; keeps one page from turning into
  /// hundreds of upstream calls.
  final int maxRepliesPerComment;

  /// How long an upstream answer is reused, in seconds. 0 disables.
  final Duration cacheTtl;

  AppConfig({
    required this.wyyApiBaseUrl,
    required this.port,
    required this.username,
    required this.password,
    this.upstreamTimeout = const Duration(seconds: 30),
    this.maxRepliesPerComment = 500,
    this.cacheTtl = const Duration(seconds: 60),
  });

  static const _defaultConfig = '''
[api]
wyy_api_base_url=http://127.0.0.1:3000
default_port=8383
username=
password=
upstream_timeout=30
max_replies_per_comment=500
cache_ttl=60
''';

  static Future<AppConfig> load() async {
    await _ensureConfigFile();

    final fileConfig = await _readIni(File('config.conf')).catchError(
      (Object _) => <String, String>{},
    );

    final base = (Platform.environment['WYY_API_BASE_URL'] ??
            fileConfig['wyy_api_base_url'] ??
            'http://127.0.0.1:3000')
        .trim()
        // A trailing slash would turn into a double slash in every request.
        .replaceFirst(RegExp(r'/+$'), '');

    final port =
        int.tryParse(Platform.environment['PORT'] ?? fileConfig['default_port'] ?? '') ??
            8383;

    final timeout = int.tryParse(
            Platform.environment['UPSTREAM_TIMEOUT'] ??
                fileConfig['upstream_timeout'] ??
                '') ??
        30;

    final maxReplies = int.tryParse(
            Platform.environment['MAX_REPLIES_PER_COMMENT'] ??
                fileConfig['max_replies_per_comment'] ??
                '') ??
        500;

    final cacheTtl =
        int.tryParse(Platform.environment['CACHE_TTL'] ?? fileConfig['cache_ttl'] ?? '') ?? 60;

    return AppConfig(
      wyyApiBaseUrl: base,
      port: port,
      username: (Platform.environment['API_USERNAME'] ?? fileConfig['username'] ?? '').trim(),
      password: (Platform.environment['API_PASSWORD'] ?? fileConfig['password'] ?? '').trim(),
      upstreamTimeout: Duration(seconds: timeout <= 0 ? 30 : timeout),
      maxRepliesPerComment: maxReplies < 0 ? 0 : maxReplies,
      cacheTtl: cacheTtl <= 0 ? Duration.zero : Duration(seconds: cacheTtl),
    );
  }

  /// Whether callers have to present the review_api `token` parameter.
  bool get authRequired => username.isNotEmpty || password.isNotEmpty;

  static Future<void> _ensureConfigFile() async {
    final file = File('config.conf');

    if (await file.exists()) {
      return;
    }

    stdout.writeln('config.conf not found, creating a default one');
    await file.writeAsString('${_defaultConfig.trim()}\n');
  }

  static Future<Map<String, String>> _readIni(File file) async {
    final lines = await file.readAsLines();
    final map = <String, String>{};

    var inApiSection = false;

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.isEmpty || trimmed.startsWith(';') || trimmed.startsWith('#')) {
        continue;
      }

      if (trimmed.startsWith('[')) {
        inApiSection = trimmed == '[api]';
        continue;
      }

      if (!inApiSection) {
        continue;
      }

      final index = trimmed.indexOf('=');
      if (index == -1) {
        continue;
      }

      map[trimmed.substring(0, index).trim()] = trimmed.substring(index + 1).trim();
    }

    return map;
  }
}
