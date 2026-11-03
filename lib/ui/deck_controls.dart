import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/brand_tokens.dart';
import '../theme/brand_theme.dart';
import 'deck_components.dart';

enum DeckButtonKind { primary, secondary, text, danger }

/// Material controls share the application theme; this adapter adds a synchronous
/// duplicate-submit guard without owning requests, permissions, or recovery.
class DeckButton extends StatefulWidget {
  const DeckButton({
    super.key,
    required this.child,
    this.onPressed,
    this.kind = DeckButtonKind.secondary,
    this.pending = false,
    this.disabledReason,
    this.style,
    this.autofocus = false,
    this.statesController,
  });

  final Widget child;
  final FutureOr<void> Function()? onPressed;
  final DeckButtonKind kind;
  final bool pending;
  final String? disabledReason;
  final ButtonStyle? style;
  final bool autofocus;
  final WidgetStatesController? statesController;

  @override
  State<DeckButton> createState() => _DeckButtonState();
}

class _DeckButtonState extends State<DeckButton> {
  bool _running = false;

  Future<void> _activate() async {
    if (_running || widget.pending || widget.onPressed == null) return;
    setState(() => _running = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _running || widget.pending;
    final callback = pending || widget.onPressed == null ? null : _activate;
    final child = pending
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top, size: BrandGeometry.iconSize),
              const SizedBox(width: BrandSpacing.space8),
              Flexible(child: widget.child),
            ],
          )
        : widget.child;
    final button = switch (widget.kind) {
      DeckButtonKind.primary => FilledButton(
        statesController: widget.statesController,
        autofocus: widget.autofocus,
        onPressed: callback,
        style: widget.style,
        child: child,
      ),
      DeckButtonKind.text => TextButton(
        statesController: widget.statesController,
        autofocus: widget.autofocus,
        onPressed: callback,
        style: widget.style,
        child: child,
      ),
      DeckButtonKind.secondary || DeckButtonKind.danger => OutlinedButton(
        statesController: widget.statesController,
        autofocus: widget.autofocus,
        onPressed: callback,
        style: widget.kind == DeckButtonKind.danger
            ? OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ).merge(widget.style)
            : widget.style,
        child: child,
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(liveRegion: pending, child: button),
        if (widget.disabledReason != null && callback == null) ...[
          const SizedBox(height: BrandSpacing.space4),
          Text(widget.disabledReason!),
        ],
      ],
    );
  }
}

/// Field values/controllers and validators remain owned by the feature form.
class DeckTextField extends StatefulWidget {
  const DeckTextField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.validator,
    this.helper,
    this.error,
    this.enabled = true,
    this.readOnly = false,
    this.secret = false,
    this.maxLines = 1,
    this.keyboardType,
    this.focusNode,
    this.onFieldSubmitted,
    this.autovalidateMode,
    this.style,
    this.prefixText,
    this.suffixText,
  });

  final String label;
  final TextEditingController? controller;
  final String? initialValue, helper, error;
  final ValueChanged<String>? onChanged, onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  final bool enabled, readOnly, secret;
  final int? maxLines;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final AutovalidateMode? autovalidateMode;
  final TextStyle? style;
  final String? prefixText, suffixText;

  @override
  State<DeckTextField> createState() => _DeckTextFieldState();
}

class _DeckTextFieldState extends State<DeckTextField> {
  bool _revealed = false;

  @override
  void didUpdateWidget(covariant DeckTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller || !widget.enabled) {
      _revealed = false;
    }
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: widget.secret
        ? const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.keyC, control: true):
                DoNothingAndStopPropagationIntent(),
            SingleActivator(LogicalKeyboardKey.keyX, control: true):
                DoNothingAndStopPropagationIntent(),
            SingleActivator(LogicalKeyboardKey.insert, control: true):
                DoNothingAndStopPropagationIntent(),
            SingleActivator(LogicalKeyboardKey.delete, shift: true):
                DoNothingAndStopPropagationIntent(),
            SingleActivator(LogicalKeyboardKey.keyC, meta: true):
                DoNothingAndStopPropagationIntent(),
            SingleActivator(LogicalKeyboardKey.keyX, meta: true):
                DoNothingAndStopPropagationIntent(),
          }
        : const <ShortcutActivator, Intent>{},
    child: DeckFieldFrame(
      label: widget.label,
      child: TextFormField(
        controller: widget.controller,
        initialValue: widget.controller == null ? widget.initialValue : null,
        focusNode: widget.focusNode,
        onChanged: widget.onChanged,
        onFieldSubmitted: widget.onFieldSubmitted,
        validator: widget.validator,
        autovalidateMode: widget.autovalidateMode,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        obscureText: widget.secret && !_revealed,
        enableSuggestions: !widget.secret,
        autocorrect: !widget.secret,
        enableIMEPersonalizedLearning: !widget.secret,
        contextMenuBuilder: (context, state) =>
            AdaptiveTextSelectionToolbar.buttonItems(
              anchors: state.contextMenuAnchors,
              buttonItems: state.contextMenuButtonItems
                  .where(
                    (item) =>
                        !widget.secret ||
                        (item.type != ContextMenuButtonType.copy &&
                            item.type != ContextMenuButtonType.cut),
                  )
                  .toList(),
            ),
        maxLines: widget.secret ? 1 : widget.maxLines,
        keyboardType: widget.keyboardType,
        style: (widget.style ?? BrandTypography.body).copyWith(
          color: Theme.of(context)
              .extension<BrandColors>()![widget.enabled ? 'text' : 'disabled'],
        ),
        decoration: InputDecoration(
          prefixText: widget.prefixText,
          suffixText: widget.suffixText,
          helper: widget.helper == null ? null : Text(widget.helper!),
          errorMaxLines: 20,
          errorText: widget.error,
          suffixIcon: widget.secret
              ? IconButton(
                  tooltip: _revealed ? 'Скрыть пароль' : 'Показать пароль',
                  onPressed: widget.enabled
                      ? () => setState(() => _revealed = !_revealed)
                      : null,
                  icon: Icon(
                    _revealed ? Icons.visibility_off : Icons.visibility,
                  ),
                )
              : null,
        ),
      ),
    ),
  );
}

/// The full label wraps at large text scales; the control gets the same
/// accessible name without an ellipsized floating InputDecorator label.
class DeckFieldFrame extends StatelessWidget {
  const DeckFieldFrame({super.key, required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(
        child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
      ),
      const SizedBox(height: BrandSpacing.space8),
      Semantics(label: label, child: child),
    ],
  );
}

class DeckSearch extends StatelessWidget {
  const DeckSearch({
    super.key,
    required this.controller,
    required this.onChanged,
    this.label = 'Поиск',
    this.filters = const [],
    this.enabled = true,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String label;
  final List<Widget> filters;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        enabled: enabled,
        style: BrandTypography.body.copyWith(
          color: Theme.of(context)
              .extension<BrandColors>()![enabled ? 'text' : 'disabled'],
        ),
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'Очистить поиск',
            onPressed: !enabled
                ? null
                : () {
                    controller.clear();
                    onChanged('');
                  },
            icon: const Icon(Icons.close),
          ),
        ),
      ),
      if (filters.isNotEmpty) ...[
        const SizedBox(height: BrandSpacing.space12),
        DeckActions(children: filters),
      ],
    ],
  );
}
