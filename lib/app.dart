import 'dart:io';

import 'package:ncm_comment_api/app_config.dart';
import 'package:ncm_comment_api/router/handlers.dart';
import 'package:ncm_comment_api/service/comment_service.dart';
import 'package:ncm_comment_api/service/resolve_service.dart';
import 'package:ncm_comment_api/util/https_utils.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// The routes this service answers, as one shelf handler.
///
/// The root path keeps its classic comment list; the new queries live under
/// `/api/`. Everything is GET: there is nothing to write.
Handler buildApp({required AppConfig config, UpstreamClient? upstream}) {
  final client = upstream ??
      UpstreamClient(baseUrl: config.wyyApiBaseUrl, timeout: config.upstreamTimeout, cacheTtl: config.cacheTtl);
  final comments = CommentService(client, maxRepliesPerComment: config.maxRepliesPerComment);
  final resolve = ResolveService(client);

  final handlers = Handlers(
    comments: comments,
    resolve: resolve,
    username: config.username,
    password: config.password,
    upstreamUrl: config.wyyApiBaseUrl,
  );

  final router = Router(notFoundHandler: (Request request) => Response.notFound('Page not found'));

  // The classic comment list endpoint, unchanged.
  router.get('/', handlers.commentList);

  // The queries added on top of it.
  router.get('/api/comments', handlers.commentsPage);
  router.get('/api/hot', handlers.hot);
  router.get('/api/replies', handlers.replies);
  router.get('/api/stats', handlers.stats);
  router.get('/api/search', handlers.search);
  router.get('/api/song', handlers.song);

  return router.call;
}

/// Adds request logging, the CORS preflight answer, and a JSON 500 error for
/// anything that throws, so a client never sees an HTML error page.
Handler withMiddleware(Handler app) {
  final pipeline = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors)
      .addMiddleware(_errorAsJson);
  return pipeline.addHandler(app);
}

Handler _cors(Handler inner) => (Request request) async {
  if (request.method == 'OPTIONS') {
    return Response.ok('', headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': '*',
    });
  }
  final response = await inner(request);
  return response.change(headers: {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
  });
};

Handler _errorAsJson(Handler inner) => (Request request) async {
  try {
    return await inner(request);
  } catch (error, stack) {
    stderr.writeln('request failed: $error\n$stack');
    return Response.internalServerError(
      body: '{"code":500,"msg":"internal error","body":null}',
      headers: const {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
    );
  }
};
