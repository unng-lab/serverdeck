import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/diagnostics/ui_runtime_diagnostics.dart';

final class _SecretException {
  int calls = 0;
  @override
  String toString() {
    calls++;
    throw StateError('synthetic-password-key-passphrase-private-path');
  }
}

final class _BrokenWidget extends StatelessWidget {
  const _BrokenWidget(this.error);
  final Object error;
  @override
  Widget build(BuildContext context) => throw error;
}

void main() {
  late FlutterExceptionHandler? originalFramework;
  late bool Function(Object, StackTrace)? originalPlatform;
  late ErrorWidgetBuilder originalBuilder;
  late DebugPrintCallback originalPrint;
  late List<String?> output;
  setUp(() {
    originalFramework = FlutterError.onError;
    originalPlatform = PlatformDispatcher.instance.onError;
    originalBuilder = ErrorWidget.builder;
    originalPrint = debugPrint;
    output = [];
    debugPrint = (message, {wrapWidth}) => output.add(message);
  });
  tearDown(() {
    FlutterError.onError = originalFramework;
    PlatformDispatcher.instance.onError = originalPlatform;
    ErrorWidget.builder = originalBuilder;
    debugPrint = originalPrint;
  });

  void safe(FlutterErrorDetails details, UiRuntimeFaultCategory category) {
    expect(details.exception, isA<UiRuntimeFault>());
    expect(details.exception.toString(), category.code);
    expect(details.stack, same(StackTrace.empty));
    expect(details.library, 'ServerDeck UI');
    expect(details.context.toString(), 'Локальная ошибка интерфейса');
    expect(details.informationCollector, isNull);
    expect(details.stackFilter, isNull);
  }

  test('framework discards every source field without stringification', () {
    final secret = _SecretException();
    var collected = 0;
    var filtered = 0;
    var observed = 0;
    FlutterError.onError = (details) {
      observed++;
      safe(details, UiRuntimeFaultCategory.framework);
      expect(details.silent, true);
    };
    installUiRuntimeDiagnostics();
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: secret,
        stack: StackTrace.fromString('synthetic-key'),
        library: 'synthetic-password',
        context: ErrorDescription('synthetic-private-path'),
        informationCollector: () {
          collected++;
          return [ErrorDescription('synthetic-passphrase')];
        },
        stackFilter: (lines) {
          filtered++;
          return lines;
        },
        silent: true,
      ),
    );
    expect([secret.calls, collected, filtered, observed], [0, 0, 0, 1]);
    expect(output, isEmpty);
  });

  test('ordinary typed faults cannot spoof a runtime source category', () {
    FlutterError.onError = (details) =>
        safe(details, UiRuntimeFaultCategory.framework);
    installUiRuntimeDiagnostics();
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: const UiRuntimeFault(UiRuntimeFaultCategory.unhandled),
      ),
    );
  });

  test('repeated installation and saved callbacks preserve observer A', () {
    var a = 0;
    var b = 0;
    var pa = 0;
    var pb = 0;
    FlutterError.onError = (_) => a++;
    PlatformDispatcher.instance.onError = (_, stack) {
      pa++;
      expect(stack, same(StackTrace.empty));
      return false;
    };
    installUiRuntimeDiagnostics();
    final frameworkA = FlutterError.onError;
    final platformA = PlatformDispatcher.instance.onError;
    installUiRuntimeDiagnostics();
    expect(FlutterError.onError, same(frameworkA));
    expect(PlatformDispatcher.instance.onError, same(platformA));
    FlutterError.onError = (_) => b++;
    PlatformDispatcher.instance.onError = (_, _) {
      pb++;
      return true;
    };
    installUiRuntimeDiagnostics();
    FlutterError.reportError(
      FlutterErrorDetails(exception: _SecretException()),
    );
    expect(
      PlatformDispatcher.instance.onError!(
        _SecretException(),
        StackTrace.empty,
      ),
      true,
    );
    FlutterError.onError = frameworkA;
    PlatformDispatcher.instance.onError = platformA;
    installUiRuntimeDiagnostics();
    expect(
      PlatformDispatcher.instance.onError!(
        _SecretException(),
        StackTrace.empty,
      ),
      true,
    );
    expect([a, b, pa, pb], [1, 1, 1, 1]);
  });

  test('restored null predecessors emit fixed console values', () {
    FlutterError.onError = null;
    PlatformDispatcher.instance.onError = null;
    installUiRuntimeDiagnostics();
    final a = FlutterError.onError;
    final pa = PlatformDispatcher.instance.onError;
    FlutterError.onError = (_) => fail('replacement observer invoked');
    PlatformDispatcher.instance.onError = (_, _) => throw StateError('secret');
    installUiRuntimeDiagnostics();
    FlutterError.onError = a;
    PlatformDispatcher.instance.onError = pa;
    installUiRuntimeDiagnostics();
    FlutterError.reportError(
      FlutterErrorDetails(exception: _SecretException()),
    );
    expect(pa!(_SecretException(), StackTrace.fromString('secret')), true);
    expect(output, [
      UiRuntimeFaultCategory.framework.code,
      UiRuntimeFaultCategory.unhandled.code,
    ]);
  });

  for (final consumes in [false, true]) {
    test(
      'platform observer consumed=$consumes gets sanitized payload once',
      () {
        var observed = 0;
        var framework = 0;
        FlutterError.onError = (details) {
          framework++;
          safe(details, UiRuntimeFaultCategory.unhandled);
        };
        PlatformDispatcher.instance.onError = (error, stack) {
          observed++;
          expect(error.toString(), UiRuntimeFaultCategory.unhandled.code);
          expect(stack, same(StackTrace.empty));
          return consumes;
        };
        installUiRuntimeDiagnostics();
        final secret = _SecretException();
        expect(
          PlatformDispatcher.instance.onError!(
            secret,
            StackTrace.fromString('secret'),
          ),
          true,
        );
        expect([observed, framework, secret.calls], [1, consumes ? 0 : 1, 0]);
      },
    );
  }

  test('throwing platform observer reports handler failure', () {
    FlutterError.onError = (details) =>
        safe(details, UiRuntimeFaultCategory.handler);
    PlatformDispatcher.instance.onError = (_, _) => throw _SecretException();
    installUiRuntimeDiagnostics();
    expect(
      PlatformDispatcher.instance.onError!(
        _SecretException(),
        StackTrace.empty,
      ),
      true,
    );
  });

  test(
    'framework observer failure stays observable with an empty safe stack',
    () {
      var calls = 0;
      FlutterError.onError = (_) {
        calls++;
        throw _SecretException();
      };
      installUiRuntimeDiagnostics();
      for (var i = 0; i < 2; i++) {
        try {
          FlutterError.reportError(
            FlutterErrorDetails(exception: _SecretException()),
          );
          fail('failure swallowed');
        } on UiRuntimeFault catch (error, stack) {
          expect(error.category, UiRuntimeFaultCategory.handler);
          expect(stack.toString(), isEmpty);
        }
      }
      expect(calls, 2);
    },
  );

  test('framework reentrancy does not recursively delegate', () {
    var calls = 0;
    FlutterError.onError = (_) {
      calls++;
      FlutterError.reportError(
        FlutterErrorDetails(exception: _SecretException()),
      );
    };
    installUiRuntimeDiagnostics();
    expect(
      () => FlutterError.reportError(
        FlutterErrorDetails(exception: _SecretException()),
      ),
      throwsA(isA<UiRuntimeFault>()),
    );
    expect(calls, 1);
  });

  test('platform reentrancy and failed sinks never allow raw fallback', () {
    var calls = 0;
    FlutterError.onError = (_) => throw _SecretException();
    PlatformDispatcher.instance.onError = (_, _) {
      calls++;
      expect(
        PlatformDispatcher.instance.onError!(
          _SecretException(),
          StackTrace.empty,
        ),
        true,
      );
      return false;
    };
    installUiRuntimeDiagnostics();
    debugPrint = (_, {wrapWidth}) => throw _SecretException();
    expect(
      PlatformDispatcher.instance.onError!(
        _SecretException(),
        StackTrace.empty,
      ),
      true,
    );
    expect(calls, 1);
  });

  test('null framework observer sink failure is observable and safe', () {
    FlutterError.onError = null;
    installUiRuntimeDiagnostics();
    debugPrint = (_, {wrapWidth}) => throw _SecretException();
    expect(
      () => FlutterError.reportError(
        FlutterErrorDetails(exception: _SecretException()),
      ),
      throwsA(isA<UiRuntimeFault>()),
    );
  });

  testWidgets('test binding retains an unexpected framework failure safely', (
    tester,
  ) async {
    final framework = FlutterError.onError;
    final platform = PlatformDispatcher.instance.onError;
    final secret = _SecretException();
    debugPrint = originalPrint;
    try {
      installUiRuntimeDiagnostics();
      await tester.pumpWidget(_BrokenWidget(secret));
    } finally {
      FlutterError.onError = framework;
      PlatformDispatcher.instance.onError = platform;
      ErrorWidget.builder = originalBuilder;
      debugPrint = originalPrint;
    }
    final failure = tester.takeException();
    expect(failure, isA<UiRuntimeFault>());
    expect(
      (failure as UiRuntimeFault).category,
      UiRuntimeFaultCategory.framework,
    );
    expect(secret.calls, 0);
    expect(
      tester.widget<ErrorWidget>(find.byType(ErrorWidget)).message,
      uiRuntimeFallbackMessage,
    );
  });

  testWidgets(
    'fallback renders fixed message without ancestors or old builder',
    (tester) async {
      final testFramework = FlutterError.onError;
      final testPlatform = PlatformDispatcher.instance.onError;
      ErrorWidget.builder = (_) => throw _SecretException();
      installUiRuntimeDiagnostics();
      final secret = _SecretException();
      final widget = ErrorWidget.builder(
        FlutterErrorDetails(exception: secret),
      ) as ErrorWidget;
      FlutterError.onError = testFramework;
      PlatformDispatcher.instance.onError = testPlatform;
      ErrorWidget.builder = originalBuilder;
      debugPrint = originalPrint;
      expect(widget.message, uiRuntimeFallbackMessage);
      await tester.pumpWidget(widget);
      expect(find.byType(ErrorWidget), findsOneWidget);
      expect(secret.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
