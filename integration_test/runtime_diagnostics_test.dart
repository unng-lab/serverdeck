import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverdeck/diagnostics/ui_runtime_diagnostics.dart';

final class _PrivateFault {
  int stringifications = 0;
  @override
  String toString() {
    stringifications++;
    return 'synthetic-password-231 synthetic-private-key-231 '
        'synthetic-passphrase-231 C:\\synthetic-private-path-231';
  }
}

final class _BrokenWidget extends StatelessWidget {
  const _BrokenWidget(this.fault);
  final Object fault;
  @override
  Widget build(BuildContext context) => throw fault;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('compiled runtime diagnostic privacy boundaries', (tester) async {
    final framework = FlutterError.onError;
    final platform = PlatformDispatcher.instance.onError;
    final builder = ErrorWidget.builder;
    final console = debugPrint;
    final output = <String?>[];
    final observations = <FlutterErrorDetails>[];
    final secret = _PrivateFault();
    var collectors = 0;
    ErrorWidget? fallback;
    try {
      debugPrint = (message, {wrapWidth}) => output.add(message);
      FlutterError.onError = observations.add;
      PlatformDispatcher.instance.onError = (error, stack) {
        if (error is! UiRuntimeFault ||
            error.category != UiRuntimeFaultCategory.unhandled ||
            stack.toString().isNotEmpty) {
          throw StateError('PLATFORM_SANITIZATION_FAILED');
        }
        return false;
      };
      installUiRuntimeDiagnostics();
      final details = FlutterErrorDetails(
        exception: secret,
        stack: StackTrace.fromString('synthetic-private-path-231'),
        library: 'synthetic-password-231',
        context: ErrorDescription('synthetic-passphrase-231'),
        informationCollector: () {
          collectors++;
          return [ErrorDescription('synthetic-private-key-231')];
        },
      );
      FlutterError.reportError(details);
      final handled = PlatformDispatcher.instance.onError!(
        secret,
        details.stack!,
      );
      fallback = ErrorWidget.builder(details) as ErrorWidget;
      if (!handled || observations.length != 2) {
        throw StateError('RUNTIME_OBSERVATION_COUNT_FAILED');
      }
      for (var i = 0; i < observations.length; i++) {
        final safe = observations[i];
        final category = i == 0
            ? UiRuntimeFaultCategory.framework
            : UiRuntimeFaultCategory.unhandled;
        if (safe.exception is! UiRuntimeFault ||
            safe.exception.toString() != category.code ||
            safe.stack.toString().isNotEmpty ||
            safe.library != 'ServerDeck UI' ||
            safe.context.toString() != 'Локальная ошибка интерфейса' ||
            safe.informationCollector != null ||
            safe.stackFilter != null) {
          throw StateError('RUNTIME_SANITIZATION_FAILED');
        }
      }
      FlutterError.onError = null;
      PlatformDispatcher.instance.onError = null;
      installUiRuntimeDiagnostics();
      FlutterError.reportError(details);
      if (!PlatformDispatcher.instance.onError!(secret, details.stack!)) {
        throw StateError('RAW_ENGINE_FALLBACK_ALLOWED');
      }
      if (!listEquals(output, [
            UiRuntimeFaultCategory.framework.code,
            UiRuntimeFaultCategory.unhandled.code,
          ]) ||
          secret.stringifications != 0 ||
          collectors != 0) {
        throw StateError('RUNTIME_OUTPUT_PRIVACY_FAILED');
      }
      FlutterError.onError = observations.add;
      installUiRuntimeDiagnostics();
      await tester.pumpWidget(_BrokenWidget(secret));
      final rendered = tester.widget<ErrorWidget>(find.byType(ErrorWidget));
      if (observations.length != 3 ||
          (observations.last.exception as UiRuntimeFault).category !=
              UiRuntimeFaultCategory.framework ||
          rendered.message != uiRuntimeFallbackMessage ||
          secret.stringifications != 0) {
        throw StateError('RUNTIME_BUILD_FALLBACK_FAILED');
      }
    } finally {
      FlutterError.onError = framework;
      PlatformDispatcher.instance.onError = platform;
      ErrorWidget.builder = builder;
      debugPrint = console;
    }
    expect(fallback.message, uiRuntimeFallbackMessage);
    expect(find.byType(ErrorWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Fixed proof only, after all output/observer/render assertions.
    // ignore: avoid_print
    print('COMPILED_UI_RUNTIME_DIAGNOSTICS_PRIVACY_PROVED');
  });
}
