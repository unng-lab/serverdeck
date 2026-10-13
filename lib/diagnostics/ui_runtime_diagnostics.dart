import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum UiRuntimeFaultCategory {
  framework('SERVERDECK_UI_FRAMEWORK_INTERNAL'),
  unhandled('SERVERDECK_UI_UNHANDLED_INTERNAL'),
  handler('SERVERDECK_UI_DIAGNOSTIC_HANDLER_FAILED');

  const UiRuntimeFaultCategory(this.code);
  final String code;
}

final class UiRuntimeFault implements Exception {
  const UiRuntimeFault(this.category);
  final UiRuntimeFaultCategory category;

  @override
  String toString() => category.code;
}

const uiRuntimeFallbackMessage =
    'Локальная ошибка интерфейса ServerDeck. Перезапустите клиент и проверьте результат сохранения.';

final _frameworkBindings = Expando<_FrameworkBinding>();
final _platformBindings = Expando<_PlatformBinding>();

FlutterErrorDetails _details(
  UiRuntimeFaultCategory category, {
  bool silent = false,
}) => _RuntimeDetails(category, silent: silent);

final class _RuntimeDetails extends FlutterErrorDetails {
  _RuntimeDetails(this.category, {bool silent = false})
    : super(
        exception: UiRuntimeFault(category),
        stack: StackTrace.empty,
        library: 'ServerDeck UI',
        context: ErrorDescription('Локальная ошибка интерфейса'),
        silent: silent,
      );
  final UiRuntimeFaultCategory category;
}

Never _handlerFailure() => Error.throwWithStackTrace(
  const UiRuntimeFault(UiRuntimeFaultCategory.handler),
  StackTrace.empty,
);

void _console(UiRuntimeFaultCategory category) => debugPrint(category.code);

void _bestEffortHandlerConsole() {
  try {
    _console(UiRuntimeFaultCategory.handler);
  } catch (_) {
    // Never permit the engine to fall back to the original platform payload.
  }
}

final class _FrameworkBinding {
  _FrameworkBinding(this.observer);
  final FlutterExceptionHandler? observer;
  bool active = false;
  late final FlutterExceptionHandler callback = report;

  void report(FlutterErrorDetails input) {
    if (active) _handlerFailure();
    active = true;
    try {
      final safe = _details(
        input is _RuntimeDetails
            ? input.category
            : UiRuntimeFaultCategory.framework,
        silent: input.silent,
      );
      final delegate = observer;
      if (delegate == null) {
        _console((safe.exception as UiRuntimeFault).category);
      } else {
        delegate(safe);
      }
    } catch (_) {
      _handlerFailure();
    } finally {
      active = false;
    }
  }
}

final class _PlatformBinding {
  _PlatformBinding(this.observer);
  final bool Function(Object, StackTrace)? observer;
  bool active = false;
  late final bool Function(Object, StackTrace) callback = report;

  bool report(Object error, StackTrace stack) {
    if (active) {
      _bestEffortHandlerConsole();
      return true;
    }
    active = true;
    try {
      var category = UiRuntimeFaultCategory.unhandled;
      try {
        if (observer?.call(UiRuntimeFault(category), StackTrace.empty) ==
            true) {
          return true;
        }
      } catch (_) {
        category = UiRuntimeFaultCategory.handler;
      }
      try {
        FlutterError.reportError(_details(category));
      } catch (_) {
        _bestEffortHandlerConsole();
      }
      return true;
    } finally {
      active = false;
    }
  }
}

void installUiRuntimeDiagnostics() {
  final framework = FlutterError.onError;
  if (framework == null || _frameworkBindings[framework] == null) {
    final binding = _FrameworkBinding(framework);
    _frameworkBindings[binding.callback] = binding;
    FlutterError.onError = binding.callback;
  }
  final platform = PlatformDispatcher.instance.onError;
  if (platform == null || _platformBindings[platform] == null) {
    final binding = _PlatformBinding(platform);
    _platformBindings[binding.callback] = binding;
    PlatformDispatcher.instance.onError = binding.callback;
  }
  ErrorWidget.builder = (_) =>
      ErrorWidget.withDetails(message: uiRuntimeFallbackMessage);
}
