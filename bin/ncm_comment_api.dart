import 'dart:io';

import 'package:ncm_comment_api/app.dart';
import 'package:ncm_comment_api/app_config.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Starts the service.
///
/// The configuration comes from `config.conf` and the environment:
/// `wyy_api_base_url`, `default_port`, `username`, `password`, and the optional
/// timeout, reply limit and cache settings.
Future<void> main(List<String> args) async {
  final config = await AppConfig.load();
  final app = withMiddleware(buildApp(config: config));

  final server = await shelf_io.serve(app, InternetAddress.anyIPv4, config.port);
  stdout.writeln('ncm-comment-api listening on port ${server.port}');
  stdout.writeln('upstream: ${config.wyyApiBaseUrl}');
  if (config.authRequired) {
    stdout.writeln('token required (username/password configured)');
  }
}
