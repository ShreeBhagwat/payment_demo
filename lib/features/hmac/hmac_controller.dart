import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/crypto/hmac_service.dart';
import '../../core/utils/bytes.dart';

@immutable
class HmacLabState {
  const HmacLabState({
    required this.key,
    required this.message,
    required this.received,
    required this.mac,
    required this.valid,
    this.headers,
    this.canonical = '',
  });

  final String key;
  final String message;
  final String received;
  final String mac; // HMAC of [message] under [key]
  final bool valid; // does [mac] verify against [received]?
  final SignedRequestHeaders? headers;
  final String canonical;

  HmacLabState copyWith({
    String? key,
    String? message,
    String? received,
    String? mac,
    bool? valid,
    SignedRequestHeaders? Function()? headers,
    String? canonical,
  }) =>
      HmacLabState(
        key: key ?? this.key,
        message: message ?? this.message,
        received: received ?? this.received,
        mac: mac ?? this.mac,
        valid: valid ?? this.valid,
        headers: headers != null ? headers() : this.headers,
        canonical: canonical ?? this.canonical,
      );
}

/// Kept alive (not autoDispose): a tamper done here must still be in effect
/// when the trainee opens the Secure Payment lab and pays.
final hmacLabProvider = NotifierProvider<HmacLabController, HmacLabState>(HmacLabController.new);

class HmacLabController extends Notifier<HmacLabState> {
  static const _path = '/v1/transfers';

  HmacService get _hmac => ref.read(hmacServiceProvider);

  @override
  HmacLabState build() {
    const key = 'bank-shared-secret-2026';
    const msg = '{"to":"ACME0001","amount":250000}';
    return _derive(const HmacLabState(key: key, message: msg, received: msg, mac: '', valid: true));
  }

  /// Recomputes the MAC and its verification from the current inputs.
  HmacLabState _derive(HmacLabState s) {
    final keyBytes = Bytes.utf8Bytes(s.key);
    final mac = _hmac.signHex(keyBytes, s.message);
    return s.copyWith(mac: mac, valid: _hmac.verifyHex(keyBytes, s.received, mac));
  }

  void setKey(String v) => state = _derive(state.copyWith(key: v));
  void setMessage(String v) => state = _derive(state.copyWith(message: v));
  void setReceived(String v) => state = _derive(state.copyWith(received: v));

  /// Simulates an attacker changing the amount in transit.
  void tamper() => setReceived(state.message.replaceFirst('250000', '9250000'));

  void restore() => setReceived(state.message);

  void signRequest() {
    final h = _hmac.signRequest(
      keyId: 'kid_demo01',
      key: Bytes.utf8Bytes(state.key),
      method: 'POST',
      path: _path,
      body: state.message,
      timestamp: ref.read(clockProvider)().millisecondsSinceEpoch,
    );
    state = state.copyWith(
      headers: () => h,
      canonical: HmacService.canonicalRequest(
        method: 'POST',
        path: _path,
        timestamp: h.timestamp,
        nonce: h.nonce,
        bodySha256: h.bodySha256,
      ),
    );
  }
}
