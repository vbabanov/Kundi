import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kundi_mobile/app/app.dart';
import 'package:kundi_mobile/features/auth/application/auth_controller.dart';
import 'package:kundi_mobile/features/auth/domain/auth_session.dart';
import 'package:kundi_mobile/features/auth/presentation/auth_page.dart';
import 'package:kundi_mobile/features/auth/presentation/main_shell_page.dart';

void main() {
  testWidgets('Kundi app boots', (tester) async {
    final flutterErrors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterErrors.add(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_FakeAuthController.new),
        ],
        child: const KundiApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 600));

    final appSurface = find.byType(AuthPage).evaluate().isNotEmpty ||
        find.byType(MainShellPage).evaluate().isNotEmpty;
    final unexpectedFlutterErrors = flutterErrors.where((details) {
      final message = details.exceptionAsString();
      return !message.contains('A RenderFlex overflowed');
    }).toList(growable: false);

    expect(appSurface, isTrue);
    expect(unexpectedFlutterErrors, isEmpty);
  });
}

class _FakeAuthController extends AuthController {
  @override
  Future<AuthSession?> build() async => null;

  @override
  Future<Map<String, String>> loadSavedCredentials() async =>
      <String, String>{};
}
