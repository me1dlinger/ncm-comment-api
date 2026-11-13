import 'package:ncm_comment_api/model/resource_type.dart';
import 'package:ncm_comment_api/model/song_comment.dart';

/// How a comment page is ordered.
enum CommentSort {
  /// What the song page shows by default: the upstream's own ranking.
  recommended('recommended', 99),

  /// By likes, most liked first.
  hot('hot', 2),

  /// Newest first.
  time('time', 3);

  /// The name callers pass and answers repeat.
  final String name;

  /// The api-enhanced `sortType` number behind it.
  final int apiSortType;

  const CommentSort(this.name, this.apiSortType);

  /// Accepts the names above, and the numbers api-enhanced takes (1 and 954 mean
  /// recommended, 2 hot, 3 time) so a client can pass whichever it knows.
  static CommentSort parse(Object? value, {CommentSort fallback = CommentSort.recommended}) {
    if (value == null) {
      return fallback;
    }
    final text = '$value'.trim().toLowerCase();
    for (final sort in CommentSort.values) {
      if (sort.name == text) {
        return sort;
      }
    }
    final number = int.tryParse(text);
    switch (number) {
      case 1:
      case 99:
        return CommentSort.recommended;
      case 2:
        return CommentSort.hot;
      case 3:
        return CommentSort.time;
    }
    return fallback;
  }
}

/// What a caller asks the service for: one page of comments on one resource.
///
/// The HTTP layer builds this from query parameters; see docs/API.md.
class CommentQuery {
  final ResourceType type;

  /// The resource id. Empty when the resource still has to be resolved from
  /// [songName].
  final String id;

  final String songName;
  final String artistName;
  final String albumName;

  /// 1 based page number, as a person counts pages.
  final int page;

  /// Top level comments per page.
  final int pageSize;

  final CommentSort sort;

  /// For [CommentSort.time]: the upstream pages by the timestamp of the
  /// previous page's last comment, and a caller passes it back verbatim.
  final String? cursor;

  /// Whether featured comments are put in front of the first page.
  final bool includeHot;

  /// How many second level replies to attach to every comment that has any.
  /// Zero fetches none, which keeps a page down to one upstream call.
  final int repliesPerComment;

  const CommentQuery({
    this.type = ResourceType.song,
    this.id = '',
    this.songName = '',
    this.artistName = '',
    this.albumName = '',
    this.page = 1,
    this.pageSize = 20,
    this.sort = CommentSort.recommended,
    this.cursor,
    this.includeHot = true,
    this.repliesPerComment = 3,
  });

  bool get resolvesByName => id.isEmpty && songName.isNotEmpty;

  /// 0 based page index, the value api-enhanced takes as `pageNo`.
  int get pageNo => page > 0 ? page - 1 : 0;

  /// Offset into the flat comment list.
  int get offset => pageNo * pageSize;

  CommentQuery copyWith({
    String? id,
    String? songName,
    String? artistName,
    String? albumName,
    int? page,
    int? pageSize,
    CommentSort? sort,
    String? cursor,
    bool? includeHot,
    int? repliesPerComment,
  }) {
    return CommentQuery(
      type: type,
      id: id ?? this.id,
      songName: songName ?? this.songName,
      artistName: artistName ?? this.artistName,
      albumName: albumName ?? this.albumName,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      sort: sort ?? this.sort,
      cursor: cursor ?? this.cursor,
      includeHot: includeHot ?? this.includeHot,
      repliesPerComment: repliesPerComment ?? this.repliesPerComment,
    );
  }
}

/// One page of comments on a resource: what the service hands the HTTP layer.
class CommentPage {
  final ResourceType type;

  /// The resource id the page belongs to; for a song resolved from a name, the
  /// id the name became.
  final String id;

  /// `search`, `song_detail` or `id`: how [id] was found.
  final String resolvedBy;

  /// The song record, when the resource is a song and one was looked up.
  final CommentSong? song;

  /// The id as review_api answered it: the song id for a song, the resource id
  /// otherwise. [id] is the same value, kept under the name the new endpoints
  /// use.
  final String songId;

  /// How many comments the resource has as the upstream counts them; -1 when
  /// it did not say.
  final int total;

  /// 0 based page index, and the 1 based number, both in the answer.
  final int pageNo;
  final int page;

  final int pageSize;

  /// How many pages there are at this size; -1 when [total] is unknown.
  final int pageCount;

  final bool hasMore;

  /// The order the page was asked for in, by name.
  final String sort;

  /// Where a time ordered page continues; null for other orders.
  final String? nextCursor;

  /// How many second level replies were fetched per comment, 0 when off.
  final int repliesPerComment;

  final List<SongComment> hotComments;
  final List<SongComment> comments;

  const CommentPage({
    required this.type,
    required this.id,
    required this.songId,
    this.resolvedBy = 'id',
    this.song,
    this.total = -1,
    this.pageNo = 0,
    this.page = 1,
    this.pageSize = 20,
    this.pageCount = -1,
    this.hasMore = false,
    this.sort = 'recommended',
    this.nextCursor,
    this.repliesPerComment = 0,
    this.hotComments = const [],
    this.comments = const [],
  });

  /// The page as an API answer body.
  Map<String, dynamic> toJson() => {
    'song': (song ?? CommentSong(id: id)).toJson(),
    'id': id,
    'type': type.code,
    'typeName': type.name,
    'resolvedBy': resolvedBy,
    'total': total,
    'page': page,
    'pageNo': pageNo,
    'pageSize': pageSize,
    'pageCount': pageCount,
    'hasMore': hasMore,
    'sort': sort,
    'nextCursor': nextCursor,
    'repliesPerComment': repliesPerComment,
    'hotComments': [for (final comment in hotComments) comment.toJson()],
    'comments': [for (final comment in comments) comment.toJson()],
  };
}
