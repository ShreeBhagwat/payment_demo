import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstraction over key-value storage so business logic is testable without
/// a device (unit tests use [InMemoryStore]).
abstract interface class KeyValueStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
  Future<void> deleteAll();
}

/// Production store backed by the platform's hardware-protected keystore.
///
///  * iOS: Keychain. `first_unlock_this_device` = readable after first unlock
///    following a reboot, and NEVER migrated to iCloud / another device via
///    backup. That stops a cloned backup from carrying the device key.
///  * Android: values encrypted with AES-GCM, whose key is wrapped by an RSA
///    key living in the Android Keystore (TEE / StrongBox where available).
///    Also set `android:allowBackup="false"` in the manifest for banking apps.
class SecureStorageStore implements KeyValueStore {
  SecureStorageStore()
      : _storage = const FlutterSecureStorage(
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
          aOptions: AndroidOptions(),
        );

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

class InMemoryStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<Map<String, String>> readAll() async => Map.of(_data);

  @override
  Future<void> deleteAll() async => _data.clear();
}

/// Well-known slots. Centralising key names avoids typos and makes a
/// security review of "what do we persist?" a one-file job.
abstract final class VaultKeys {
  static const deviceSigningSeed = 'device.ed25519.seed';
  static const deviceId = 'device.id';
  static const sessionEncKey = 'session.aes.key';
  static const sessionMacKey = 'session.hmac.key';
  static const sessionKeyId = 'session.key_id';
  static const authToken = 'auth.access_token';
}

/// App-facing facade over the secure store.
class SecureVault {
  SecureVault(this._store);

  final KeyValueStore _store;

  Future<void> put(String key, String value) => _store.write(key, value);
  Future<String?> get(String key) => _store.read(key);
  Future<void> remove(String key) => _store.delete(key);
  Future<Map<String, String>> dump() => _store.readAll();
  Future<void> wipe() => _store.deleteAll();
}
