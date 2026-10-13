import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' as testing;

/// Production startup owns global hooks. Restore the test binding's exact hooks
/// before it verifies invariants, including when a scenario throws.
void testWidgetsWithRuntimeHooks(
  String description,
  Future<void> Function(testing.WidgetTester) callback,
) {
  testing.testWidgets(description, (tester) async {
    final framework = FlutterError.onError;
    final platform = PlatformDispatcher.instance.onError;
    final builder = ErrorWidget.builder;
    final console = debugPrint;
    try {
      await callback(tester);
    } finally {
      FlutterError.onError = framework;
      PlatformDispatcher.instance.onError = platform;
      ErrorWidget.builder = builder;
      debugPrint = console;
    }
  });
}
