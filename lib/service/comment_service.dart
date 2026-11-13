import 'dart:async';

import 'package:ncm_comment_api/model/resource_type.dart';
import 'package:ncm_comment_api/model/song_comment.dart';
import 'package:ncm_comment_api/service/comment_query.dart';
import 'package:ncm_comment_api/service/resolve_service.dart';
import 'package:ncm_comment_api/util/https_utils.dart';

/// Fetches comments from api-enhanced and shapes them for this API.
///
/// Every read ends in one of three api-enhanced endpoints:
///
/// - `/comment/new` for a page in a chosen order, with the total and, for the
///   time order, the cursor the next page needs;
/// - `/comment/music` (or `/comment/mv`, `/comment/album`, ...) for the featured
///   comments that endpoint answers;
/// - `/comment/floor` for the second level replies under a comment.
///
/// Nothing of api-enhanced's own logic is reproduced here: requests are plain
/// GETs and this class only reads their answers. The resource kind is carried
/// through, so the same code serves a song, an MV, an album, a playlist, a radio
/// programme and a video.
class CommentService {
  final UpstreamClient client;
  final ResolveService resolver;

  /// Hard cap on how many replies are fetched for one page, whatever a caller
  /// asks for: every reply costs an upstream call.
  final int maxRepliesPerComment;

  /// How many upstream calls this service may have in flight at once.
  final int parallelRequests;

  late final _Semaphore _semaphore = _Semaphore(parallelRequests);

  CommentService(this.client, {this.maxRepliesPerComment = 500, this.parallelRequests = 4})
    : resolver = ResolveService(client);

  /// Resolves the resource a query names.
  ///
  /// A query that carries an id is already resolved. A song name goes through
  /// search.
  Future<ResolvedResource?> resolve(CommentQuery query) async {
    if (query.id.isNotEmpty) {
      return ResolvedResource(type: query.type, id: query.id, resolvedBy: 'id');
    }
    if (query.type != ResourceType.song || query.songName.trim().isEmpty) {
      return null;
    }
    final found = await resolver.resolveSong(
      songName: query.songName,
      artistName: query.artistName,
      albumName: query.albumName,
    );
    if (found == null) {
      return null;
    }
    return ResolvedResource(type: query.type, id: found.$1.id, song: found.$1, resolvedBy: found.$2);
  }

  /// One page of comments.
  ///
  /// Replies are attached when asked for; the featured comments are only
  /// fetched for the first page, which is where a client shows them.
  Future<CommentPage> page(CommentQuery query) async {
    final resolved = await resolve(query);
    if (resolved == null) {
      return CommentPage(
        type: query.type,
        id: '',
        songId: '',
        page: 1,
        pageSize: query.pageSize,
        sort: query.sort.name,
        resolvedBy: 'search',
      );
    }

    final page = query.page < 1 ? 1 : query.page;
    final pageSize = query.pageSize < 1 ? 1 : query.pageSize;
    final effective = query.copyWith(page: page, pageSize: pageSize);

    final fetched = await _fetchPage(resolved, effective);

    final repliesPerComment = effective.repliesPerComment.clamp(0, maxRepliesPerComment);
    var comments = fetched.comments;
    if (repliesPerComment > 0 && comments.isNotEmpty) {
      comments = await _attachReplies(resolved, comments, repliesPerComment);
    }

    var hot = const <SongComment>[];
    if (effective.includeHot && effective.pageNo == 0) {
      hot = await hotComments(resolved, limit: pageSize);
    }

    final total = fetched.total;
    return CommentPage(
      type: resolved.type,
      id: resolved.id,
      songId: resolved.song?.id ?? resolved.id,
      song: resolved.song,
      resolvedBy: resolved.resolvedBy,
      total: total,
      pageNo: effective.pageNo,
      page: effective.page,
      pageSize: pageSize,
      pageCount: total >= 0 ? (total + pageSize - 1) ~/ pageSize : -1,
      hasMore: fetched.hasMore,
      sort: effective.sort.name,
      nextCursor: fetched.nextCursor,
      repliesPerComment: repliesPerComment,
      hotComments: hot,
      comments: comments,
    );
  }

  /// Fetches the requested page of top level comments, before replies.
  ///
  /// By likes and by the recommended order, the page number is all the upstream
  /// needs. By time it is not: `comment/new` answers an empty page for any page
  /// past the first unless the request carries a cursor, so a time ordered page
  /// is reached by following the cursor the upstream returns, one page at a
  /// time. A caller can also pass the cursor itself, which reads that page
  /// directly.
  Future<FetchedPage> _fetchPage(ResolvedResource resource, CommentQuery query) async {
    if (query.sort != CommentSort.time) {
      final page = await _fetchOnce(resource, query, upstreamPageNo: query.page, cursor: null);
      // The upstream's recommended ranking (sortType 99) answers only its
      // first page: every later page comes back empty even though the total
      // says more comments exist. Those pages are served from the likes
      // order instead, which does page; the first page keeps the recommended
      // ranking.
      if (query.sort == CommentSort.recommended &&
          page.error == null &&
          page.comments.isEmpty &&
          page.total > 0 &&
          query.page > 1 &&
          query.offset < page.total) {
        final likes = await _fetchOnce(
          resource,
          query.copyWith(sort: CommentSort.hot),
          upstreamPageNo: query.page,
          cursor: null,
        );
        if (likes.comments.isNotEmpty) {
          return likes;
        }
      }
      return page;
    }

    // A caller that passes a cursor reads that one page. Otherwise the pages
    // are walked from the first, and each step asks with the page number it has
    // reached (1 based) and the cursor the previous step returned: the upstream
    // only pages when both agree.
    var cursor = query.cursor;
    final skipped = query.cursor == null ? query.pageNo : 0;

    FetchedPage? page;
    for (var index = 0; index <= skipped; index++) {
      page = await _fetchOnce(resource, query, upstreamPageNo: query.page + (index - skipped), cursor: cursor);
      if (page.error != null) {
        return page;
      }
      if (index < skipped) {
        if (page.nextCursor == null || page.comments.isEmpty) {
          return FetchedPage(comments: const [], total: page.total, hasMore: false);
        }
        cursor = page.nextCursor;
      }
    }
    return page ?? const FetchedPage(comments: [], total: -1, hasMore: false);
  }

  /// One `comment/new` call.
  ///
  /// [upstreamPageNo] is what the upstream gets as `pageNo`, and it is 1 based:
  /// the caller's `page`, never the 0 based index. The cursor order needs it to
  /// grow alongside the cursor, because the upstream ignores a cursor that
  /// arrives on page 1 but pages correctly when the number matches how far the
  /// cursor has walked.
  Future<FetchedPage> _fetchOnce(
    ResolvedResource resource,
    CommentQuery query, {
    required int upstreamPageNo,
    required String? cursor,
  }) {
    return _semaphore.run(() async {
      final response = await client.get('/comment/new', {
        'type': resource.type.code,
        'id': resource.id,
        'pageNo': upstreamPageNo,
        'pageSize': query.pageSize,
        'showInner': true,
        'sortType': query.sort.apiSortType,
        // No cursor on the first page: an absent cursor reads as the start, and
        // leaving it out avoids depending on how the upstream treats `0`.
        'cursor': cursor,
      });

      final data = response.map?['data'];
      if (data is! Map) {
        return FetchedPage.empty(response);
      }

      final rawComments = data['comments'];
      final comments = <SongComment>[];
      if (rawComments is List) {
        for (final raw in rawComments) {
          if (raw is Map) {
            comments.add(SongComment.fromRaw(raw, songId: resource.id));
          }
        }
      }

      final total = Json.toInt(data['totalCount']);

      // The time order hands back its own cursor; it is what the next page is
      // asked with.
      String? nextCursor;
      if (query.sort == CommentSort.time) {
        final upstreamCursor = Json.toStr(data['cursor']);
        if (comments.isNotEmpty && upstreamCursor.isNotEmpty && upstreamCursor != '0') {
          nextCursor = upstreamCursor;
        }
      }

      // A cursor order says how far it goes in the cursor alone: the page after
      // it may be empty even when the total says more comments exist, because
      // the upstream caps how many pages an order may walk. For the cursor
      // order the answer's own `hasMore` is therefore the one to trust.
      final hasMore = query.sort == CommentSort.time
          ? nextCursor != null
          : Json.toBool(data['hasMore']) || (total > 0 && query.offset + comments.length < total);

      return FetchedPage(
        comments: comments,
        total: total,
        hasMore: comments.isEmpty ? false : hasMore,
        nextCursor: nextCursor,
      );
    });
  }

  /// The featured comments of a resource.
  ///
  /// `/comment/music` and its `/comment/mv` family answer `hotComments`
  /// alongside ordinary comments; only the featured ones are read here. When
  /// that endpoint has no featured section, the top of the likes ordered list
  /// stands in, so a caller still gets the most liked comments.
  Future<List<SongComment>> hotComments(ResolvedResource resource, {int limit = 20}) async {
    final response = await _semaphore.run(
      () => client.get(resource.type.legacyPath, {
        'id': resource.id,
        'limit': limit,
        'offset': 0,
      }),
    );

    final hotComments = response.map?['hotComments'];
    if (hotComments is List) {
      return [
        for (final raw in hotComments)
          if (raw is Map) SongComment.fromRaw(raw, songId: resource.id, isHot: true),
      ];
    }

    final likes = await _semaphore.run(
      () => client.get('/comment/new', {
        'type': resource.type.code,
        'id': resource.id,
        'pageNo': 1,
        'pageSize': limit,
        'sortType': CommentSort.hot.apiSortType,
      }),
    );
    final data = likes.map?['data'];
    final comments = data is Map ? data['comments'] : null;
    if (comments is! List) {
      return const [];
    }
    return [
      for (final raw in comments)
        if (raw is Map) SongComment.fromRaw(raw, songId: resource.id, isHot: true),
    ];
  }

  /// The second level replies under one comment.
  ///
  /// [time] pages the thread: pass the `createTimeMillis` of the last reply of
  /// the previous page, or -1 (the default) for the first page.
  Future<RepliesPage> fetchReplies(
    ResolvedResource resource,
    String parentCommentId, {
    int limit = 20,
    int time = -1,
  }) {
    return _semaphore.run(() async {
      final response = await client.get('/comment/floor', {
        'type': resource.type.code,
        'id': resource.id,
        'parentCommentId': parentCommentId,
        'time': time,
        'limit': limit,
      });

      final data = response.map?['data'];
      if (data is! Map) {
        return RepliesPage(
          parentCommentId: parentCommentId,
          resourceId: resource.id,
          failed: !response.ok,
        );
      }

      final rawComments = data['comments'];
      final replies = <SongComment>[];
      if (rawComments is List) {
        for (final raw in rawComments) {
          if (raw is Map) {
            replies.add(SongComment.fromRaw(raw, songId: resource.id, asReply: true));
          }
        }
      }

      final hasMore = Json.toBool(data['hasMore']);
      String? nextTime;
      if (hasMore && replies.isNotEmpty) {
        nextTime = '${replies.last.createTimeMs}';
      }

      return RepliesPage(
        parentCommentId: parentCommentId,
        resourceId: resource.id,
        total: Json.toInt(data['totalCount']),
        hasMore: hasMore,
        nextTime: nextTime,
        replies: replies,
      );
    });
  }

  /// Attaches up to [perComment] replies to every comment that has any.
  ///
  /// Each comment costs one upstream call, so they run together, at most
  /// [parallelRequests] at a time. A comment whose floor call fails keeps its own
  /// record and its reply count, so the page still answers with everything that
  /// was readable.
  Future<List<SongComment>> _attachReplies(
    ResolvedResource resource,
    List<SongComment> comments,
    int perComment,
  ) async {
    final futures = <Future<List<SongComment>>>[];
    for (final comment in comments) {
      if (comment.replyCount <= 0) {
        futures.add(Future.value(const <SongComment>[]));
        continue;
      }
      futures.add(
        fetchReplies(resource, comment.commentId, limit: perComment).then(
          (page) => page.replies,
          onError: (Object _) => const <SongComment>[],
        ),
      );
    }

    final replies = await Future.wait(futures);
    final result = <SongComment>[];
    for (var index = 0; index < comments.length; index++) {
      final comment = comments[index];
      final fetched = replies[index];
      result.add(
        fetched.isEmpty
            ? comment
            : comment.copyWith(replies: fetched, repliesHasMore: fetched.length < comment.replyCount),
      );
    }
    return result;
  }
}

/// The resource a query resolved to.
class ResolvedResource {
  final ResourceType type;
  final String id;

  /// The song record, when the resource is a song and one was looked up. A query
  /// that passed an id has none until someone asks for it.
  final CommentSong? song;

  /// `search` or `id`: how [id] was found.
  final String resolvedBy;

  const ResolvedResource({
    required this.type,
    required this.id,
    this.song,
    this.resolvedBy = 'id',
  });
}

/// One page as `/comment/new` answered it, before replies are attached.
class FetchedPage {
  final List<SongComment> comments;
  final int total;
  final bool hasMore;
  final String? nextCursor;

  /// Why the page could not be read: non-null when the upstream refused or was
  /// unreachable. An empty page with `null` here means the song has no comments.
  final String? error;

  const FetchedPage({
    required this.comments,
    required this.total,
    required this.hasMore,
    this.nextCursor,
    this.error,
  });

  factory FetchedPage.empty(XResponse response) => FetchedPage(
    comments: const [],
    total: -1,
    hasMore: false,
    error: response.ok ? null : 'upstream answered ${response.code}: ${response.msg}',
  );
}

/// The second level replies under one comment.
class RepliesPage {
  final String parentCommentId;
  final String resourceId;
  final List<SongComment> replies;

  /// How many replies the thread has in total.
  final int total;
  final bool hasMore;

  /// The `time` value that reads the next page; null when there is no next page.
  final String? nextTime;

  /// Whether the upstream could not be read at all. An empty thread without it
  /// means the comment really has no replies.
  final bool failed;

  const RepliesPage({
    required this.parentCommentId,
    required this.resourceId,
    this.replies = const [],
    this.total = -1,
    this.hasMore = false,
    this.nextTime,
    this.failed = false,
  });
}

/// A counting semaphore: at most [permits] holders at a time.
class _Semaphore {
  final int permits;

  /// How many slots are taken; a waiting task takes the slot it is handed, so
  /// the count only grows when nobody is waiting.
  int _inUse = 0;
  final List<Completer<void>> _waiting = [];

  _Semaphore(this.permits);

  Future<T> run<T>(Future<T> Function() task) async {
    if (_inUse < permits) {
      _inUse++;
    } else {
      final waiter = Completer<void>();
      _waiting.add(waiter);
      await waiter.future;
    }
    try {
      return await task();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _inUse--;
      }
    }
  }
}
