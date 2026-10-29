import 'package:flutter/material.dart';

import '../shell/private_session.dart';
import '../ui/deck_components.dart';
import '../ui/deck_icon.dart';
import 'brand_theme.dart';

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
        style: style.merge(base.filledButtonTheme.style),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: style.merge(base.elevatedButtonTheme.style),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: style.merge(base.iconButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: style.merge(base.outlinedButtonTheme.style),
      ),
      textButtonTheme: TextButtonThemeData(
        style: style.merge(base.textButtonTheme.style),
      ),
    );
  }
}

Future<T?> showMotionDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  bool privateContent = true,
  Color? barrierColor,
}) async {
  final launcher = FocusManager.instance.primaryFocus;
  final launchScope = FocusScope.of(context, createDependency: false);
  final launchRoute = ModalRoute.of(launchScope.context ?? context);
  final launchEpoch = privateContent
      ? PrivateSessionScope.maybeOf(context)?.epoch
      : null;
  final result = await showDialog<T>(
    context: context,
    builder: privateContent
        ? (context) =>
              PrivateDialogGate(launchEpoch: launchEpoch, builder: builder)
        : builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    animationStyle: Motion.reduced(context) ? AnimationStyle.noAnimation : null,
  );
  // Flutter restores a surviving launcher. If it was removed while the modal
  // was open, move to an existing control only in the still-current route and
  // session. Focus movement never invokes an action or revives a private owner.
  final scopeContext = launchScope.context;
  if (launcher != null &&
      launcher.context?.mounted != true &&
      launchRoute?.isCurrent == true &&
      scopeContext != null &&
      scopeContext.mounted) {
    final session = PrivateSessionScope.maybeOf(scopeContext);
    if (launchEpoch == null ||
        (session?.authorized == true && session?.epoch == launchEpoch)) {
      launchScope.nextFocus();
    }
  }
  return result;
}

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
    final fieldDecoration = decoration.copyWith(
      isDense: decoration.isDense ?? true,
      contentPadding:
          decoration.contentPadding ??
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
    if (!Motion.reduced(context))
      return DropdownButtonFormField<T>(
        initialValue: initialValue,
        isDense: false,
        iconSize: 16,
        icon: const DeckIcon('chevron', size: 16),
        iconEnabledColor: Theme.of(context).extension<BrandColors>()!['text'],
        iconDisabledColor: Theme.of(context)
            .extension<BrandColors>()!['disabled'],
        style: BrandTypography.body.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        itemHeight: null,
        // Popup options retain their normal touch targets. The closed field
        // uses the original child directly so multiline values determine its
        // height instead of a dense button's single-line fixed height.
        selectedItemBuilder: (context) {
          final field = context.findAncestorStateOfType<FormFieldState<T>>();
          final current = field == null ? initialValue : field.value;
          return [
            for (final item in items)
              if (item.value == current)
                Align(
                  alignment: item.alignment,
                  heightFactor: 1,
                  child: _selectedValue(context, item.child, item.value),
                )
              else
                const SizedBox.shrink(),
          ];
        },
        items: [
          for (final item in items)
            DropdownMenuItem<T>(
              key: item.key,
              value: item.value,
              onTap: item.onTap,
              enabled: item.enabled,
              alignment: item.alignment,
              child: DeckFocusLabel(child: item.child),
            ),
        ],
        decoration: fieldDecoration,
        onChanged: onChanged,
        isExpanded: isExpanded,
      );
    final selected = items
        .where((item) => item.value == initialValue)
        .firstOrNull;
    return _StaticSelectField(
      decoration: fieldDecoration,
      isExpanded: isExpanded,
      value: selected == null
          ? null
          : _selectedValue(context, selected.child, selected.value),
      onPressed: onChanged == null || !items.any((item) => item.enabled)
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
                              if (decoration.labelText?.isNotEmpty ?? false)
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
                                  clipBehavior: Clip.none,
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                  onPressed: item.enabled
                                      ? () {
                                          if (!(available?.call() ?? true))
                                            return;
                                          item.onTap?.call();
                                          Navigator.of(dialogContext)
                                              .pop(item.value);
                                        }
                                      : null,
                                  child: Semantics(
                                    selected: item.value == initialValue,
                                    child: item.child,
                                  ),
                                ),
                              TextButton(
                                clipBehavior: Clip.none,
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
    );
  }

  Widget _selectedValue(BuildContext context, Widget value, Object? identity) =>
      MediaQuery.textScalerOf(context).scale(14) <= 14
      ? SingleChildScrollView(
          key: ValueKey(identity),
          scrollDirection: Axis.horizontal,
          primary: false,
          child: value,
        )
      : value;
}

/// Reduced motion changes the popup route, not the closed select composition.
class _StaticSelectField extends StatefulWidget {
  const _StaticSelectField({
    required this.decoration,
    required this.isExpanded,
    required this.value,
    required this.onPressed,
  });
  final InputDecoration decoration;
  final bool isExpanded;
  final Widget? value;
  final VoidCallback? onPressed;
  @override
  State<_StaticSelectField> createState() => _StaticSelectFieldState();
}

class _StaticSelectFieldState extends State<_StaticSelectField> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final colors = Theme.of(context).extension<BrandColors>()!;
    final value = widget.value ?? const SizedBox.shrink();
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onPressed,
          onFocusChange: (value) => setState(() => _focused = value),
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            isFocused: _focused,
            isEmpty: widget.value == null,
            decoration: widget.decoration
                .applyDefaults(InputDecorationTheme.of(context))
                .copyWith(
                  enabled: enabled,
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 16,
                  ),
                  suffixIcon: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: DeckIcon(
                      'chevron',
                      size: 16,
                      color: colors[enabled ? 'text' : 'disabled'],
                    ),
                  ),
                ),
            child: DefaultTextStyle(
              style: BrandTypography.body.copyWith(
                color: colors[enabled ? 'text' : 'disabled'],
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.textScalerOf(context).scale(20),
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  heightFactor: 1,
                  widthFactor: widget.isExpanded ? null : 1,
                  child: value,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
