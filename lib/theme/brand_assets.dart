import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// Bundled brandbook 1.1 resources and separately licensed Unicode fallback.
abstract final class BrandAssets {
  static const logoMinWidth = BrandGeometry.logoMinWidth;
  static const markMinSize = BrandGeometry.markMinSize;
  static const uiFont = 'Noto Sans';
  static const monoFont = 'Noto Sans Mono';
  static const regularFont = 'assets/brand/fonts/NotoSans-Regular.ttf';
  static const semiboldFont = 'assets/brand/fonts/NotoSans-SemiBold.ttf';
  static const monoRegularFont = 'assets/brand/fonts/NotoSansMono-Regular.ttf';
  static const fontLicense = 'assets/brand/fonts/OFL.txt';
  // Keep the brandbook faces first; this offline face supplies missing glyphs.
  static const unicodeFont = 'Noto Sans SC';
  static const fontFamilyFallback = [unicodeFont];
  static const unicodeVariableFont =
      'assets/brand/fonts/NotoSansSC-Variable.ttf';
  static const unicodeFontLicense = 'assets/brand/fonts/OFL-NotoSansSC.txt';
  static const unicodeFontSource = 'assets/brand/fonts/NotoSansSC-SOURCE.json';
  static const darkLogo = 'assets/brand/logos/logo-dark.png';
  static const lightLogo = 'assets/brand/logos/logo-light.png';
  static const darkMark = 'assets/brand/logos/mark-dark.png';
  static const lightMark = 'assets/brand/logos/mark-light.png';

  static String logo(Brightness brightness) =>
      brightness == Brightness.dark ? darkLogo : lightLogo;

  static String mark(Brightness brightness) =>
      brightness == Brightness.dark ? darkMark : lightMark;
}
