import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Small, dependency-free helpers used across every security module.
abstract final class Bytes {
  static final Random _secure = Random.secure();

  /// Cryptographically secure random bytes (backed by the OS CSPRNG).
  static Uint8List random(int length) => Uint8List.fromList(List<int>.generate(length, (_) => _secure.nextInt(256)));

  static String toHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List fromHex(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s'), '');
    if (clean.length.isOdd) throw const FormatException('Odd-length hex');
    return Uint8List.fromList([
      for (var i = 0; i < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16),
    ]);
  }

  static String toBase64(List<int> bytes) => base64Encode(bytes);
  static Uint8List fromBase64(String s) => base64Decode(s);

  static Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

  /// Constant-time comparison.
  ///
  /// A naive `a == b` returns on the first mismatching byte, so response time
  /// leaks how many leading bytes were correct. An attacker can use that to
  /// forge a MAC byte-by-byte (a "timing attack"). Always compare secrets
  /// with this function.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Deterministic JSON: keys sorted recursively, no whitespace.
  ///
  /// Signatures and MACs are computed over *bytes*. If the client and server
  /// serialise the same map differently (key order, spacing), verification
  /// fails. Canonicalisation removes that ambiguity.
  static String canonicalJson(Object? value) => jsonEncode(_sort(value));

  static Object? _sort(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: _sort(v[k])};
    }
    if (v is List) return v.map(_sort).toList();
    return v;
  }

  /// Shortens long hex/base64 strings for display: `a1b2c3…e4f5`.
  static String ellipsize(String s, {int keep = 10}) =>
      s.length <= keep * 2 + 1 ? s : '${s.substring(0, keep)}…${s.substring(s.length - keep)}';
}
