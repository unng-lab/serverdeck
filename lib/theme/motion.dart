import 'package:flutter/material.dart';

/// Reduce large transitions; keep feedback, focus, text input and timers live.
abstract final class Motion {
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  static ThemeData theme(ThemeData base, bool reduced) {
    if (!reduced) return base;
    const style = ButtonStyle(
      animationDuration: Duration.zero,
      splashFactory: NoSplash.splashFactory,
    );
    return base.copyWith(
      splashFactory: NoSplash.splashFactory,
      expansionTileTheme: base.expansionTileTheme.copyWith(
        expansionAnimationStyle: AnimationStyle.noAnimation,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.merge(style) ?? style,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: base.outlinedButtonTheme.style?.merge(style) ?? style,
      ),
      textButtonTheme: TextButtonThemeData(
        style: base.textButtonTheme.style?.merge(style) ?? style,
      ),
    );
  }
}

Future<T?> showMotionDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: barrierDismissible,
  animationStyle: Motion.reduced(context) ? AnimationStyle.noAnimation : null,
);

/// Flutter's dropdown route has a fixed duration. Reduced mode uses a static
/// modal list with the same values and explicit selection/cancellation.
class MotionDropdown<T> extends StatelessWidget {
  const MotionDropdown({
    super.key,
    required this.initialValue,
    required this.items,
    required this.decoration,
    required this.onChanged,
    this.isExpanded = true,
    this.changes,
    this.available,
  });
  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final InputDecoration decoration;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;
  final Listenable? changes;
  final bool Function()? available;

  @override
  Widget build(BuildContext context) {
    if (!Motion.reduced(context))
      return DropdownButtonFormField<T>(
        initialValue: initialValue,
        items: items,
        decoration: decoration,
        onChanged: onChanged,
        isExpanded: isExpanded,
      );
    final selected = items
        .where((item) => item.value == initialValue)
        .firstOrNull;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: onChanged == null
          ? null
          : () async {
              final value = await showMotionDialog<T>(
                context: context,
                barrierDismissible: true,
                builder: (dialogContext) => ListenableBuilder(
                  listenable:
                      changes ?? const AlwaysStoppedAnimation<bool>(true),
                  builder: (dialogContext, _) => Dialog(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                decoration.labelText ?? '',
                                style: Theme.of(dialogContext)
                                    .textTheme
                                    .titleLarge,
                              ),
                              if (!(available?.call() ?? true))
                                const Text(
                                  'Выбор недоступен: локальная служба не готова',
                                ),
                              for (final item
                                  in (available?.call() ?? true)
                                      ? items
                                      : <DropdownMenuItem<T>>[])
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                  onPressed: item.enabled
                                      ? () =>
                                            Navigator.of(dialogContext)
                                                .pop(item.value)
                                      : null,
                                  child: Semantics(
                                    selected: item.value == initialValue,
                                    child: item.child,
                                  ),
                                ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                child: const Text('Отмена'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              if (context.mounted &&
                  value != null &&
                  (available?.call() ?? true))
                onChanged?.call(value);
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(decoration.labelText ?? ''),
          if (selected != null) selected.child,
        ],
      ),
    );
  }
}
