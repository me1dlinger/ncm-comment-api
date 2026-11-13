import 'dart:convert';

import 'package:shelf/shelf.dart';

/// The envelope every endpoint answers in.
///
/// The shape is `{"code":200,"msg":"success","body":[...]}`. Every endpoint
/// answers in it, failures included, so a client has one thing to parse
/// whatever it asked for.
Map<String, dynamic> envelope(Object? body, {int code = 200, String msg = 'success'}) => {
  'code': code,
  'msg': msg,
  'body': body,
};

/// The headers every answer carries, including the CORS allowance.
const Map<String, String> apiHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': '*',
  'x-powered-by': 'ncm-comment-api server',
};

/// [payload] as a JSON answer with the API headers.
Response jsonResponse(Map<String, dynamic> payload, {required int status}) =>
    Response(status, body: jsonEncode(payload), headers: apiHeaders);

/// A failure: an envelope with no body, in the same shape as a success.
Response failure(int status, String msg, {Object? body}) =>
    jsonResponse(envelope(body, code: status, msg: msg), status: status);

/// Reads one query parameter, trimmed; empty counts as absent.
String? param(Request request, String name) {
  final value = request.requestedUri.queryParameters[name]?.trim();
  return value == null || value.isEmpty ? null : value;
}

/// Reads an integer parameter, falling back to [fallback] when absent or not a
/// number, and clamped into [min]..[max].
int intParam(Request request, String name, {required int fallback, required int min, required int max}) {
  final raw = param(request, name);
  final parsed = raw == null ? null : int.tryParse(raw);
  final value = parsed ?? fallback;
  return value < min ? min : (value > max ? max : value);
}

/// Reads a boolean parameter: `1`/`true`/`yes`/`on` are true,
/// `0`/`false`/`no`/`off` false, anything else (including absent) [fallback].
bool boolParam(Request request, String name, {required bool fallback}) {
  final raw = param(request, name)?.toLowerCase();
  if (raw == null) {
    return fallback;
  }
  if (raw == '1' || raw == 'true' || raw == 'yes' || raw == 'on') {
    return true;
  }
  if (raw == '0' || raw == 'false' || raw == 'no' || raw == 'off') {
    return false;
  }
  return fallback;
}
