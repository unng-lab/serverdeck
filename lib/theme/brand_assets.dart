import 'package:flutter/material.dart';

/// Bundled resources from the preserved brandbook 1.1 kit.
abstract final class BrandAssets {
  static const uiFont = 'Noto Sans';
  static const monoFont = 'Noto Sans Mono';
  static const regularFont = 'assets/brand/fonts/NotoSans-Regular.ttf';
  static const semiboldFont = 'assets/brand/fonts/NotoSans-SemiBold.ttf';
  static const monoRegularFont = 'assets/brand/fonts/NotoSansMono-Regular.ttf';
  static const fontLicense = 'assets/brand/fonts/OFL.txt';
  static const darkLogo = 'assets/brand/logos/logo-dark.png';
  static const lightLogo = 'assets/brand/logos/logo-light.png';
  static const darkMark = 'assets/brand/logos/mark-dark.png';
  static const lightMark = 'assets/brand/logos/mark-light.png';

  static String logo(Brightness brightness) =>
      brightness == Brightness.dark ? darkLogo : lightLogo;

  static String mark(Brightness brightness) =>
      brightness == Brightness.dark ? darkMark : lightMark;
}
