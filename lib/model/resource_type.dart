/// The NetEase resource kinds a comment can belong to.
///
/// api-enhanced's `resourceTypeMap` maps the numbers its comment endpoints take
/// to the thread id prefixes NetEase uses; this table is the same one, plus the
/// name and the endpoints that serve each kind, so the routes can be written once
/// for every resource.
enum ResourceType {
  song(0, 'R_SO_4_', 'song', '/comment/music'),
  mv(1, 'R_MV_5_', 'mv', '/comment/mv'),
  playlist(2, 'A_PL_0_', 'playlist', '/comment/playlist'),
  album(3, 'R_AL_3_', 'album', '/comment/album'),
  dj(4, 'A_DJ_1_', 'dj', '/comment/dj'),
  video(5, 'R_VI_62_', 'video', '/comment/video');

  /// The number api-enhanced's `type` parameter takes.
  final int code;

  /// The prefix NetEase's thread ids carry, as in `R_SO_4_186016`.
  final String threadPrefix;

  /// The name used in paths and in answers.
  final String name;

  /// The api-enhanced endpoint that lists this kind's comments the old way
  /// (hot comments plus ordinary ones, unpageable).
  final String legacyPath;

  const ResourceType(this.code, this.threadPrefix, this.name, this.legacyPath);

  /// The thread id of [id] on this resource kind.
  String thread(String id) => '$threadPrefix$id';

  /// Looks a kind up by its path name (`song`, `mv`, ...).
  static ResourceType? byName(String? value) {
    if (value == null) {
      return null;
    }
    final needle = value.trim().toLowerCase();
    for (final type in ResourceType.values) {
      if (type.name == needle) {
        return type;
      }
    }
    return null;
  }

  /// Looks a kind up by the number api-enhanced takes. Accepts `"0"` and `"song"`
  /// alike, because both are in the wild.
  static ResourceType? byNumber(String? value) {
    if (value == null) {
      return null;
    }
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      return byName(value);
    }
    for (final type in ResourceType.values) {
      if (type.code == parsed) {
        return type;
      }
    }
    return null;
  }
}
