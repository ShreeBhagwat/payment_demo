import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/crypto/aes_gcm_service.dart';
import '../../core/utils/bytes.dart';

enum EncryptionTamper {
  none('Untouched'),
  ciphertext('Flip 1 bit'),
  aad('Swap AAD'),
  wrongKey('Wrong key / PIN');

  const EncryptionTamper(this.label);

  final String label;
}

@immutable
class EncryptionLabState {
  const EncryptionLabState({
    this.plain = 'Card 4111 1111 1111 1111 · CVV 123 · Exp 08/29',
    this.aad = 'customer:CIF-00921',
    this.pin = '482913',
    this.usePin = true,
    this.busy = false,
    this.key,
    this.salt,
    this.keyHex = '',
    this.kdfMillis = 0,
    this.payload,
    this.tamper = EncryptionTamper.none,
    this.decrypted,
    this.decryptError,
  });

  final String plain;
  final String aad;
  final String pin;
  final bool usePin;
  final bool busy;
  final SecretKey? key;
  final Uint8List? salt;
  final String keyHex;
  final int kdfMillis;
  final EncryptedPayload? payload;
  final EncryptionTamper tamper;
  final String? decrypted;
  final String? decryptError;

  EncryptionLabState copyWith({
    String? plain,
    String? aad,
    String? pin,
    bool? usePin,
    bool? busy,
    SecretKey? key,
    Uint8List? Function()? salt,
    String? keyHex,
    int? kdfMillis,
    EncryptedPayload? payload,
    EncryptionTamper? tamper,
    String? Function()? decrypted,
    String? Function()? decryptError,
  }) =>
      EncryptionLabState(
        plain: plain ?? this.plain,
        aad: aad ?? this.aad,
        pin: pin ?? this.pin,
        usePin: usePin ?? this.usePin,
        busy: busy ?? this.busy,
        key: key ?? this.key,
        salt: salt != null ? salt() : this.salt,
        keyHex: keyHex ?? this.keyHex,
        kdfMillis: kdfMillis ?? this.kdfMillis,
        payload: payload ?? this.payload,
        tamper: tamper ?? this.tamper,
        decrypted: decrypted != null ? decrypted() : this.decrypted,
        decryptError: decryptError != null ? decryptError() : this.decryptError,
      );
}

final encryptionLabProvider = NotifierProvider.autoDispose<EncryptionLabController, EncryptionLabState>(
  EncryptionLabController.new,
);

class EncryptionLabController extends Notifier<EncryptionLabState> {
  AesGcmService get _aes => ref.read(aesGcmServiceProvider);

  @override
  EncryptionLabState build() => const EncryptionLabState();

  void setPlain(String v) => state = state.copyWith(plain: v);
  void setAad(String v) => state = state.copyWith(aad: v);
  void setPin(String v) => state = state.copyWith(pin: v);
  void setUsePin(bool v) => state = state.copyWith(usePin: v);

  void setTamper(EncryptionTamper t) =>
      state = state.copyWith(tamper: t, decrypted: () => null, decryptError: () => null);

  Future<void> encrypt() async {
    state = state.copyWith(busy: true);
    final sw = Stopwatch()..start();
    final salt = state.usePin ? Bytes.random(16) : null;
    final key = salt != null ? await _aes.deriveFromPassword(state.pin, salt: salt) : await _aes.newKey();
    final kdfMillis = sw.elapsedMilliseconds;
    final keyHex = Bytes.toHex(await key.extractBytes());
    final payload = await _aes.encryptString(state.plain, key: key, aad: state.aad.isEmpty ? null : state.aad);
    if (!ref.mounted) return;
    state = state.copyWith(
      busy: false,
      key: key,
      salt: () => salt,
      keyHex: keyHex,
      kdfMillis: kdfMillis,
      payload: payload,
      tamper: EncryptionTamper.none,
      decrypted: () => null,
      decryptError: () => null,
    );
  }

  Future<void> decrypt() async {
    var p = state.payload!;
    var key = state.key!;
    switch (state.tamper) {
      case EncryptionTamper.ciphertext:
        p = p.copyWith(cipherText: Uint8List.fromList(p.cipherText)..[0] ^= 0x01);
      case EncryptionTamper.aad:
        p = p.copyWith(aad: 'customer:CIF-66666');
      case EncryptionTamper.wrongKey:
        key = state.salt != null ? await _aes.deriveFromPassword('482914', salt: state.salt!) : await _aes.newKey();
      case EncryptionTamper.none:
        break;
    }
    try {
      final clear = await _aes.decryptString(p, key: key);
      if (ref.mounted) state = state.copyWith(decrypted: () => clear, decryptError: () => null);
    } on SecretBoxAuthenticationError {
      if (!ref.mounted) return;
      state = state.copyWith(
        decrypted: () => null,
        decryptError: () => 'Authentication tag mismatch — decryption refused. No partial plaintext is released.',
      );
    }
  }
}
