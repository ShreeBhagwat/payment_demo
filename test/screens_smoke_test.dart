import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_demo/app/lab_module.dart';
import 'package:payment_demo/core/security/pin_service.dart';
import 'package:payment_demo/core/storage/secure_vault.dart';
import 'package:payment_demo/main.dart';

import 'support/fakes.dart';

void main() {
  late InMemoryStore store;

  setUp(() => store = InMemoryStore());

  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Widget app() => ProviderScope(
        overrides: testOverrides(store: store),
        child: const SecurePayAcademy(),
      );

  /// Lets real async work (PBKDF2, vault reads) finish between fake frames.
  Future<void> settleRealAsync(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  for (final module in LabModule.values) {
    testWidgets('opens "${module.title}" at phone size without layout errors', (tester) async {
      phoneSize(tester);
      await tester.pumpWidget(app());
      await settleRealAsync(tester);
      final tile = find.text(module.title);
      await tester.scrollUntilVisible(tile, 200);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text(module.shortTitle)), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // dispose providers & timers
    });
  }

  testWidgets('with a PIN set, the app opens locked and the PIN unlocks it', (tester) async {
    phoneSize(tester);
    await tester.runAsync(() => PinService(store, iterations: 1000).setPin('482913'));

    await tester.pumpWidget(app());
    await settleRealAsync(tester);
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.text('App launched'), findsOneWidget);

    for (final d in '482913'.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await settleRealAsync(tester);

    expect(find.text('Enter your PIN'), findsNothing);
    expect(find.text('SecurePay Academy'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // dispose providers & timers
  });

  testWidgets('defence ring "Try it" opens the linked lab', (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(app());
    await settleRealAsync(tester);
    final tryIt = find.textContaining('Try it in Module');
    await tester.scrollUntilVisible(tryIt, 300);
    await tester.pumpAndSettle();
    await tester.tap(tryIt);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text(LabModule.appSecurity.shortTitle)),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
