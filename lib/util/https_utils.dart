import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:ncm_comment_api/model/song_comment.dart';
import 'package:ncm_comment_api/util/cache.dart';

/// One answer from the NetEase API: the HTTP status plus the decoded body.
///
/// `body` is a decoded JSON map or list when the upstream answered with JSON,
/// and a plain string otherwise. `code` follows review_api's convention: the
/// upstream HTTP status when the upstream answered, and a gateway code when it
/// did not; [unreachable] and [timedOut] tell the two apart.
class XResponse {
  final dynamic body;
  final int code;
  final String msg;

  /// Transport-level failures, reported in place of an HTTP status. The two
  /// are kept distinct so a caller can tell "upstream is down" from
  /// "upstream is too slow".
  static const int unreachable = 502;
  static const int timedOut = 504;

  XResponse({this.body = const {}, this.code = 200, String? msg})
      : msg = msg ?? _message(code);

  bool get ok => code >= 200 && code < 300;

  Map<String, dynamic>? get map => body is Map ? body as Map<String, dynamic> : null;

  List<dynamic>? get list => body is List ? body as List : null;

  /// The NetEase API nests its own status inside an HTTP 200 answer.
  int get upstreamCode {
    final bodyMap = map;
    return bodyMap == null ? 0 : Json.toInt(bodyMap['code']);
  }

  Map<String, dynamic> toJson() => {'body': body, 'code': code, 'msg': msg};

  static String _message(int code) {
    if (code == 400) {
      return 'Bad Request';
    }
    return 'HTTP $code';
  }
}

/// Talks to the NetEase cloud music API.
///
/// One client serves every request and keeps connections alive: a single page
/// of comments may cost several upstream calls (name lookup, comment list, one
/// floor per comment that has replies), so the connection pool is worth reusing.
///
/// Successful answers are cached for [cacheTtl]; concurrent requests for the
/// same URL share one upstream call. [Duration.zero] disables the cache.
class UpstreamClient {
  final String baseUrl;
  final Duration timeout;
  final Duration cacheTtl;

  /// A desktop user agent and a referer are required: the API answers -462 or
  /// an empty body to a bare request.
  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  static const _referer = 'https://music.163.com/';

  final http.Client _client = http.Client();
  final TtlCache _cache = TtlCache();

  UpstreamClient({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 30),
    this.cacheTtl = const Duration(seconds: 60),
  });

  void close() => _client.close();

  /// GET [path] with [params] appended as a query string.
  ///
  /// Null values are skipped, so optional fields can be passed straight through.
  Future<XResponse> get(String path, [Map<String, dynamic>? params]) async {
    if (baseUrl.isEmpty) {
      return XResponse(code: 400, msg: 'no upstream configured');
    }

    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: {
        for (final entry in (params ?? const <String, dynamic>{}).entries)
          if (entry.value != null) entry.key: '${entry.value}',
      },
    );

    return _cache.run(
      uri.toString(),
      () => _request(uri),
      ttl: cacheTtl,
      cacheable: (response) => response.ok,
    );
  }

  Future<XResponse> _request(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: const {'User-Agent': _userAgent, 'Referer': _referer})
          .timeout(timeout);

      final raw = utf8.decode(response.bodyBytes, allowMalformed: true);

      dynamic body;
      if (raw.startsWith('{') || raw.startsWith('[')) {
        try {
          body = jsonDecode(raw);
        } catch (_) {
          body = raw;
        }
      } else {
        body = raw;
      }

      return XResponse(body: body, code: response.statusCode);
    } on TimeoutException {
      return XResponse(code: XResponse.timedOut);
    } on SocketException {
      return XResponse(code: XResponse.unreachable);
    } on FormatException {
      return XResponse(code: XResponse.unreachable);
    } on http.ClientException {
      return XResponse(code: XResponse.unreachable);
    } on HttpException {
      return XResponse(code: XResponse.unreachable);
    }
  }
}
