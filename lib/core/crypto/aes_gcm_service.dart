import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../utils/bytes.dart';

/// Wire format for an encrypted payload. Every field is needed to decrypt.
class EncryptedPayload {
  const EncryptedPayload({required this.nonce, required this.cipherText, required this.mac, this.aad});

  final Uint8List nonce; // 12 bytes, MUST be unique per key
  final Uint8List cipherText;
  final Uint8List mac; // 16-byte GCM authentication tag
  final String? aad; // additional authenticated data (sent in clear)

  Map<String, dynamic> toJson() => {
        'alg': 'A256GCM',
        'iv': Bytes.toBase64(nonce),
        'ct': Bytes.toBase64(cipherText),
        'tag': Bytes.toBase64(mac),
        if (aad != null) 'aad': aad,
      };

  factory EncryptedPayload.fromJson(Map<String, dynamic> j) => EncryptedPayload(
        nonce: Bytes.fromBase64(j['iv'] as String),
        cipherText: Bytes.fromBase64(j['ct'] as String),
        mac: Bytes.fromBase64(j['tag'] as String),
        aad: j['aad'] as String?,
      );

  /// Single base64 blob: nonce ‖ ciphertext ‖ tag. Handy for storage.
  String toCompact() => Bytes.toBase64([...nonce, ...cipherText, ...mac]);

  factory EncryptedPayload.fromCompact(String s, {String? aad}) {
    final all = Bytes.fromBase64(s);
    return EncryptedPayload(
      nonce: Uint8List.sublistView(all, 0, 12),
      cipherText: Uint8List.sublistView(all, 12, all.length - 16),
      mac: Uint8List.sublistView(all, all.length - 16),
      aad: aad,
    );
  }

  EncryptedPayload copyWith({Uint8List? cipherText, Uint8List? mac, String? aad}) => EncryptedPayload(
        nonce: nonce,
        cipherText: cipherText ?? this.cipherText,
        mac: mac ?? this.mac,
        aad: aad ?? this.aad,
      );
}

/// AES-256-GCM: authenticated encryption (confidentiality + integrity).
///
/// Why GCM and not CBC/ECB?
///  * ECB leaks patterns (identical blocks → identical ciphertext).
///  * CBC without a separate MAC is vulnerable to padding-oracle attacks.
///  * GCM encrypts AND authenticates in one step; any tampering with the
///    ciphertext, nonce or AAD makes decryption fail loudly.
class AesGcmService {
  AesGcmService() : _algo = AesGcm.with256bits();

  final AesGcm _algo;

  Future<SecretKey> newKey() => _algo.newSecretKey();

  SecretKey keyFromBytes(List<int> bytes) => SecretKey(bytes);

  /// Derive an encryption key from a user PIN/password.
  ///
  /// PBKDF2 is deliberately slow (many iterations) to make brute-forcing a
  /// short PIN expensive. The salt must be random and stored with the data.
  Future<SecretKey> deriveFromPassword(String password, {required List<int> salt, int iterations = 100000}) {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    return kdf.deriveKeyFromPassword(password: password, nonce: salt);
  }

  Future<EncryptedPayload> encrypt(List<int> plain, {required SecretKey key, String? aad}) async {
    final box = await _algo.encrypt(
      plain,
      secretKey: key,
      nonce: _algo.newNonce(),
      aad: aad == null ? const <int>[] : utf8.encode(aad),
    );
    return EncryptedPayload(
      nonce: Uint8List.fromList(box.nonce),
      cipherText: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
      aad: aad,
    );
  }

  Future<EncryptedPayload> encryptString(String plain, {required SecretKey key, String? aad}) =>
      encrypt(utf8.encode(plain), key: key, aad: aad);

  /// Throws [SecretBoxAuthenticationError] if anything was tampered with.
  Future<Uint8List> decrypt(EncryptedPayload p, {required SecretKey key}) async {
    final box = SecretBox(p.cipherText, nonce: p.nonce, mac: Mac(p.mac));
    final clear = await _algo.decrypt(box, secretKey: key, aad: p.aad == null ? const <int>[] : utf8.encode(p.aad!));
    return Uint8List.fromList(clear);
  }

  Future<String> decryptString(EncryptedPayload p, {required SecretKey key}) async =>
      utf8.decode(await decrypt(p, key: key));
}
