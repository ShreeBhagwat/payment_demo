import 'package:cryptography/cryptography.dart';

import '../storage/secure_vault.dart';
import '../utils/bytes.dart';
import '../utils/clock.dart';

enum PinStatus { ok, wrong, lockedOut, notSet }

class PinVerifyResult {
  const PinVerifyResult(this.status, {this.attemptsLeft = 0, this.lockedUntil});

  final PinStatus status;
  final int attemptsLeft; // before the next lockout
  final DateTime? lockedUntil;

  bool get ok => status == PinStatus.ok;
}

/// App PIN: hashed with PBKDF2, never stored in clear, with brute-force
/// throttling persisted in Secure Storage (so killing the app doesn't reset it).
///
/// Training note: a 6-digit PIN has only 10^6 combinations. If an attacker
/// dumps the keystore from a rooted device, PBKDF2 only slows an offline
/// brute force; it doesn't stop it. In production, verify the PIN on the
/// SERVER (or use it to unwrap a hardware-bound key) so attempt limits
/// can't be bypassed offline.
class PinService {
  PinService(
    this._store, {
    this.pinLength = 6,
    this.attemptsBeforeLockout = 5,
    this.baseLockout = const Duration(seconds: 30),
    int iterations = 100000,
    Clock? clock,
  })  : _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256),
        _clock = clock ?? DateTime.now;

  final KeyValueStore _store;
  final int pinLength;
  final int attemptsBeforeLockout;
  final Duration baseLockout;
  final Pbkdf2 _kdf;
  final Clock _clock;

  static const kHash = 'pin.pbkdf2.hash';
  static const kSalt = 'pin.pbkdf2.salt';
  static const kFailures = 'pin.failures';
  static const kLockedUntil = 'pin.locked_until';

  Future<bool> get isSet async => await _store.read(kHash) != null;

  /// Returns a human-readable reason if [pin] is too weak, else null.
  String? validateNewPin(String pin) {
    if (pin.length != pinLength || !RegExp(r'^\d+$').hasMatch(pin)) {
      return 'PIN must be exactly $pinLength digits';
    }
    if (RegExp(r'^(\d)\1+$').hasMatch(pin)) return 'All digits are the same';
    const asc = '01234567890';
    const desc = '09876543210';
    if (asc.contains(pin) || desc.contains(pin)) return 'Sequential digits are easy to guess';
    if (RegExp(r'^(\d\d)\1+$').hasMatch(pin) || RegExp(r'^(\d\d\d)\1$').hasMatch(pin)) {
      return 'Repeating patterns are easy to guess';
    }
    if (pin.length == 6) {
      final month = int.parse(pin.substring(0, 2));
      final year = int.parse(pin.substring(2));
      if (month >= 1 && month <= 12 && year >= 1940 && year <= 2030) {
        return 'Looks like a birth month/year (MMYYYY)';
      }
    }
    return null;
  }

  Future<void> setPin(String pin) async {
    final weak = validateNewPin(pin);
    if (weak != null) throw ArgumentError(weak);
    final salt = Bytes.random(16);
    await _store.write(kSalt, Bytes.toBase64(salt));
    await _store.write(kHash, Bytes.toBase64(await _hash(pin, salt)));
    await _resetFailures();
  }

  Future<PinVerifyResult> verify(String pin) async {
    final hashB64 = await _store.read(kHash);
    final saltB64 = await _store.read(kSalt);
    if (hashB64 == null || saltB64 == null) return const PinVerifyResult(PinStatus.notSet);

    final lockedUntil = await this.lockedUntil();
    if (lockedUntil != null) return PinVerifyResult(PinStatus.lockedOut, lockedUntil: lockedUntil);

    final candidate = await _hash(pin, Bytes.fromBase64(saltB64));
    if (Bytes.constantTimeEquals(candidate, Bytes.fromBase64(hashB64))) {
      await _resetFailures();
      return PinVerifyResult(PinStatus.ok, attemptsLeft: attemptsBeforeLockout);
    }

    final failures = int.parse(await _store.read(kFailures) ?? '0') + 1;
    await _store.write(kFailures, '$failures');
    if (failures >= attemptsBeforeLockout) {
      // 30s, 60s, 120s, … doubling with every further failure.
      final until = _clock().add(baseLockout * (1 << (failures - attemptsBeforeLockout)));
      await _store.write(kLockedUntil, until.toIso8601String());
      return PinVerifyResult(PinStatus.lockedOut, lockedUntil: until);
    }
    return PinVerifyResult(PinStatus.wrong, attemptsLeft: attemptsBeforeLockout - failures);
  }

  /// Change flow: re-authenticate with the current PIN first. That stops
  /// someone who picks up an unlocked phone from silently resetting it.
  Future<PinVerifyResult> changePin({required String current, required String next}) async {
    final weak = validateNewPin(next);
    if (weak != null) throw ArgumentError(weak);
    if (current == next) throw ArgumentError('New PIN must differ from the current PIN');
    final r = await verify(current);
    if (r.ok) await setPin(next);
    return r;
  }

  Future<DateTime?> lockedUntil() async {
    final s = await _store.read(kLockedUntil);
    if (s == null) return null;
    final until = DateTime.parse(s);
    return until.isAfter(_clock()) ? until : null;
  }

  Future<void> clear() async {
    for (final k in [kHash, kSalt, kFailures, kLockedUntil]) {
      await _store.delete(k);
    }
  }

  Future<void> _resetFailures() async {
    await _store.delete(kFailures);
    await _store.delete(kLockedUntil);
  }

  Future<List<int>> _hash(String pin, List<int> salt) async =>
      (await _kdf.deriveKeyFromPassword(password: pin, nonce: salt)).extractBytes();
}
