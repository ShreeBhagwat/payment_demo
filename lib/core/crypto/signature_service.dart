import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../utils/bytes.dart';

/// A device signing identity. The private seed never leaves the device; only
/// the public key is registered with the bank.
class DeviceIdentity {
  const DeviceIdentity({required this.keyPair, required this.publicKey});

  final SimpleKeyPair keyPair;
  final Uint8List publicKey;

  String get publicKeyB64 => Bytes.toBase64(publicKey);

  /// Short human-checkable fingerprint (first 8 bytes of SHA-256(pubkey)).
  Future<String> fingerprint() async {
    final h = await Sha256().hash(publicKey);
    return Bytes.toHex(h.bytes.sublist(0, 8)).toUpperCase().replaceAllMapped(RegExp(r'.{4}'), (m) => '${m[0]} ').trim();
  }
}

/// Digital signatures with Ed25519.
///
/// Unlike HMAC (shared secret), signatures use a key PAIR:
///  * sign with the PRIVATE key (only the device has it),
///  * verify with the PUBLIC key (anyone, e.g. the bank, can have it).
///
/// This gives non-repudiation: the bank can prove to an auditor that this
/// specific device authorised the transaction, because the bank itself could
/// not have produced the signature.
///
/// Ed25519 is fast, has small keys (32 B) and signatures (64 B), and is
/// deterministic — no per-signature randomness that could be botched (the
/// flaw that leaked the PlayStation 3 ECDSA key).
class SignatureService {
  SignatureService() : _algo = Ed25519();

  final Ed25519 _algo;

  Future<DeviceIdentity> generate() async => _wrap(await _algo.newKeyPair());

  Future<DeviceIdentity> fromSeed(List<int> seed) async => _wrap(await _algo.newKeyPairFromSeed(seed));

  Future<Uint8List> exportSeed(DeviceIdentity id) async =>
      Uint8List.fromList(await id.keyPair.extractPrivateKeyBytes());

  Future<Uint8List> sign(List<int> message, DeviceIdentity id) async {
    final sig = await _algo.sign(message, keyPair: id.keyPair);
    return Uint8List.fromList(sig.bytes);
  }

  Future<bool> verify(List<int> message, {required List<int> signature, required List<int> publicKey}) {
    return _algo.verify(
      message,
      signature: Signature(signature, publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)),
    );
  }

  Future<DeviceIdentity> _wrap(SimpleKeyPair kp) async {
    final pub = await kp.extractPublicKey();
    return DeviceIdentity(keyPair: kp, publicKey: Uint8List.fromList(pub.bytes));
  }
}
