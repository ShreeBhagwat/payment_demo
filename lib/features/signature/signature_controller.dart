import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/crypto/signature_service.dart';
import '../../core/storage/secure_vault.dart';
import '../../core/utils/bytes.dart';

@immutable
class SignatureLabState {
  const SignatureLabState({
    this.identity,
    this.fingerprint = '',
    this.fromVault = false,
    this.payee = 'HDFC0001234 · Priya Traders',
    this.amount = '75000',
    this.signedMessage,
    this.signature,
    this.tamperAmount = false,
    this.otherKey = false,
    this.verified,
  });

  final DeviceIdentity? identity;
  final String fingerprint;
  final bool fromVault;
  final String payee;
  final String amount; // rupees, as typed
  final String? signedMessage;
  final Uint8List? signature;
  final bool tamperAmount;
  final bool otherKey;
  final bool? verified;

  SignatureLabState copyWith({
    DeviceIdentity? identity,
    String? fingerprint,
    bool? fromVault,
    String? payee,
    String? amount,
    String? Function()? signedMessage,
    Uint8List? Function()? signature,
    bool? tamperAmount,
    bool? otherKey,
    bool? Function()? verified,
  }) =>
      SignatureLabState(
        identity: identity ?? this.identity,
        fingerprint: fingerprint ?? this.fingerprint,
        fromVault: fromVault ?? this.fromVault,
        payee: payee ?? this.payee,
        amount: amount ?? this.amount,
        signedMessage: signedMessage != null ? signedMessage() : this.signedMessage,
        signature: signature != null ? signature() : this.signature,
        tamperAmount: tamperAmount ?? this.tamperAmount,
        otherKey: otherKey ?? this.otherKey,
        verified: verified != null ? verified() : this.verified,
      );
}

/// Kept alive (not autoDispose): a tamper switched on here must still be in
/// effect when the trainee opens the Secure Payment lab and pays.
final signatureLabProvider = NotifierProvider<SignatureLabController, SignatureLabState>(SignatureLabController.new);

class SignatureLabController extends Notifier<SignatureLabState> {
  static const _seedSlot = 'lab.signature.seed';

  SignatureService get _sig => ref.read(signatureServiceProvider);
  SecureVault get _vault => ref.read(secureVaultProvider);

  @override
  SignatureLabState build() {
    Future.microtask(_load);
    return const SignatureLabState();
  }

  Future<void> _load() async {
    String? seed;
    try {
      seed = await _vault.get(_seedSlot);
    } catch (_) {
      seed = null;
    }
    if (seed == null || !ref.mounted) return;
    await _setIdentity(await _sig.fromSeed(Bytes.fromBase64(seed)), fromVault: true);
  }

  /// Generates (or rotates) the device key and persists its seed.
  Future<void> generate() async {
    final id = await _sig.generate();
    await _vault.put(_seedSlot, Bytes.toBase64(await _sig.exportSeed(id)));
    await _setIdentity(id, fromVault: false);
  }

  Future<void> _setIdentity(DeviceIdentity id, {required bool fromVault}) async {
    final fp = await id.fingerprint();
    if (!ref.mounted) return;
    state = state.copyWith(
      identity: id,
      fingerprint: fp,
      fromVault: fromVault,
      signature: () => null,
      signedMessage: () => null,
      verified: () => null,
    );
  }

  void setPayee(String v) => state = state.copyWith(payee: v);
  void setAmount(String v) => state = state.copyWith(amount: v);

  void setTamperAmount(bool v) => state = state.copyWith(tamperAmount: v, verified: () => null);
  void setOtherKey(bool v) => state = state.copyWith(otherKey: v, verified: () => null);

  String _message({bool tampered = false}) => Bytes.canonicalJson({
        'type': 'NEFT',
        'payee': state.payee,
        'amountPaise': (int.tryParse(state.amount) ?? 0) * 100 * (tampered ? 10 : 1),
        'ts': 1790000000,
      });

  Future<void> signTransaction() async {
    final msg = _message();
    final s = await _sig.sign(Bytes.utf8Bytes(msg), state.identity!);
    if (!ref.mounted) return;
    state = state.copyWith(
      signedMessage: () => msg,
      signature: () => s,
      verified: () => null,
      tamperAmount: false,
      otherKey: false,
    );
  }

  /// What the bank does: verify against the registered public key.
  Future<void> verify() async {
    final msg = state.tamperAmount ? _message(tampered: true) : state.signedMessage!;
    final pub = state.otherKey ? (await _sig.generate()).publicKey : state.identity!.publicKey;
    final ok = await _sig.verify(Bytes.utf8Bytes(msg), signature: state.signature!, publicKey: pub);
    if (ref.mounted) state = state.copyWith(verified: () => ok);
  }
}
