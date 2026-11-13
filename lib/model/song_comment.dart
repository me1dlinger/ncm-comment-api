/// Comment models, and the JSON shape they are served in.
///
/// The wire format is review_api's, extended rather than replaced: a caller that
/// only knows `nick`, `avatarurl`, `content`, `praiseNum`, `createTime`,
/// `commentId`, `type` and `id` keeps working, because those fields keep their
/// names and types. Everything else is additional, so an old client can ignore
/// it.
library;

/// Small, forgiving conversion helpers shared by the models.
///
/// NetEase sends numbers as numbers, as strings, and occasionally not at all, so
/// every field is parsed leniently instead of cast.
class Json {
  const Json._();

  /// A `code` field as an int, 0 when it is not one.
  static int code(Map<dynamic, dynamic>? map) => map == null ? 0 : toInt(map['code']);

  static int toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('${value ?? ''}'.trim()) ?? 0;
  }

  static bool toBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    return '${value ?? ''}' == 'true';
  }

  static String toStr(Object? value) => value == null ? '' : '$value';

  /// An `ipLocation` record, which is either a string or `{location: ...}`.
  static String toLocation(Object? value) {
    if (value is Map) {
      return toStr(value['location']);
    }
    return toStr(value);
  }
}

/// One listener, as a comment shows them.
class CommentUser {
  final String userId;
  final String nickname;

  /// The avatar URL, served under review_api's spelling `avatarurl`.
  final String avatarUrl;

  /// Whether the listener is a paid member (VIP / black vinyl).
  final bool isVip;

  /// The upstream's numeric vip type, 0 when it has none.
  final int vipType;

  const CommentUser({
    this.userId = '',
    this.nickname = '',
    this.avatarUrl = '',
    this.isVip = false,
    this.vipType = 0,
  });

  factory CommentUser.fromRaw(Object? raw) {
    if (raw is! Map) {
      return const CommentUser();
    }
    final rights = raw['vipRights'];
    final vipType = Json.toInt(raw['vipType']);

    return CommentUser(
      userId: Json.toStr(raw['userId']),
      nickname: Json.toStr(raw['nickname']),
      avatarUrl: Json.toStr(raw['avatarUrl']),
      // A member has either a vip type or a rights record.
      isVip: vipType > 0 || (rights is Map && rights.isNotEmpty),
      vipType: vipType,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'nickname': nickname,
    'avatarUrl': avatarUrl,
    'isVip': isVip,
    'vipType': vipType,
  };
}

/// A comment.
///
/// [type] follows the convention review_api exposed: `0` and `1` mark a featured
/// comment (`1` is what the newer upstream calls "hot"), `2` is an ordinary one.
/// [replies] carries the second level replies fetched alongside the comment, and
/// [replyCount] says how many there really are, so a client can tell a fully
/// fetched thread from a partial one.
class SongComment {
  /// The resource the comment belongs to (a song id for this service's song
  /// endpoints).
  final String id;

  final String commentId;
  final String content;

  /// Likes. review_api called it `praiseNum`; the upstream calls it `likedCount`.
  final int praiseNum;

  /// Unix seconds, as review_api reported it.
  final int createTime;

  /// The same instant in milliseconds, as the upstream reports it.
  final int createTimeMs;

  /// The date the upstream renders for the comment, e.g. `2014-10-20`.
  final String createTimeStr;

  /// Where the listener wrote it from, when the upstream says.
  final String ipLocation;

  final CommentUser user;

  /// `0` / `1` featured, `2` ordinary.
  final int type;

  /// Whether this comment came from the featured ("hot") section.
  final bool isHot;

  /// The top level comment this one replies to; empty for a top level comment.
  final String parentCommentId;

  /// How many second level replies the comment has in total.
  final int replyCount;

  /// The fetched second level replies; empty when none were asked for or there
  /// are none.
  final List<SongComment> replies;

  /// Whether [replies] holds only the first page of a longer thread.
  final bool repliesHasMore;

  const SongComment({
    this.id = '',
    required this.commentId,
    this.content = '',
    this.praiseNum = 0,
    this.createTime = 0,
    this.createTimeMs = 0,
    this.createTimeStr = '',
    this.ipLocation = '',
    this.user = const CommentUser(),
    this.type = 2,
    this.isHot = false,
    this.parentCommentId = '',
    this.replyCount = 0,
    this.replies = const [],
    this.repliesHasMore = false,
  });

  /// Builds a comment from one upstream record.
  ///
  /// The same record shape serves top level comments (`comment/new`,
  /// `comment/music`, `comment/hot`) and floor replies (`comment/floor`); a
  /// reply says who it answers in `beReplied[0].beRepliedCommentId`, and a top
  /// level comment to a song has `parentCommentId` 0.
  factory SongComment.fromRaw(
    Object? raw, {
    required String songId,
    bool isHot = false,
    bool asReply = false,
    String parentCommentId = '',
  }) {
    if (raw is! Map) {
      return SongComment(commentId: '', id: songId);
    }

    final showFloor = raw['showFloorComment'];
    final showFloorReplies = showFloor is Map ? Json.toInt(showFloor['replyCount']) : 0;
    final replyCount = Json.toInt(raw['replyCount']);

    final timeMs = Json.toInt(raw['time']);
    // The upstream sends milliseconds; review_api divided by 1000. A seconds
    // value (or a missing one) shows up as a too-small number and is left as is.
    final timeSeconds = timeMs > 100000000000 ? timeMs ~/ 1000 : timeMs;

    final beReplied = raw['beReplied'];
    var answered = '';
    if (beReplied is List && beReplied.isNotEmpty && beReplied.first is Map) {
      answered = Json.toStr((beReplied.first as Map)['beRepliedCommentId']);
    }

    final ownParent = Json.toStr(raw['parentCommentId']);
    final parent = parentCommentId.isNotEmpty
        ? parentCommentId
        : asReply
        ? (answered.isNotEmpty ? answered : ownParent)
        : (ownParent == '0' ? '' : ownParent);

    // Featured comments come from `hotComments`; a comment that carries a hot
    // type downstream is honoured too.
    final rawType = raw['type'];
    final type = isHot
        ? 1
        : (rawType == null ? 2 : Json.toInt(rawType));

    return SongComment(
      id: songId,
      commentId: Json.toStr(raw['commentId']),
      content: Json.toStr(raw['content']),
      praiseNum: Json.toInt(raw['likedCount'] ?? raw['praiseNum']),
      createTime: timeSeconds,
      createTimeMs: timeMs,
      createTimeStr: Json.toStr(raw['timeStr']),
      ipLocation: Json.toLocation(raw['ipLocation']),
      user: CommentUser.fromRaw(raw['user']),
      type: type,
      isHot: isHot,
      parentCommentId: parent,
      replyCount: replyCount > showFloorReplies ? replyCount : showFloorReplies,
    );
  }

  SongComment copyWith({
    List<SongComment>? replies,
    bool? repliesHasMore,
    int? replyCount,
  }) {
    return SongComment(
      id: id,
      commentId: commentId,
      content: content,
      praiseNum: praiseNum,
      createTime: createTime,
      createTimeMs: createTimeMs,
      createTimeStr: createTimeStr,
      ipLocation: ipLocation,
      user: user,
      type: type,
      isHot: isHot,
      parentCommentId: parentCommentId,
      replyCount: replyCount ?? this.replyCount,
      replies: replies ?? this.replies,
      repliesHasMore: repliesHasMore ?? this.repliesHasMore,
    );
  }

  /// review_api's field set first, then this service's additions.
  Map<String, dynamic> toJson() => {
    // review_api's fields, unchanged in name and type.
    'id': id,
    'commentId': commentId,
    'nick': user.nickname,
    'avatarurl': user.avatarUrl,
    'content': content,
    'praiseNum': praiseNum,
    'createTime': createTime,
    'type': type,
    // Additions.
    'createTimeMillis': createTimeMs,
    'createTimeStr': createTimeStr,
    'ipLocation': ipLocation,
    'isHot': isHot,
    'avatarUrl': user.avatarUrl,
    'userId': user.userId,
    'isVip': user.isVip,
    'vipType': user.vipType,
    'parentCommentId': parentCommentId,
    'replyCount': replyCount,
    'replies': [for (final reply in replies) reply.toJson()],
    'repliesHasMore': repliesHasMore,
  };
}

/// The song a comment page belongs to.
class CommentSong {
  final String id;
  final String name;
  final String artist;
  final String album;
  final String coverUrl;
  final int durationMs;

  const CommentSong({
    required this.id,
    this.name = '',
    this.artist = '',
    this.album = '',
    this.coverUrl = '',
    this.durationMs = 0,
  });

  bool get isEmpty => id.isEmpty;

  /// How the upstream record names the artists.
  static String joinArtists(Object? raw) {
    if (raw is List) {
      return [for (final item in raw) if (item is Map) Json.toStr(item['name'])].join('/');
    }
    if (raw is Map) {
      return Json.toStr(raw['name']);
    }
    return '';
  }

  /// Builds a song from one search result.
  ///
  /// `/search` and `/cloudsearch` answer the same song with different field
  /// names, and both are read here: `/search` sends `artists`/`album`/`duration`,
  /// `/cloudsearch` sends `ar`/`al`/`dt`, and the `/song/detail` shape used
  /// elsewhere is the short one too.
  factory CommentSong.fromSearch(Object? raw) {
    if (raw is! Map) {
      return const CommentSong(id: '');
    }
    final album = raw['album'] ?? raw['al'];
    final artists = raw['artists'] ?? raw['ar'];
    return CommentSong(
      id: Json.toStr(raw['id']),
      name: Json.toStr(raw['name']),
      artist: joinArtists(artists),
      album: album is Map ? Json.toStr(album['name']) : '',
      coverUrl: album is Map ? Json.toStr(album['picUrl'] ?? album['blurPicUrl']) : '',
      durationMs: Json.toInt(raw['duration'] ?? raw['dt']),
    );
  }

  /// Builds a song from one record of `/song/detail` (same shape as the search
  /// result, but the API uses the short field names `ar`/`al`/`dt` there).
  factory CommentSong.fromDetail(Object? raw) {
    if (raw is! Map) {
      return const CommentSong(id: '');
    }
    final album = raw['al'] ?? raw['album'];
    return CommentSong(
      id: Json.toStr(raw['id']),
      name: Json.toStr(raw['name']),
      artist: joinArtists(raw['ar'] ?? raw['artists']),
      album: album is Map ? Json.toStr(album['name']) : '',
      coverUrl: album is Map ? Json.toStr(album['picUrl'] ?? album['blurPicUrl']) : '',
      durationMs: Json.toInt(raw['dt'] ?? raw['duration']),
    );
  }

  Map<String, dynamic> toJson() => {
    'songId': id,
    'id': id,
    'name': name,
    'artist': artist,
    'album': album,
    'coverUrl': coverUrl,
    'duration': durationMs,
  };
}
