import 'package:flutter/services.dart';

Future<void>? _fontsLoaded;

Future<void> loadDesignFonts() => _fontsLoaded ??= _loadDesignFonts();

Future<void> _loadDesignFonts() async {
  final sans = FontLoader('Noto Sans')
    ..addFont(rootBundle.load('assets/brand/fonts/NotoSans-Regular.ttf'));
  final semibold = FontLoader('Noto Sans SemiBold')
    ..addFont(rootBundle.load('assets/brand/fonts/NotoSans-SemiBold.ttf'));
  final mono = FontLoader('Noto Sans Mono')
    ..addFont(rootBundle.load('assets/brand/fonts/NotoSansMono-Regular.ttf'));
  final unicode = FontLoader('Noto Sans SC')
    ..addFont(rootBundle.load('assets/brand/fonts/NotoSansSC-Variable.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await Future.wait([
    sans.load(),
    semibold.load(),
    mono.load(),
    unicode.load(),
    icons.load(),
  ]);
}
