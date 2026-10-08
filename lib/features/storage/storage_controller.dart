import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/storage/secure_vault.dart';
import '../../core/utils/bytes.dart';

@immutable
class StorageLabState {
  const StorageLabState({
    required this.keyName,
    required this.value,
    this.entries = const {},
    this.revealed = const {},
    this.error,
  });

  final String keyName;
  final String value;
  final Map<String, String> entries; // sorted by key
  final Set<String> revealed;
  final String? error;

  StorageLabState copyWith({
    String? keyName,
    String? value,
    Map<String, String>? entries,
    Set<String>? revealed,
    String? Function()? error,
  }) =>
      StorageLabState(
        keyName: keyName ?? this.keyName,
        value: value ?? this.value,
        entries: entries ?? this.entries,
        revealed: revealed ?? this.revealed,
        error: error != null ? error() : this.error,
      );
}

final storageLabProvider = NotifierProvider.autoDispose<StorageLabController, StorageLabState>(
  StorageLabController.new,
);

class StorageLabController extends Notifier<StorageLabState> {
  SecureVault get _vault => ref.read(secureVaultProvider);

  @override
  StorageLabState build() {
    // Reload whenever credentials are wiped elsewhere (e.g. "Forgot PIN").
    ref.watch(vaultGenerationProvider);
    Future.microtask(refresh);
    return StorageLabState(
      keyName: VaultKeys.authToken,
      value: 'eyJhbGciOiJFZERTQSJ9.${Bytes.toBase64(Bytes.random(18))}',
    );
  }

  void setKeyName(String v) => state = state.copyWith(keyName: v);
  void setValue(String v) => state = state.copyWith(value: v);

  Future<void> refresh() async {
    try {
      final all = await _vault.dump();
      if (!ref.mounted) return;
      final sorted = Map.fromEntries(all.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
      state = state.copyWith(entries: sorted);
    } catch (e) {
      if (ref.mounted) state = state.copyWith(error: () => '$e');
    }
  }

  Future<void> write() => _guard(() => _vault.put(state.keyName.trim(), state.value));

  Future<void> remove(String key) => _guard(() => _vault.remove(key));

  Future<void> wipe() => _guard(() async {
        await _vault.wipe();
        // Tell other features (app lock, payment lab) their cached state is stale.
        ref.read(vaultGenerationProvider.notifier).bump();
      });

  void toggleReveal(String key) {
    final next = {...state.revealed};
    next.contains(key) ? next.remove(key) : next.add(key);
    state = state.copyWith(revealed: next);
  }

  Future<void> _guard(Future<void> Function() op) async {
    String? error;
    try {
      await op();
    } catch (e) {
      error = '$e';
    }
    if (!ref.mounted) return;
    state = state.copyWith(error: () => error);
    await refresh();
  }
}
