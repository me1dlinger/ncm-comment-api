import 'dart:async';

/// A tiny in-memory cache: values live for [ttl] and concurrent misses for the
/// same key share the one in-flight lookup.
///
/// The comment service makes several upstream calls per request and users tend
/// to ask for the same song over and over, so a short TTL removes most of the
/// repeat traffic without ever serving stale content for long.
class TtlCache {
  final Map<String, _Entry> _entries = {};
  final Map<String, Future<dynamic>> _inflight = {};

  /// Size cap, so a long running process cannot grow without bound.
  static const int _maxEntries = 2048;

  /// Runs [load] for [key], reusing a fresh value or an in-flight lookup.
  ///
  /// [cacheable] decides whether a loaded value is worth keeping; a failure is
  /// never kept.
  Future<T> run<T>(
    String key,
    Future<T> Function() load, {
    required Duration ttl,
    bool Function(T value)? cacheable,
  }) {
    if (ttl <= Duration.zero) {
      return load();
    }

    final now = DateTime.now();
    final cached = _entries[key];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return Future<T>.value(cached.value as T);
    }
    if (cached != null) {
      _entries.remove(key);
    }

    final pending = _inflight[key];
    if (pending != null) {
      return pending.then((value) => value as T);
    }

    final future = load().then<T>((value) {
      if (cacheable == null || cacheable(value)) {
        _store(key, value, now.add(ttl));
      }
      return value;
    }).whenComplete(() {
      _inflight.remove(key);
    });

    _inflight[key] = future;
    return future;
  }

  void _store(String key, Object? value, DateTime expiresAt) {
    if (_entries.length >= _maxEntries) {
      _entries.removeWhere((_, entry) => !entry.expiresAt.isAfter(DateTime.now()));
      // Still full of live entries: drop the oldest quarter.
      if (_entries.length >= _maxEntries) {
        final keys = _entries.keys.take(_entries.length ~/ 4).toList();
        for (final key in keys) {
          _entries.remove(key);
        }
      }
    }
    _entries[key] = _Entry(value, expiresAt);
  }

  void clear() {
    _entries.clear();
  }
}

class _Entry {
  final Object? value;
  final DateTime expiresAt;

  const _Entry(this.value, this.expiresAt);
}
