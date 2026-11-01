import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;

import 'brand_assets.dart';
import 'brand_tokens.dart';

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
  static const button = TextStyle(
    fontFamily: BrandAssets.uiFont,
    fontFamilyFallback: BrandAssets.fontFamilyFallback,
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w600,
  );
  static const tableHeader = button;
  static const body = TextStyle(
    fontFamily: BrandAssets.uiFont,
    fontFamilyFallback: BrandAssets.fontFamilyFallback,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );
  static const table = TextStyle(
    fontFamily: BrandAssets.uiFont,
    fontFamilyFallback: BrandAssets.fontFamilyFallback,
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w400,
  );
  static const log = TextStyle(
    fontFamily: BrandAssets.monoFont,
    fontFamilyFallback: BrandAssets.fontFamilyFallback,
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w400,
  );
  static const title = TextStyle(
    fontFamily: BrandAssets.uiFont,
    fontFamilyFallback: BrandAssets.fontFamilyFallback,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
  );
  static const label = TextStyle(
    fontFamily: BrandAssets.uiFont,
    fontFamilyFallback: BrandAssets.fontFamilyFallback,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );
  static const caption = label;
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
      fontFamilyFallback: BrandAssets.fontFamilyFallback,
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: colors['bg'],
      canvasColor: colors['bg'],
      cardColor: colors['surface'],
      dividerColor: colors['border'],
      disabledColor: colors['disabled'],
      // Stock InkWell paints this across its whole row. Keep that fill
      // readable; DeckFocusLabel supplies the separate focus-token outline.
      focusColor: colors['selected'],
      hoverColor: colors['hover'],
      highlightColor: colors['selected'],
      iconTheme: IconThemeData(
        size: BrandGeometry.iconSize,
        color: colors['text'],
      ),
      checkboxTheme: CheckboxThemeData(
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.selected) &&
              !states.contains(WidgetState.disabled)) {
            return BorderSide.none;
          }
          return BorderSide(
            color:
                colors[states.contains(WidgetState.error)
                    ? 'error'
                    : 'control'],
            width: 2,
          );
        }),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (!states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          if (states.contains(WidgetState.disabled)) return colors['control'];
          return colors[states.contains(WidgetState.error)
              ? 'error'
              : 'accent'];
        }),
        checkColor: WidgetStateProperty.resolveWith((states) {
          return colors[states.contains(WidgetState.disabled) ||
                  states.contains(WidgetState.error)
              ? 'bg'
              : 'onAccent'];
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _button(colors, _ButtonKind.filled),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _button(colors, _ButtonKind.filled),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _button(colors, _ButtonKind.outlined),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _button(colors, _ButtonKind.text),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: _button(
          colors,
          _ButtonKind.text,
        ).copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.all(12))),
      ),
      cardTheme: CardThemeData(
        color: colors['surface'],
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandGeometry.radiusCard),
          side: BorderSide(color: colors['border']),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors['surface'],
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandGeometry.radiusDialog),
          side: BorderSide(color: colors['border']),
        ),
        titleTextStyle: BrandTypography.title.copyWith(color: colors['text']),
        contentTextStyle: BrandTypography.body.copyWith(color: colors['text']),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colors['surface'],
        labelStyle: BrandTypography.body.copyWith(color: colors['muted']),
        hintStyle: BrandTypography.body.copyWith(color: colors['muted']),
        errorStyle: BrandTypography.caption.copyWith(color: colors['error']),
        contentPadding: const EdgeInsets.all(BrandSpacing.space12),
        constraints: const BoxConstraints(minHeight: BrandGeometry.minTarget),
        border: _inputBorder(colors['control']),
        enabledBorder: _inputBorder(colors['control']),
        disabledBorder: _inputBorder(colors['control']),
        focusedBorder: _FocusInputBorder(
          control: colors['control'],
          focus: colors['focus'],
        ),
        errorBorder: _inputBorder(colors['error']),
        focusedErrorBorder: _FocusInputBorder(
          control: colors['error'],
          focus: colors['focus'],
        ),
      ),
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

  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(BrandGeometry.radiusControl),
    borderSide: BorderSide(color: color),
  );

  static ButtonStyle _button(BrandColors colors, _ButtonKind kind) =>
      ButtonStyle(
        textStyle: const WidgetStatePropertyAll(BrandTypography.button),
        minimumSize: const WidgetStatePropertyAll(
          Size(BrandGeometry.minTarget, BrandGeometry.minTarget),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: BrandSpacing.space16,
            vertical: BrandSpacing.space12,
          ),
        ),
        iconSize: const WidgetStatePropertyAll(BrandGeometry.iconSize),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        elevation: const WidgetStatePropertyAll(0),
        animationDuration: const Duration(milliseconds: 120),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              BrandGeometry.radiusControl +
                  BrandGeometry.focusGap +
                  BrandGeometry.focusWidth,
            ),
          ),
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return colors['disabled'];
          if (states.contains(WidgetState.error)) return colors['text'];
          if (states.contains(WidgetState.selected)) return colors['text'];
          return kind == _ButtonKind.filled
              ? colors['onAccent']
              : colors['text'];
        }),
        backgroundBuilder: (context, states, child) => CustomPaint(
          painter: _ButtonPainter(colors, kind, states),
          child: child,
        ),
      );
}

enum _ButtonKind { filled, outlined, text }

/// Reserves four pixels inside the hit area. The transparent gap exposes the
/// actual adjacent surface, including when a button is placed on a card.
class _ButtonPainter extends CustomPainter {
  _ButtonPainter(this.colors, this.kind, Set<WidgetState> states)
    : states = Set.of(states);
  final BrandColors colors;
  final _ButtonKind kind;
  final Set<WidgetState> states;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = BrandGeometry.focusWidth + BrandGeometry.focusGap;
    final rect = (Offset.zero & size).deflate(inset);
    final radius = Radius.circular(BrandGeometry.radiusControl);
    final control = RRect.fromRectAndRadius(rect, radius);
    final disabled = states.contains(WidgetState.disabled);
    final selected = states.contains(WidgetState.selected);
    final error = states.contains(WidgetState.error);
    final hovered =
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.pressed);
    final Color fill;
    if (selected) {
      fill = colors['selected'];
    } else if (disabled || error) {
      fill = colors['raised'];
    } else if (kind == _ButtonKind.filled) {
      fill = colors[hovered ? 'accentHover' : 'accent'];
    } else {
      fill = hovered ? colors['hover'] : Colors.transparent;
    }
    canvas.drawRRect(control, Paint()..color = fill);
    if (kind == _ButtonKind.outlined || disabled || error || selected) {
      final paint = Paint()
        ..color = colors[error ? 'error' : 'control']
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      if (disabled) {
        final path = Path()..addRRect(control.deflate(0.5));
        for (final metric in path.computeMetrics()) {
          for (double offset = 0; offset < metric.length; offset += 7) {
            canvas.drawPath(metric.extractPath(offset, offset + 4), paint);
          }
        }
      } else {
        canvas.drawRRect(control.deflate(0.5), paint);
      }
    }
    if (states.contains(WidgetState.focused)) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(BrandGeometry.focusWidth / 2),
          const Radius.circular(
            BrandGeometry.radiusControl + inset - BrandGeometry.focusWidth / 2,
          ),
        ),
        Paint()
          ..color = colors['focus']
          ..style = PaintingStyle.stroke
          ..strokeWidth = BrandGeometry.focusWidth,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ButtonPainter oldDelegate) =>
      colors != oldDelegate.colors ||
      kind != oldDelegate.kind ||
      !setEquals(states, oldDelegate.states);
}

/// A second, inset outline keeps focus visible alongside an error outline.
/// Both strokes fit inside the InputDecorator's reserved border dimensions.
class _FocusInputBorder extends OutlineInputBorder {
  _FocusInputBorder({required this.control, required this.focus})
    : super(
        borderRadius: BorderRadius.circular(BrandGeometry.radiusControl),
        borderSide: BorderSide(color: control, width: 1),
        gapPadding: 4,
      );
  final Color control;
  final Color focus;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(5);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(BrandGeometry.radiusControl - 3),
      borderSide: BorderSide(color: focus, width: BrandGeometry.focusWidth),
      gapPadding: 4,
    ).paint(
      canvas,
      rect.deflate(3),
      gapStart: gapStart == null ? null : gapStart - 3,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
  }

  @override
  _FocusInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) => _FocusInputBorder(control: borderSide?.color ?? control, focus: focus);
}
