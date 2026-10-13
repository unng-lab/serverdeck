import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SubmitFormIntent extends Intent {
  const SubmitFormIntent();
}

class _CloseFormIntent extends Intent {
  const _CloseFormIntent();
}

/// Escape applies to the form. Enter applies only to opted-in single-line
/// fields; buttons/selectors keep activation and multiline fields keep newline.
class FormKeyboard extends StatelessWidget {
  const FormKeyboard({
    super.key,
    required this.onSubmit,
    required this.onClose,
    required this.child,
  });
  final VoidCallback onSubmit, onClose;
  final Widget child;
  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): _CloseFormIntent(),
    },
    child: Actions(
      actions: {
        SubmitFormIntent: CallbackAction<SubmitFormIntent>(
          onInvoke: (_) {
            onSubmit();
            return null;
          },
        ),
        _CloseFormIntent: CallbackAction<_CloseFormIntent>(
          onInvoke: (_) {
            onClose();
            return null;
          },
        ),
      },
      child: FocusScope(autofocus: true, child: child),
    ),
  );
}

class SubmitOnEnter extends StatelessWidget {
  const SubmitOnEnter({super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;
  @override
  Widget build(BuildContext context) => enabled
      ? Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): SubmitFormIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): SubmitFormIntent(),
          },
          child: child,
        )
      : child;
}
