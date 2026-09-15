import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers.dart';

/// A small on-disk cache for read-mostly data a screen should still have
/// something to show from when the network is not reachable — the notice
/// board, a snapshot's headline figures, that kind of thing.
///
/// Deliberately not a general offline-writes framework: everything here is a
/// GET result kept around for display, never a queued mutation. Approvals,
/// payments, and anything else transactional stay online-only, per the same
/// reasoning `SecureStore` uses for tokens — this is unauthenticated,
/// non-sensitive, low-stakes data, so plain (unencrypted) `SharedPreferences`
/// is the right tool rather than secure storage.
class JsonCache {
  JsonCache(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = 'cache.';
  static const _tsPrefix = 'cache.ts.';

  /// Saves [value] (anything `jsonEncode` accepts — a map or a list) under
  /// [key], stamped with the time it was written.
  Future<void> write(String key, Object? value) async {
    await _prefs.setString('$_prefix$key', jsonEncode(value));
    await _prefs.setString(
      '$_tsPrefix$key',
      DateTime.now().toIso8601String(),
    );
  }

  /// The last value written under [key], or null if there is none — a first
  /// run, or a cache that was never populated because the request always
  /// succeeded so far.
  Object? read(String key) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// When [key] was last written, for a "last updated" label — never shown
  /// as more than a relative time, so a null here just means nothing to show.
  DateTime? writtenAt(String key) {
    final raw = _prefs.getString('$_tsPrefix$key');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Wipes every cached entry — called on sign-out. Nothing cached here is
  /// keyed per account, so without this a second person signing in on the
  /// same device could see the first person's (and first tenant's) cached
  /// dashboard data for as long as it takes their own fetch to succeed. A
  /// fetch that succeeds overwrites it immediately regardless, but a fetch
  /// that fails offline right after switching accounts must not fall back to
  /// someone else's company's copy.
  Future<void> clearAll() async {
    // `_tsPrefix` is itself `_prefix` plus more, so matching `_prefix` alone
    // already covers both a value key and its timestamp key.
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}

final jsonCacheProvider = Provider<JsonCache>(
  (ref) => JsonCache(ref.watch(sharedPreferencesProvider)),
);
