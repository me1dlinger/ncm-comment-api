import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ncm_comment_api/model/resource_type.dart';
import 'package:ncm_comment_api/router/response.dart';
import 'package:ncm_comment_api/model/song_comment.dart';
import 'package:ncm_comment_api/model/song_info.dart';
import 'package:ncm_comment_api/service/comment_query.dart';
import 'package:ncm_comment_api/service/comment_service.dart';
import 'package:ncm_comment_api/service/resolve_service.dart';
import 'package:shelf/shelf.dart';

/// Every endpoint this service answers.
///
/// The root path is the classic comment list: fixed parameters, the same answer
/// shape, the same optional token. The paths under `/api/` add the queries
/// api-enhanced can answer: paging, ordering, hot comments, replies, statistics
/// and search. Every endpoint answers in the same `{code, msg, body}` envelope,
/// so a client parses one shape whatever it asked for. See docs/API.md for the
/// full reference.
///
/// Only GET is served: every endpoint here is a read, and api-enhanced answers
/// reads over GET.
class Handlers {
  final CommentService comments;
  final ResolveService resolve;
  final String username;
  final String password;
  final String upstreamUrl;

  Handlers({
    required this.comments,
    required this.resolve,
    required this.username,
    required this.password,
    required this.upstreamUrl,
  });

  /// The token required when a username or password was configured: sha256 of
  /// `username + password + upstream url`.
  bool get authRequired => username.isNotEmpty || password.isNotEmpty;

  String get serverToken =>
      sha256.convert(utf8.encode('$username$password$upstreamUrl')).toString();

  /// A protected server tells a missing token from a wrong one.
  Response? checkToken(Request request) {
    if (!authRequired) {
      return null;
    }
    final token = param(request, 'token');
    if (token == null) {
      return Response.forbidden('missing token');
    }
    if (token != serverToken) {
      return Response.forbidden('invalid token');
    }
    return null;
  }

  /// GET /
  ///
  /// `?song_name=&singer_name=&album_name=&token=`. The song is looked up by
  /// name and the comments the service can read are answered as a flat list,
  /// featured ones first, in the classic field shape.
  Future<Response> commentList(Request request) async {
    final songName = param(request, 'song_name');
    final singerName = param(request, 'singer_name');

    // Both names are required; a plain-text 400 answers a request without them.
    if (songName == null || singerName == null) {
      return Response.badRequest(body: 'params error');
    }

    final tokenFailure = checkToken(request);
    if (tokenFailure != null) {
      return tokenFailure;
    }

    final albumName = param(request, 'album_name') ?? '';
    final resolved = await resolve.resolveSong(
      songName: songName,
      artistName: singerName,
      albumName: albumName,
    );
    if (resolved == null) {
      return jsonResponse(envelope(const <Object?>[]), status: 200);
    }

    final song = resolved.$1;
    final page = await comments.page(
      CommentQuery(type: ResourceType.song, id: song.id, includeHot: true, repliesPerComment: 0),
    );

    final all = [...page.hotComments, ...page.comments];
    return jsonResponse(envelope([for (final comment in all) comment.toJson()]), status: 200);
  }

  /// GET /api/comments
  ///
  /// One page of comments, by song id or by song name. This is the endpoint a
  /// client pages through: `total`, `pageCount` and `hasMore` say how much more
  /// there is, `sort` picks the order, and replies can be attached.
  Future<Response> commentsPage(Request request) async {
    final tokenFailure = checkToken(request);
    if (tokenFailure != null) {
      return tokenFailure;
    }

    final type = _typeParam(request) ?? ResourceType.song;
    final id = param(request, 'id') ?? param(request, 'song_id');
    final songName = param(request, 'song_name');

    if (id == null && songName == null) {
      return failure(400, 'params error: pass id (or song_id) or song_name');
    }
    if (id == null && type != ResourceType.song) {
      return failure(400, 'params error: only a song can be looked up by name');
    }

    final query = CommentQuery(
      type: type,
      id: id ?? '',
      songName: songName ?? '',
      artistName: param(request, 'singer_name') ?? param(request, 'artist') ?? '',
      albumName: param(request, 'album_name') ?? '',
      page: intParam(request, 'page', fallback: 1, min: 1, max: 1000),
      pageSize: intParam(request, 'pageSize', fallback: 20, min: 1, max: 100),
      sort: CommentSort.parse(param(request, 'sort')),
      cursor: param(request, 'cursor'),
      includeHot: boolParam(request, 'hot', fallback: true),
      repliesPerComment: intParam(request, 'reply_limit', fallback: 3, min: 0, max: 50),
    );

    final page = await comments.page(query);
    if (page.id.isEmpty) {
      return failure(404, 'song not found: ${query.songName}');
    }
    return jsonResponse(envelope(page.toJson()), status: 200);
  }

  /// GET /api/hot
  ///
  /// The featured ("hot") comments of a resource, by id.
  Future<Response> hot(Request request) async {
    final tokenFailure = checkToken(request);
    if (tokenFailure != null) {
      return tokenFailure;
    }
    final resourceOrFailure = await _resourceFrom(request);
    if (resourceOrFailure is Response) {
      return resourceOrFailure;
    }
    final resource = resourceOrFailure as ResolvedResource;

    final limit = intParam(request, 'limit', fallback: 20, min: 1, max: 100);
    final hot = await comments.hotComments(resource, limit: limit);
    return jsonResponse(
      envelope({
        'id': resource.id,
        'type': resource.type.code,
        'typeName': resource.type.name,
        'total': hot.length,
        'hotComments': [for (final comment in hot) comment.toJson()],
      }),
      status: 200,
    );
  }

  /// GET /api/replies
  ///
  /// The second level replies under one comment. `time` reads the next page of
  /// a long thread: pass the `createTimeMillis` of the last reply.
  Future<Response> replies(Request request) async {
    final tokenFailure = checkToken(request);
    if (tokenFailure != null) {
      return tokenFailure;
    }
    final parent = param(request, 'comment_id') ?? param(request, 'parentCommentId');
    if (parent == null) {
      return failure(400, 'params error: pass comment_id');
    }
    final resourceOrFailure = await _resourceFrom(request);
    if (resourceOrFailure is Response) {
      return resourceOrFailure;
    }
    final resource = resourceOrFailure as ResolvedResource;

    final page = await comments.fetchReplies(
      resource,
      parent,
      limit: intParam(request, 'limit', fallback: 20, min: 1, max: 100),
      time: intParam(request, 'time', fallback: -1, min: -1, max: 1 << 53),
    );
    if (page.failed) {
      return failure(502, 'upstream could not be read');
    }

    return jsonResponse(
      envelope({
        'id': resource.id,
        'type': resource.type.code,
        'typeName': resource.type.name,
        'commentId': parent,
        'total': page.total,
        'hasMore': page.hasMore,
        'nextTime': page.nextTime,
        'replies': [for (final reply in page.replies) reply.toJson()],
      }),
      status: 200,
    );
  }

  /// GET /api/stats
  ///
  /// How many comments, likes and shares a resource has, from api-enhanced's
  /// `/comment/info/list`.
  Future<Response> stats(Request request) async {
    final tokenFailure = checkToken(request);
    if (tokenFailure != null) {
      return tokenFailure;
    }
    final resourceOrFailure = await _resourceFrom(request);
    if (resourceOrFailure is Response) {
      return resourceOrFailure;
    }
    final resource = resourceOrFailure as ResolvedResource;

    final info = await resolve.commentInfo(resource.type, resource.id);
    if (info == null) {
      return failure(502, 'upstream could not be read');
    }
    return jsonResponse(
      envelope({
        'id': resource.id,
        'type': resource.type.code,
        'typeName': resource.type.name,
        'threadId': Json.toStr(info['threadId']).isEmpty
            ? resource.type.thread(resource.id)
            : Json.toStr(info['threadId']),
        'commentCount': Json.toInt(info['commentCount']),
        'commentCountDesc': Json.toStr(info['commentCountDesc']),
        'likedCount': Json.toInt(info['likedCount']),
        'shareCount': Json.toInt(info['shareCount']),
        'musicianCommentCount': Json.toInt(info['musicianSaidCount']),
      }),
      status: 200,
    );
  }

  /// GET /api/search
  ///
  /// Songs (and artists, albums, playlists) by keyword. A client that wants to
  /// resolve a name to a song id itself, and then call `/api/comments` by id,
  /// starts here.
  Future<Response> search(Request request) async {
    final tokenFailure = checkToken(request);
    if (tokenFailure != null) {
      return tokenFailure;
    }
    final keywords = param(request, 'keywords') ?? param(request, 'query');
    if (keywords == null) {
      return failure(400, 'params error: pass keywords');
    }

    final type = _searchTypeParam(request);
    final limit = intParam(request, 'limit', fallback: 30, min: 1, max: 100);

    final results = await resolve.search(keywords, type: type, limit: limit);
    return jsonResponse(
      envelope({
        'keywords': keywords,
        'type': type,
        'total': results.length,
        'songs': [for (final result in results) result.toJson()],
      }),
      status: 200,
    );
  }

  /// GET /api/song
  ///
  /// One song by id or by name: its title, artists, album, cover and duration,
  /// plus how many comments and hearts it has.
  Future<Response> song(Request request) async {
    final tokenFailure = checkToken(request);
    if (tokenFailure != null) {
      return tokenFailure;
    }

    final id = param(request, 'id') ?? param(request, 'song_id');
    CommentSong? found;
    if (id != null) {
      found = await resolve.songDetail(id);
    } else {
      final songName = param(request, 'song_name');
      if (songName == null) {
        return failure(400, 'params error: pass id (or song_id) or song_name');
      }
      final resolved = await resolve.resolveSong(
        songName: songName,
        artistName: param(request, 'singer_name') ?? param(request, 'artist') ?? '',
        albumName: param(request, 'album_name') ?? '',
      );
      found = resolved?.$1;
    }
    if (found == null || found.id.isEmpty) {
      return failure(404, 'song not found');
    }

    final info = await resolve.commentInfo(ResourceType.song, found.id);
    final hearts = await resolve.redCount(found.id);
    final song = SongInfo(
      song: found,
      commentCount: info == null ? -1 : Json.toInt(info['commentCount']),
      commentCountDesc: info == null ? '' : Json.toStr(info['commentCountDesc']),
      likedCount: hearts,
    );
    return jsonResponse(envelope(song.toJson()), status: 200);
  }

  /// Turns `id` (and `type`) into a resource, or answers why it could not.
  Future<Object> _resourceFrom(Request request) async {
    final id = param(request, 'id') ?? param(request, 'song_id');
    if (id == null) {
      return failure(400, 'params error: pass id (or song_id)');
    }
    return ResolvedResource(type: _typeParam(request) ?? ResourceType.song, id: id);
  }

  static ResourceType? _typeParam(Request request) {
    final raw = param(request, 'type');
    if (raw == null) {
      return null;
    }
    return ResourceType.byNumber(raw) ?? ResourceType.byName(raw);
  }

  static int _searchTypeParam(Request request) {
    final raw = param(request, 'type');
    if (raw == null) {
      return 1;
    }
    switch (raw.toLowerCase()) {
      case 'artist':
        return 100;
      case 'album':
        return 10;
      case 'playlist':
        return 1000;
      case 'mv':
        return 1004;
      case 'user':
        return 1002;
    }
    return int.tryParse(raw) ?? 1;
  }
}
