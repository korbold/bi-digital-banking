import 'dart:convert';

import 'package:hive_ce/hive.dart';

/// A cached response body with the moment it was stored.
class CacheEntry {
  const CacheEntry(this.body, this.storedAt);

  final Object? body;
  final DateTime storedAt;
}

/// Persistence for last-known-good responses. Keys are request paths and
/// are scoped per user by the `ApiClient` so a logout never leaks data.
abstract interface class CacheStore {
  Future<CacheEntry?> read(String key);
  Future<void> write(String key, Object? body);
  Future<void> clear();
}

class MemoryCacheStore implements CacheStore {
  final Map<String, CacheEntry> _entries = {};

  @override
  Future<CacheEntry?> read(String key) async => _entries[key];

  @override
  Future<void> write(String key, Object? body) async =>
      _entries[key] = CacheEntry(body, DateTime.now());

  @override
  Future<void> clear() async => _entries.clear();
}

/// Hive-backed store. Bodies are stored as JSON strings.
///
/// Note: balances are sensitive. The box is opened with a key derived from
/// secure storage in a production hardening step (see docs/adr/0006).
class HiveCacheStore implements CacheStore {
  HiveCacheStore(this._box);

  final Box<String> _box;

  static Future<HiveCacheStore> open({
    String name = 'http_cache',
    HiveCipher? cipher,
  }) async => HiveCacheStore(
    await Hive.openBox<String>(name, encryptionCipher: cipher),
  );

  @override
  Future<CacheEntry?> read(String key) async {
    final raw = _box.get(key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return CacheEntry(
      decoded['body'],
      DateTime.parse(decoded['storedAt'] as String),
    );
  }

  @override
  Future<void> write(String key, Object? body) => _box.put(
    key,
    jsonEncode({'body': body, 'storedAt': DateTime.now().toIso8601String()}),
  );

  @override
  Future<void> clear() => _box.clear();
}
