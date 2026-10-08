import 'dart:convert';

import '../crypto/hmac_service.dart';
import '../crypto/signature_service.dart';
import '../utils/bytes.dart';
import 'bank_api.dart';
import 'models.dart';
import 'trace.dart';

/// A red-team scenario plugged into the payment pipeline.
///
/// Open/closed principle: [SecurePaymentClient] calls these hooks and never
/// switches on [AttackMode]. Adding an attack means adding a subclass and one
/// registry entry; the client stays untouched. Every hook defaults to "do
/// nothing", so each attack overrides only the step it corrupts.
abstract class AttackSimulation {
  const AttackSimulation();

  /// Change the payment payload before it is signed and encrypted.
  Map<String, Object?> tamperPayload(Map<String, Object?> payload, List<TraceStep> trace) => payload;

  /// Choose the key that signs the payload.
  Future<DeviceIdentity> signingIdentity(
    DeviceIdentity device,
    SignatureService signatures,
    List<TraceStep> trace,
  ) async =>
      device;

  /// Change the canonical payload after it was signed, before encryption.
  String alterSignedPayload(String canonical, List<TraceStep> trace) => canonical;

  /// Override the request timestamp (epoch ms), or null for "now".
  int? requestTimestamp(DateTime now) => null;

  /// Act on the request while it is "on the network".
  Future<ApiRequest> intercept(ApiRequest request, BankApi bank, List<TraceStep> trace) async => request;
}

class NoAttack extends AttackSimulation {
  const NoAttack();
}

class TamperInTransit extends AttackSimulation {
  const TamperInTransit();

  @override
  Future<ApiRequest> intercept(ApiRequest request, BankApi bank, List<TraceStep> trace) async {
    trace.add(const TraceStep('⚠ MITM flipped a byte in transit', 'Body ≠ signed body', danger: true));
    final body = request.body;
    final i = body.indexOf('"ct":"') + 8;
    return request.copyWith(body: body.replaceRange(i, i + 1, body[i] == 'A' ? 'B' : 'A'));
  }
}

class ReplayAttack extends AttackSimulation {
  const ReplayAttack();

  @override
  Future<ApiRequest> intercept(ApiRequest request, BankApi bank, List<TraceStep> trace) async {
    final first = await bank.processPayment(request);
    trace
      ..add(TraceStep('Original request delivered', first.success ? 'Captured ${first.paymentId}' : first.message!))
      ..add(const TraceStep('⚠ Attacker re-sends captured request', 'Identical bytes & headers', danger: true));
    return request;
  }
}

class StaleRequest extends AttackSimulation {
  const StaleRequest();

  @override
  int? requestTimestamp(DateTime now) => now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch;
}

class ForgedDevice extends AttackSimulation {
  const ForgedDevice();

  @override
  Future<DeviceIdentity> signingIdentity(
    DeviceIdentity device,
    SignatureService signatures,
    List<TraceStep> trace,
  ) async {
    trace.add(const TraceStep('⚠ Attacker signs with own key', 'Device seed not stolen', danger: true));
    return signatures.generate();
  }
}

class AmountManipulation extends AttackSimulation {
  const AmountManipulation();

  @override
  Map<String, Object?> tamperPayload(Map<String, Object?> payload, List<TraceStep> trace) {
    trace.add(const TraceStep('⚠ Hooked app rewrites amount to ₹1', 'Signed by the genuine device key', danger: true));
    return {...payload, 'amount': 100};
  }
}

/// Same edit as the HMAC lab's "Tamper" button, done by a smarter attacker:
/// the body hash is public math, so they fix X-Content-SHA256 too. Only the
/// HMAC, which needs the session key, still gives them away.
class HmacTamper extends AttackSimulation {
  const HmacTamper();

  @override
  Future<ApiRequest> intercept(ApiRequest request, BankApi bank, List<TraceStep> trace) async {
    final body = request.body;
    final i = body.indexOf('"ct":"') + 8;
    final forged = body.replaceRange(i, i + 1, body[i] == 'A' ? 'B' : 'A');
    trace.add(const TraceStep('⚠ Attacker edited body + recomputed SHA-256', 'X-Signature left as-is', danger: true));
    return request.copyWith(
      body: forged,
      headers: {...request.headers, 'X-Content-SHA256': HmacService.sha256Hex(Bytes.utf8Bytes(forged))},
    );
  }
}

/// Same edit as the Digital Signatures lab's "amount ×10" switch. Encryption
/// and HMAC happily wrap the altered bytes; only the Ed25519 check notices.
class SignatureTamper extends AttackSimulation {
  const SignatureTamper();

  @override
  String alterSignedPayload(String canonical, List<TraceStep> trace) {
    final payload = jsonDecode(canonical) as Map<String, dynamic>;
    trace.add(
      const TraceStep('⚠ Malware changed amount ×10 after signing', 'Signature now covers other bytes', danger: true),
    );
    return Bytes.canonicalJson({...payload, 'amount': (payload['amount'] as int) * 10});
  }
}

/// The single place that maps a UI choice to its behaviour.
const attackSimulations = <AttackMode, AttackSimulation>{
  AttackMode.none: NoAttack(),
  AttackMode.tamperInTransit: TamperInTransit(),
  AttackMode.replay: ReplayAttack(),
  AttackMode.staleRequest: StaleRequest(),
  AttackMode.forgedDevice: ForgedDevice(),
  AttackMode.amountManipulation: AmountManipulation(),
  AttackMode.hmacTamper: HmacTamper(),
  AttackMode.signatureTamper: SignatureTamper(),
};
