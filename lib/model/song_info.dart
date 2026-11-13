import 'package:ncm_comment_api/model/song_comment.dart';

/// A song as `/api/song` and search answers describe it, plus the comment
/// numbers that make it worth looking at.
class SongInfo {
  final CommentSong song;

  /// How many comments the song has, from `/comment/info/list`; 0 when unknown.
  final int commentCount;

  final String commentCountDesc;

  /// How many listeners liked (hearted) the song, from `/song/red/count`;
  /// negative when unknown.
  final int likedCount;

  const SongInfo({
    required this.song,
    this.commentCount = 0,
    this.commentCountDesc = '',
    this.likedCount = -1,
  });

  Map<String, dynamic> toJson() => {
    'songId': song.id,
    'id': song.id,
    'name': song.name,
    'artist': song.artist,
    'album': song.album,
    'coverUrl': song.coverUrl,
    'duration': song.durationMs,
    'commentCount': commentCount,
    'commentCountDesc': commentCountDesc,
    'likedCount': likedCount,
  };
}

/// One hit of `/api/search`: either a song, an artist, an album, a playlist or
/// a user, as the caller asked for.
class SearchResult {
  /// `song`, `artist`, `album`, `playlist`, `mv`, `user`.
  final String kind;

  final String id;
  final String name;
  final String artist;
  final String album;
  final String coverUrl;

  /// Songs only: milliseconds.
  final int duration;

  /// How many comments the resource has, when the caller asked for counts and
  /// the resource type supports it; negative when unknown.
  final int commentCount;

  /// How many listeners follow the resource (fans for an artist, subscribers
  /// for a playlist, play count for a song). Negative when unknown.
  final int popularity;

  const SearchResult({
    required this.kind,
    required this.id,
    required this.name,
    this.artist = '',
    this.album = '',
    this.coverUrl = '',
    this.duration = 0,
    this.commentCount = -1,
    this.popularity = -1,
  });

  /// Builds a hit from one record of a search answer; the field names differ
  /// between search types, so each kind is read by its own shape.
  factory SearchResult.fromRaw(String kind, Object? raw) {
    final map = raw is Map ? raw : const {};

    switch (kind) {
      case 'song':
        final song = CommentSong.fromSearch(map);
        return SearchResult(
          kind: kind,
          id: song.id,
          name: song.name,
          artist: song.artist,
          album: song.album,
          coverUrl: song.coverUrl,
          duration: song.durationMs,
        );
      case 'artist':
        return SearchResult(
          kind: kind,
          id: Json.toStr(map['id']),
          name: Json.toStr(map['name']),
          artist: map['alias'] is List
              ? [for (final alias in map['alias'] as List) Json.toStr(alias)].join('/')
              : '',
          coverUrl: Json.toStr(map['picUrl'] ?? map['img1v1Url']),
        );
      case 'album':
        return SearchResult(
          kind: kind,
          id: Json.toStr(map['albumId'] ?? map['id']),
          name: Json.toStr(map['albumName'] ?? map['name']),
          artist: CommentSong.joinArtists(map['artist'] ?? map['artists']),
          coverUrl: Json.toStr(map['picUrl'] ?? map['blurPicUrl']),
        );
      case 'playlist':
        return SearchResult(
          kind: kind,
          id: Json.toStr(map['id']),
          name: Json.toStr(map['name']),
          artist: map['creator'] is Map ? Json.toStr((map['creator'] as Map)['nickname']) : '',
          coverUrl: Json.toStr(map['coverImgUrl'] ?? map['picUrl']),
        );
      case 'mv':
        return SearchResult(
          kind: kind,
          id: Json.toStr(map['id']),
          name: Json.toStr(map['name']),
          artist: CommentSong.joinArtists(map['artistName'] ?? map['artists']),
          coverUrl: Json.toStr(map['cover'] ?? map['picUrl']),
          duration: Json.toInt(map['duration']),
        );
      default:
        // A user: the nickname is the name, the avatar the cover.
        return SearchResult(
          kind: 'user',
          id: Json.toStr(map['userId'] ?? map['id']),
          name: Json.toStr(map['nickname'] ?? map['name']),
          coverUrl: Json.toStr(map['avatarUrl'] ?? map['picUrl']),
        );
    }
  }

  /// A copy carrying the numbers a second request found.
  SearchResult withNumbers({int? comments, int? popularity}) => SearchResult(
    kind: kind,
    id: id,
    name: name,
    artist: artist,
    album: album,
    coverUrl: coverUrl,
    duration: duration,
    commentCount: comments ?? commentCount,
    popularity: popularity ?? this.popularity,
  );

  SearchResult withCommentCount(int count) => SearchResult(
    kind: kind,
    id: id,
    name: name,
    artist: artist,
    album: album,
    coverUrl: coverUrl,
    duration: duration,
    commentCount: count,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'name': name,
    'artist': artist,
    'album': album,
    'coverUrl': coverUrl,
    'duration': duration,
    'commentCount': commentCount,
  };
}
