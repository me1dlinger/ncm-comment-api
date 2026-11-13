import 'package:ncm_comment_api/model/resource_type.dart';
import 'package:ncm_comment_api/model/song_comment.dart';
import 'package:ncm_comment_api/model/song_info.dart';
import 'package:ncm_comment_api/util/https_utils.dart';

/// Resolves songs and other resources to ids, and reads their details.
///
/// The upstream's comment endpoints only take ids; a caller who knows a song by
/// name has to go through search first. That lookup is the same one review_api
/// did, including its name normalisation and its ranking, so a name that worked
/// there resolves to the same song here.
class ResolveService {
  final UpstreamClient client;

  /// How many candidates a search asks for.
  static const int searchLimit = 30;

  ResolveService(this.client);

  /// The song [songName] (and optionally [artistName], [albumName]) names.
  ///
  /// Candidates are ranked the way review_api ranked them: song + artist +
  /// album, then song + artist, then the song alone, then whatever the search
  /// put first. review_api sent `song/artist` as its only keyword; the search
  /// engine ranks that differently today, putting covers and re-uploads first,
  /// so the plain name is tried first and the album, when a caller knows it,
  /// narrows the search to the original recording.
  Future<(CommentSong, String)?> resolveSong({
    required String songName,
    String artistName = '',
    String albumName = '',
  }) async {
    final wanted = _normalise(songName);
    final wantedArtist = _normalise(artistName);

    // Each attempt is searched in turn, and the best result one of them can
    // return stops the search: an album and artist match beats everything, and
    // a keyword that carries the album is tried before a weaker answer is
    // accepted.
    final attempts = <({String keyword, int rank})>[
      if (albumName.trim().isNotEmpty)
        (keyword: [songName, artistName, albumName].where((v) => v.trim().isNotEmpty).join(' '), rank: 3),
      (keyword: [songName, artistName].where((v) => v.trim().isNotEmpty).join(' '), rank: 2),
    ];

    if (albumName.trim().isEmpty) {
      attempts.sort((a, b) => b.rank.compareTo(a.rank));
    }

    CommentSong? best;
    var bestRank = 0;
    for (final attempt in attempts) {
      if (attempt.rank <= bestRank) {
        continue;
      }
      final songs = await _search(attempt.keyword);
      if (songs.isEmpty) {
        continue;
      }
      final (chosen, rank) = _bestMatch(
        songs,
        wanted: wanted,
        wantedArtist: wantedArtist,
        wantedAlbum: _normalise(albumName),
      );
      if (chosen != null && rank > bestRank) {
        best = chosen;
        bestRank = rank;
      }
      if (bestRank >= 3) {
        break;
      }
    }

    if (best != null) {
      return (best, 'search');
    }

    // Nothing matched by name: review_api fell back to the first search result.
    for (final attempt in attempts) {
      final songs = await _search(attempt.keyword);
      if (songs.isNotEmpty) {
        return (songs.first, 'search');
      }
    }
    return null;
  }

  /// The best of [songs] for the wanted name, artist and album, and how good it
  /// is: 3 for the same name, artist and album, 2 for the same name and artist,
  /// 1 for the name alone, 0 when no song carries the wanted name.
  (CommentSong?, int) _bestMatch(
    List<CommentSong> songs, {
    required String wanted,
    required String wantedArtist,
    required String wantedAlbum,
  }) {
    CommentSong? nameOnly;
    CommentSong? artistMatch;
    CommentSong? fullMatch;

    for (final song in songs) {
      if (_normalise(song.name) != wanted) {
        continue;
      }
      nameOnly ??= song;
      if (wantedArtist.isEmpty || !_normalise(song.artist).contains(wantedArtist)) {
        continue;
      }
      artistMatch ??= song;
      if (wantedAlbum.isNotEmpty && _normalise(song.album) == wantedAlbum) {
        fullMatch ??= song;
      }
    }

    if (fullMatch != null) {
      return (fullMatch, 3);
    }
    if (artistMatch != null) {
      return (artistMatch, 2);
    }
    if (nameOnly != null) {
      return (nameOnly, 1);
    }
    return (null, 0);
  }

  /// Songs for [keyword], from `/cloudsearch` first and `/search` after it.
  ///
  /// `/cloudsearch` is the search api-enhanced documents as the more complete
  /// one, and it reaches further: a Chinese keyword that `/search` answers a
  /// single hit for comes back as a full page from it. `/search` stays as the
  /// fallback for an api-enhanced that lacks `/cloudsearch`.
  Future<List<CommentSong>> _search(String keyword) async {
    final cloud = await client.get('/cloudsearch', {
      'keywords': keyword,
      'type': 1,
      'limit': searchLimit,
    });
    if (cloud.ok) {
      final songs = _songsOf(cloud.map?['result']);
      if (songs.isNotEmpty) {
        return songs;
      }
    }

    final plain = await client.get('/search', {
      'keywords': keyword,
      'type': 1,
      'limit': searchLimit,
    });
    if (!plain.ok) {
      return const [];
    }
    return _songsOf(plain.map?['result']);
  }

  /// The song records inside a search `result`; both search endpoints name the
  /// list `songs`, but a record may carry the long or the short field names.
  static List<CommentSong> _songsOf(Object? result) {
    if (result is! Map) {
      return const [];
    }
    final rawSongs = result['songs'];
    if (rawSongs is! List) {
      return const [];
    }

    final songs = <CommentSong>[];
    for (final raw in rawSongs) {
      final song = CommentSong.fromSearch(raw);
      if (song.id.isEmpty || song.id == '0') {
        continue;
      }
      songs.add(song);
    }
    return songs;
  }

  /// The song record behind an id, from `/song/detail`.
  Future<CommentSong?> songDetail(String id) async {
    final response = await client.get('/song/detail', {'ids': id});
    if (!response.ok) {
      return null;
    }
    final songs = response.map?['songs'];
    if (songs is! List || songs.isEmpty) {
      return null;
    }
    final song = CommentSong.fromDetail(songs.first);
    return song.id.isEmpty ? null : song;
  }

  /// Comment counts for one resource id, from `/comment/info/list`.
  ///
  /// The endpoint reports the comment numbers the resource page shows. It
  /// answers zeros rather than failing for a resource without a comment
  /// thread, so the caller must not read a zero as "unknown".
  Future<Map<String, dynamic>?> commentInfo(ResourceType type, String id) async {
    final response = await client.get('/comment/info/list', {
      'type': type.code,
      'ids': id,
    });
    if (!response.ok) {
      return null;
    }
    final data = response.map?['data'];
    if (data is! List || data.isEmpty) {
      return null;
    }
    final first = data.first;
    return first is Map ? first.cast<String, dynamic>() : null;
  }

  /// Search hits for [keywords], as `/api-enhanced`'s `/search` ranks them.
  ///
  /// [type] is api-enhanced's search type: 1 songs, 100 artists, 10
  /// albums, 1000 playlists, 1002 users, 1004 MVs. Only the fields a
  /// client needs to pick a result are kept.
  Future<List<SearchResult>> search(String keywords, {int type = 1, int limit = 30}) async {
    final response = await client.get('/search', {
      'keywords': keywords,
      'type': type,
      'limit': limit,
    });
    if (!response.ok) {
      return const [];
    }
    final result = response.map?['result'];
    if (result is! Map) {
      return const [];
    }

    // Each search type names its list differently, and the records inside it too.
    final (key, kind) = switch (type) {
      1 => ('songs', 'song'),
      10 => ('albums', 'album'),
      100 => ('artists', 'artist'),
      1000 => ('playlists', 'playlist'),
      1004 => ('mvs', 'mv'),
      1002 => ('userprofiles', 'user'),
      _ => ('songs', 'song'),
    };
    final rawList = result[key];
    if (rawList is! List) {
      return const [];
    }

    final results = <SearchResult>[];
    for (final raw in rawList) {
      final hit = SearchResult.fromRaw(kind, raw);
      if (hit.id.isNotEmpty && hit.id != '0') {
        results.add(hit);
      }
    }
    return results;
  }

  /// How many listeners liked (hearted) the song [id], from `/song/red/count`;
  /// -1 when the upstream does not say.
  Future<int> redCount(String id) async {
    final response = await client.get('/song/red/count', {'id': id});
    final data = response.map?['data'];
    if (data is! Map) {
      return -1;
    }
    return Json.toInt(data['count']);
  }

  /// The upstream's rendering of names before they are compared.
  ///
  /// review_api stripped the punctuation that differs between a search result
  /// and a caller's typing, then compared the strings exactly.
  static String _normalise(String input) {
    if (input.trim().isEmpty) {
      return '';
    }
    return input
        .replaceAll('&', '/')
        .replaceAll(';', '/')
        .replaceAll('、', '/')
        .replaceAll(r'\', '/')
        .replaceAll(',', '/')
        .replaceAll('《', '')
        .replaceAll('》', ' ')
        .replaceAll(' ', '');
  }
}
