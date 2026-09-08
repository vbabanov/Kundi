import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/app/app.dart';
import 'package:kundi_mobile/features/auth/application/auth_controller.dart';
import 'package:kundi_mobile/features/auth/domain/auth_session.dart';
import 'package:kundi_mobile/features/auth/presentation/auth_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Use Android font metrics for the accepted fixed-size greeting bubble.
    // Ahem's square glyphs overflow it independently of the login lifecycle.
    final root = Platform.environment['FLUTTER_ROOT']!;
    final bytes = await File(
            '$root/bin/cache/artifacts/material_fonts/roboto-regular.ttf')
        .readAsBytes();
    await (FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  });
  testWidgets(
      'loading replaces the real AuthPage while sheet fields stay alive',
      (tester) async {
    final auth = _DelayedAuthController();
    await _pumpRoot(tester, auth, realApp: true);
    await _open(tester);
    final controllers = _controllers(tester);
    await _enterAndSubmit(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).first, 'pending-edit');

    expect(find.byType(AuthPage), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(_controllers(tester), orderedEquals(controllers));
    expect(controllers.first.text, 'pending-edit');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('success closes one sheet once after repeated loading rebuilds',
      (tester) async {
    final auth = _DelayedAuthController();
    final observer = _RouteObserver();
    await _pumpRoot(tester, auth, observer: observer);
    await _open(tester);
    final controllers = _controllers(tester);
    await _enterAndSubmit(tester);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // A stale button/IME callback cannot submit twice before the next rebuild.
    tester
        .widget<TextField>(find.byType(TextField).last)
        .onSubmitted!('ignored');
    expect(auth.loginCalls, 1);
    expect(auth.savedReads, 1);
    auth.pendingLogin!.complete(_session());
    await tester.pumpAndSettle();
    auth.publishSession();
    await tester.pumpAndSettle();

    expect(find.text('Authenticated root'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(observer.sheetPops, 1);
    expect(observer.otherPops, 0);
    _expectDisposed(controllers);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure keeps fields, renders one safe error and allows retry',
      (tester) async {
    final auth = _DelayedAuthController();
    final observer = _RouteObserver();
    await _pumpRoot(tester, auth, observer: observer);
    await _open(tester);
    final controllers = _controllers(tester);
    await _enterAndSubmit(tester);
    await tester.pump();
    auth.pendingLogin!.completeError(StateError('raw-sensitive-fixture-error'));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось войти. Попробуйте ещё раз.'), findsOneWidget);
    expect(find.textContaining('raw-sensitive'), findsNothing);
    expect(_controllers(tester), orderedEquals(controllers));
    expect(controllers.first.text, 'synthetic-login');
    expect(controllers.last.text, 'synthetic-password');
    expect(observer.sheetPops, 0);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    expect(auth.savedReads, 1);

    await tester.enterText(find.byType(TextField).last, 'corrected-fixture');
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    expect(auth.loginCalls, 2);
    expect(auth.lastPassword, 'corrected-fixture');
    auth.pendingLogin!.complete(_session());
    await tester.pumpAndSettle();
    expect(observer.sheetPops, 1);
    expect(find.text('Authenticated root'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final success in [true, false]) {
    testWidgets('dismiss pending login before ${success ? 'success' : 'error'}',
        (tester) async {
      final auth = _DelayedAuthController();
      final observer = _RouteObserver();
      await _pumpRoot(tester, auth, observer: observer);
      await _open(tester);
      final controllers = _controllers(tester);
      await _enterAndSubmit(tester);
      await tester.pump();
      await _dismiss(tester);
      _expectDisposed(controllers);
      if (success) {
        auth.pendingLogin!.complete(_session());
      } else {
        auth.pendingLogin!.completeError(StateError('fixture-error'));
      }
      await tester.pumpAndSettle();
      expect(observer.sheetPops, 1);
      expect(observer.otherPops, 0);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Не удалось войти. Попробуйте ещё раз.'), findsNothing);
      expect(find.text('Login successful'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('prefill completes safely after dismiss', (tester) async {
    final auth = _DelayedAuthController()
      ..pendingSaved = Completer<Map<String, String>>();
    await _pumpRoot(tester, auth);
    await _open(tester);
    final controllers = _controllers(tester);
    await _dismiss(tester);
    auth.pendingSaved!.complete({'login': 'late', 'password': 'late-secret'});
    await tester.pumpAndSettle();
    _expectDisposed(controllers);
    expect(auth.savedReads, 1);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prefill runs once and cannot overwrite input during its wait',
      (tester) async {
    final auth = _DelayedAuthController()
      ..pendingSaved = Completer<Map<String, String>>();
    await _pumpRoot(tester, auth);
    await _open(tester);
    await tester.enterText(find.byType(TextField).first, 'manual-login');
    auth.pendingSaved!.complete({
      'source': 'kundelik',
      'login': 'saved-login',
      'password': 'saved-password',
    });
    await tester.pumpAndSettle();
    final controllers = _controllers(tester);
    expect(controllers.first.text, 'manual-login');
    expect(controllers.last.text, 'saved-password');
    await tester.enterText(find.byType(TextField).last, 'manual-password');
    await tester.pumpAndSettle();
    expect(auth.savedReads, 1);
    await _dismiss(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ten sheet routes release fields and old listeners stay inactive',
      (tester) async {
    final auth = _DelayedAuthController();
    final observer = _RouteObserver();
    await _pumpRoot(tester, auth, observer: observer);
    final retired = <TextEditingController>[];
    for (var i = 0; i < 10; i++) {
      await _open(tester);
      retired.addAll(_controllers(tester));
      await _dismiss(tester);
    }
    _expectDisposed(retired);
    expect(auth.savedReads, 10);
    expect(observer.sheetPops, 10);
    await _open(tester);
    await _enterAndSubmit(tester);
    await tester.pump();
    auth.pendingLogin!.complete(_session());
    await tester.pumpAndSettle();
    auth.publishSession();
    await tester.pumpAndSettle();
    expect(auth.loginCalls, 1);
    expect(observer.sheetPops, 11);
    expect(observer.otherPops, 0);
    expect(find.text('Вход выполнен'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('success removes its own sheet without popping a newer route',
      (tester) async {
    final auth = _DelayedAuthController();
    final observer = _RouteObserver();
    await _pumpRoot(tester, auth, observer: observer);
    await _open(tester);
    await _enterAndSubmit(tester);
    await tester.pump();
    final navigator =
        Navigator.of(tester.element(find.byType(TextField).first));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Newer route'))));
    await tester.pump(const Duration(milliseconds: 400));
    auth.pendingLogin!.complete(_session());
    await tester.pumpAndSettle();
    expect(find.text('Newer route'), findsOneWidget);
    expect(observer.sheetRemovals, 1);
    expect(observer.otherPops, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'labels, field styling, long input and keyboard inset remain valid',
      (tester) async {
    final auth = _DelayedAuthController();
    await _pumpRoot(tester, auth);
    for (final provider in ['Kundelik.kz', 'Dnevnik.ru', 'EduPage']) {
      expect(find.text('Войти через $provider'), findsOneWidget);
    }
    await _open(tester);
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.map((f) => f.decoration!.labelText), ['Логин', 'Пароль']);
    expect(fields.first.style!.color, Colors.white);
    expect(fields.last.obscureText, isTrue);
    expect(fields.last.textInputAction, TextInputAction.done);
    expect(fields.first.decoration!.filled, isTrue);
    await tester.enterText(find.byType(TextField).first, 'длинный_логин_' * 40);
    await tester.enterText(find.byType(TextField).last, 'long-password-' * 40);
    final initialBottom = tester.getBottomRight(find.byType(FilledButton)).dy;
    tester.view.viewInsets =
        FakeViewPadding(bottom: 240 * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final keyboardBottom = tester.getBottomRight(find.byType(FilledButton)).dy;
    expect(initialBottom - keyboardBottom, closeTo(240, 1));
    expect(find.text('Логин'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dismiss(tester);
  });
}

AuthSession _session() => AuthSession(
    studentId: 'synthetic-student',
    accessToken: 'synthetic-token',
    refreshToken: 'synthetic-refresh',
    expiresAt: DateTime.utc(2030));

void _expectDisposed(List<TextEditingController> controllers) {
  for (final controller in controllers) {
    expect(() => controller.addListener(_noop), throwsFlutterError);
  }
}

void _noop() {}

Future<void> _dismiss(WidgetTester tester) async {
  await tester.tapAt(const Offset(5, 5));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

class _RouteObserver extends NavigatorObserver {
  int sheetPops = 0;
  int sheetRemovals = 0;
  int otherPops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalBottomSheetRoute) {
      sheetPops++;
    } else {
      otherPops++;
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalBottomSheetRoute) sheetRemovals++;
  }
}

Future<void> _pumpRoot(WidgetTester tester, _DelayedAuthController auth,
    {bool realApp = false, NavigatorObserver? observer}) async {
  await tester.binding.setSurfaceSize(const Size(500, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [authControllerProvider.overrideWith(() => auth)],
    child: realApp ? const KundiApp() : _AuthRoot(observer: observer),
  ));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Войти через Kundelik.kz'));
  await tester.pumpAndSettle();
}

List<TextEditingController> _controllers(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField))
    .map((field) => field.controller!)
    .toList();

Future<void> _enterAndSubmit(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'synthetic-login');
  await tester.enterText(find.byType(TextField).last, 'synthetic-password');
  await tester.tap(find.text('Продолжить'));
}

// The same auth-state root replacement as KundiApp, with the authenticated
// screen isolated from unrelated database/native-avatar bootstrap work.
class _AuthRoot extends ConsumerWidget {
  const _AuthRoot({this.observer});
  final NavigatorObserver? observer;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        navigatorObservers: [if (observer != null) observer!],
        home: ref.watch(authControllerProvider).when(
              data: (session) => session == null
                  ? const AuthPage()
                  : const Scaffold(body: Text('Authenticated root')),
              loading: () => const Scaffold(
                  body: Center(child: CircularProgressIndicator())),
              error: (_, __) => const AuthPage(),
            ),
      );
}

class _DelayedAuthController extends AuthController {
  int loginCalls = 0;
  int savedReads = 0;
  Completer<AuthSession?>? pendingLogin;
  Completer<Map<String, String>>? pendingSaved;
  String lastPassword = '';

  void publishSession() => state = AsyncData<AuthSession?>(_session());

  @override
  Future<AuthSession?> build() async => null;

  @override
  Future<Map<String, String>> loadSavedCredentials() {
    savedReads++;
    return pendingSaved?.future ?? Future.value(<String, String>{});
  }

  @override
  Future<void> login(
      {required String source,
      required String login,
      required String password}) async {
    loginCalls++;
    lastPassword = password;
    pendingLogin = Completer<AuthSession?>();
    state = const AsyncLoading<AuthSession?>();
    state = await AsyncValue.guard(() => pendingLogin!.future);
  }
}
