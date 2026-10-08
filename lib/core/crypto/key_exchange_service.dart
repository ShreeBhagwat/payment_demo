import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Keys derived from one ECDH handshake. Separate keys per purpose: never
/// reuse the same key for encryption and MAC.
class SessionKeys {
  const SessionKeys({required this.encKey, required this.macKey});

  final Uint8List encKey; // AES-256-GCM
  final Uint8List macKey; // HMAC-SHA256
}

/// X25519 Elliptic-Curve Diffie–Hellman + HKDF.
///
/// Lets the app and the bank agree on fresh symmetric keys over an untrusted
/// network without ever sending the keys themselves. Each side combines its
/// own private key with the other side's public key and arrives at the same
/// shared secret. HKDF then stretches that secret into independent keys.
class KeyExchangeService {
  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);

  Future<SimpleKeyPair> newEphemeralKeyPair() => _x25519.newKeyPair();

  Future<Uint8List> publicKeyOf(SimpleKeyPair kp) async => Uint8List.fromList((await kp.extractPublicKey()).bytes);

  Future<SessionKeys> deriveSessionKeys({
    required SimpleKeyPair myKeyPair,
    required List<int> theirPublicKey,
    required List<int> salt,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: SimplePublicKey(theirPublicKey, type: KeyPairType.x25519),
    );
    final okm = await _hkdf.deriveKey(secretKey: shared, nonce: salt, info: utf8.encode('securepay/v1/session'));
    final bytes = await okm.extractBytes();
    return SessionKeys(
      encKey: Uint8List.fromList(bytes.sublist(0, 32)),
      macKey: Uint8List.fromList(bytes.sublist(32, 64)),
    );
  }
}
