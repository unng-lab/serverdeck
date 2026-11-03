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
