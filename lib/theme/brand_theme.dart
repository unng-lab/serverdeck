import 'package:flutter/material.dart';

import 'brand_assets.dart';

/// Exact semantic roles from tokens/serverdeck.tokens.json (palette 1.0).
/// A ThemeExtension preserves roles that have no Material ColorScheme slot.
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors._(this.roles);

  final Map<String, Color> roles;

  Color operator [](String role) => roles[role]!;

  static const dark = BrandColors._({
    'bg': Color(0xff0C121C),
    'surface': Color(0xff151E2B),
    'raised': Color(0xff1D2939),
    'hover': Color(0xff253246),
    'selected': Color(0xff173E43),
    'text': Color(0xffEAF0F7),
    'muted': Color(0xffA7B5C7),
    'border': Color(0xff35465E),
    'control': Color(0xff8192A8),
    'accent': Color(0xff64DFC5),
    'onAccent': Color(0xff0C121C),
    'accentHover': Color(0xff8CEBD7),
    'focus': Color(0xff7DCFFF),
    'disabled': Color(0xffA7B5C7),
    'available': Color(0xff72DBAC),
    'unavailable': Color(0xffFF9DA5),
    'unknown': Color(0xffBCC7D6),
    'warning': Color(0xffFFC47A),
    'error': Color(0xffFF8D98),
    'running': Color(0xff86C9FF),
    'success': Color(0xff72DBAC),
    'chart2': Color(0xffC5ABFF),
    'chart3': Color(0xffFFC47A),
  });

  static const light = BrandColors._({
    'bg': Color(0xffF3F6FA),
    'surface': Color(0xffFFFFFF),
    'raised': Color(0xffEAF0F6),
    'hover': Color(0xffE2EAF3),
    'selected': Color(0xffD9F1EC),
    'text': Color(0xff172337),
    'muted': Color(0xff526279),
    'border': Color(0xffCDD7E4),
    'control': Color(0xff718198),
    'accent': Color(0xff087565),
    'onAccent': Color(0xffFFFFFF),
    'accentHover': Color(0xff075E51),
    'focus': Color(0xff006AAB),
    'disabled': Color(0xff526279),
    'available': Color(0xff137346),
    'unavailable': Color(0xffB62D42),
    'unknown': Color(0xff586579),
    'warning': Color(0xff915000),
    'error': Color(0xffB6203C),
    'running': Color(0xff1765A8),
    'success': Color(0xff137346),
    'chart2': Color(0xff7650B4),
    'chart3': Color(0xff915000),
  });

  @override
  BrandColors copyWith({Map<String, Color>? roles}) =>
      roles == null ? this : BrandColors._(Map.unmodifiable(roles));

  @override
  BrandColors lerp(covariant BrandColors? other, double t) {
    if (other == null) return this;
    return BrandColors._(
      Map.unmodifiable({
        for (final role in roles.keys)
          role: Color.lerp(this[role], other[role], t)!,
      }),
    );
  }
}

/// UI/table/log/title/label styles retain the source's sizes and line heights.
abstract final class BrandTypography {
  static const body = TextStyle(
    fontFamily: BrandAssets.uiFont,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );
  static const table = TextStyle(
    fontFamily: BrandAssets.uiFont,
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w400,
  );
  static const log = TextStyle(
    fontFamily: BrandAssets.monoFont,
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w400,
  );
  static const title = TextStyle(
    fontFamily: BrandAssets.uiFont,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
  );
  static const label = TextStyle(
    fontFamily: BrandAssets.uiFont,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );
}

abstract final class BrandTheme {
  static final light = _create(Brightness.light, BrandColors.light);
  static final dark = _create(Brightness.dark, BrandColors.dark);

  static ThemeData _create(Brightness brightness, BrandColors colors) {
    final text = TextTheme(
      displayLarge: BrandTypography.title,
      displayMedium: BrandTypography.title,
      displaySmall: BrandTypography.title,
      headlineLarge: BrandTypography.title,
      headlineMedium: BrandTypography.title,
      headlineSmall: BrandTypography.title,
      titleLarge: BrandTypography.title,
      titleMedium: BrandTypography.body.copyWith(fontWeight: FontWeight.w600),
      titleSmall: BrandTypography.table.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: BrandTypography.body,
      bodyMedium: BrandTypography.body,
      bodySmall: BrandTypography.table,
      labelLarge: BrandTypography.label,
      labelMedium: BrandTypography.label,
      labelSmall: BrandTypography.label,
    ).apply(bodyColor: colors['text'], displayColor: colors['text']);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      extensions: [colors],
      fontFamily: BrandAssets.uiFont,
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: colors['bg'],
      canvasColor: colors['bg'],
      cardColor: colors['surface'],
      dividerColor: colors['border'],
      disabledColor: colors['disabled'],
      focusColor: colors['focus'],
      hoverColor: colors['hover'],
      highlightColor: colors['selected'],
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors['accent'],
        onPrimary: colors['onAccent'],
        primaryContainer: colors['selected'],
        onPrimaryContainer: colors['text'],
        secondary: colors['accent'],
        onSecondary: colors['onAccent'],
        secondaryContainer: colors['selected'],
        onSecondaryContainer: colors['text'],
        tertiary: colors['chart2'],
        onTertiary: colors['bg'],
        error: colors['error'],
        onError: colors['bg'],
        surface: colors['surface'],
        onSurface: colors['text'],
        surfaceDim: colors['bg'],
        surfaceBright: colors['raised'],
        surfaceContainerLowest: colors['bg'],
        surfaceContainerLow: colors['surface'],
        surfaceContainer: colors['surface'],
        surfaceContainerHigh: colors['raised'],
        surfaceContainerHighest: colors['hover'],
        onSurfaceVariant: colors['muted'],
        outline: colors['control'],
        outlineVariant: colors['border'],
        surfaceTint: Colors.transparent,
      ),
    );
  }
}
