import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;

import '../utils/bytes.dart';

/// Headers attached to every HMAC-authenticated API call.
class SignedRequestHeaders {
  const SignedRequestHeaders({
    required this.keyId,
    required this.timestamp,
    required this.nonce,
    required this.bodySha256,
    required this.signature,
  });

  final String keyId;
  final int timestamp; // epoch millis
  final String nonce;
  final String bodySha256;
  final String signature; // hex HMAC-SHA256

  Map<String, String> toMap() => {
        'X-Key-Id': keyId,
        'X-Timestamp': '$timestamp',
        'X-Nonce': nonce,
        'X-Content-SHA256': bodySha256,
        'X-Signature': signature,
      };
}

/// HMAC = Hash-based Message Authentication Code.
///
/// Proves two things about a message:
///  * Integrity – it was not modified in transit.
///  * Authenticity – it was produced by someone holding the shared secret.
///
/// It does NOT provide confidentiality (the message is still readable) and it
/// does NOT provide non-repudiation (both sides share the key, so either side
/// could have produced it). For non-repudiation use digital signatures.
class HmacService {
  const HmacService();

  Uint8List sign(List<int> key, List<int> message) => Uint8List.fromList(c.Hmac(c.sha256, key).convert(message).bytes);

  String signHex(List<int> key, String message) => Bytes.toHex(sign(key, Bytes.utf8Bytes(message)));

  bool verifyHex(List<int> key, String message, String expectedHex) {
    final actual = sign(key, Bytes.utf8Bytes(message));
    final expected = _tryHex(expectedHex);
    return expected != null && Bytes.constantTimeEquals(actual, expected);
  }

  static String sha256Hex(List<int> data) => c.sha256.convert(data).toString();

  /// The exact string that gets MAC'd. Binding method + path + timestamp +
  /// nonce + body hash stops an attacker from:
  ///  * replaying the request later (timestamp + nonce),
  ///  * re-targeting a valid signature to another endpoint (method + path),
  ///  * swapping the body (body hash).
  static String canonicalRequest({
    required String method,
    required String path,
    required int timestamp,
    required String nonce,
    required String bodySha256,
  }) =>
      [method.toUpperCase(), path, '$timestamp', nonce, bodySha256].join('\n');

  SignedRequestHeaders signRequest({
    required String keyId,
    required List<int> key,
    required String method,
    required String path,
    required String body,
    int? timestamp,
    String? nonce,
  }) {
    final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final n = nonce ?? Bytes.toHex(Bytes.random(16));
    final bodyHash = sha256Hex(Bytes.utf8Bytes(body));
    final canonical = canonicalRequest(method: method, path: path, timestamp: ts, nonce: n, bodySha256: bodyHash);
    return SignedRequestHeaders(
      keyId: keyId,
      timestamp: ts,
      nonce: n,
      bodySha256: bodyHash,
      signature: signHex(key, canonical),
    );
  }

  static Uint8List? _tryHex(String s) {
    try {
      return Bytes.fromHex(s);
    } on FormatException {
      return null;
    }
  }
}
