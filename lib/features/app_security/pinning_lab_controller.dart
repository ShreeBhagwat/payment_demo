import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/security/certificate_pinning.dart';
import '../../core/utils/bytes.dart';

@immutable
class PinningLabState {
  const PinningLabState({this.host = 'www.google.com', this.cert, this.status, this.ok, this.busy = false});

  final String host;
  final CertInfo? cert;
  final String? status;
  final bool? ok;
  final bool busy;

  PinningLabState copyWith({
    String? host,
    CertInfo? Function()? cert,
    String? Function()? status,
    bool? Function()? ok,
    bool? busy,
  }) =>
      PinningLabState(
        host: host ?? this.host,
        cert: cert != null ? cert() : this.cert,
        status: status != null ? status() : this.status,
        ok: ok != null ? ok() : this.ok,
        busy: busy ?? this.busy,
      );
}

final pinningLabProvider = NotifierProvider.autoDispose<PinningLabController, PinningLabState>(
  PinningLabController.new,
);

class PinningLabController extends Notifier<PinningLabState> {
  @override
  PinningLabState build() => const PinningLabState();

  void setHost(String host) => state = state.copyWith(host: host);

  Future<void> inspect() async {
    state = state.copyWith(busy: true, status: () => null, ok: () => null);
    try {
      final cert = await ref.read(certificateInspectorProvider).inspect(state.host.trim());
      if (ref.mounted) state = state.copyWith(cert: () => cert, busy: false);
    } catch (e) {
      if (ref.mounted) state = state.copyWith(status: () => 'Could not connect: $e', ok: () => false, busy: false);
    }
  }

  /// [correctPin] false simulates a MITM: the presented key won't match.
  Future<void> pinnedRequest({required bool correctPin}) async {
    final host = state.host.trim();
    final pin = correctPin ? state.cert!.spkiPin : Bytes.toBase64(Bytes.random(32));
    String? presented;
    final dio = PinnedDio.create(
      pinsByHost: {
        host: {pin},
      },
      onMismatch: (_, p) => presented = p,
    );
    state = state.copyWith(busy: true);
    final sw = Stopwatch()..start();
    String status;
    bool ok;
    try {
      final res = await dio.get<String>('https://$host/', options: Options(responseType: ResponseType.plain));
      ok = true;
      status =
          'HTTP ${res.statusCode} in ${sw.elapsedMilliseconds} ms — key matched pin ${Bytes.ellipsize(pin, keep: 8)}';
    } on DioException catch (e) {
      ok = false;
      status = presented != null
          ? 'Connection refused before any data was sent.\nExpected ${Bytes.ellipsize(pin, keep: 8)}\n'
              'Presented ${Bytes.ellipsize(presented!, keep: 8)}'
          : 'Request failed: ${e.message ?? e.type.name}';
    } finally {
      dio.close(force: true);
    }
    if (ref.mounted) state = state.copyWith(busy: false, ok: () => ok, status: () => status);
  }
}
