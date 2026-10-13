import '../support/dormant_bootstrap.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/main.dart';
import 'package:serverdeck/theme/brand_assets.dart';
import 'package:serverdeck/theme/brand_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = jsonDecode(
    File('docs/brandbook/tokens/serverdeck.tokens.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('both palettes retain every exact semantic source role', () {
    final themes = source['themes'] as Map<String, dynamic>;
    for (final entry in {
      'light': BrandTheme.light,
      'dark': BrandTheme.dark,
    }.entries) {
      final expected = themes[entry.key] as Map<String, dynamic>;
      final palette = entry.value.extension<BrandColors>()!;
      expect(palette.roles.keys.toSet(), expected.keys.toSet());
      for (final role in expected.entries) {
        expect(
          palette[role.key].toARGB32(),
          0xff000000 |
              int.parse((role.value as String).substring(1), radix: 16),
          reason: '${entry.key}/${role.key}',
        );
      }
      expect(entry.value.scaffoldBackgroundColor, palette['bg']);
      expect(entry.value.colorScheme.primary, palette['accent']);
      expect(entry.value.colorScheme.onPrimary, palette['onAccent']);
      expect(entry.value.colorScheme.surface, palette['surface']);
      expect(entry.value.colorScheme.onSurface, palette['text']);
      expect(entry.value.colorScheme.onSurfaceVariant, palette['muted']);
      expect(entry.value.colorScheme.outline, palette['control']);
      expect(entry.value.colorScheme.outlineVariant, palette['border']);
      expect(entry.value.colorScheme.error, palette['error']);
      expect(entry.value.colorScheme.surfaceTint, Colors.transparent);
    }
  });

  test('typography uses source families, sizes and line heights', () {
    final shared = source['shared'] as Map<String, dynamic>;
    for (final entry in {
      'body': BrandTypography.body,
      'table': BrandTypography.table,
      'log': BrandTypography.log,
      'title': BrandTypography.title,
      'label': BrandTypography.label,
    }.entries) {
      final style = entry.value;
      expect(
        style.fontFamily,
        shared[entry.key == 'log' ? 'font.mono' : 'font.ui'],
      );
      expect(style.fontSize, shared['font.${entry.key}']);
      expect(
        style.height! * style.fontSize!,
        closeTo((shared['font.${entry.key}.line'] as num).toDouble(), 0.000001),
      );
    }
    for (final theme in [BrandTheme.light, BrandTheme.dark]) {
      expect(theme.textTheme.bodyMedium!.fontFamily, shared['font.ui']);
      expect(theme.textTheme.bodyMedium!.fontSize, shared['font.body']);
      expect(theme.textTheme.titleLarge!.fontWeight, FontWeight.w600);
      expect(
        theme.textTheme.bodyMedium!.color,
        theme.extension<BrandColors>()!['text'],
      );
    }
  });

  test(
    'bundle contains original fonts, license and decodable current logos',
    () async {
      final fonts = <String, List<String>>{
        BrandAssets.uiFont: [BrandAssets.regularFont, BrandAssets.semiboldFont],
        BrandAssets.monoFont: [BrandAssets.monoRegularFont],
      };
      for (final family in fonts.entries) {
        final loader = FontLoader(family.key);
        for (final path in family.value) {
          final bytes = await rootBundle.load(path);
          expect(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
            File(path.replaceFirst('assets/brand/', 'docs/brandbook/'))
                .readAsBytesSync(),
          );
          loader.addFont(Future.value(bytes));
        }
        await loader.load();
      }
      final manifest = jsonDecode(
        await rootBundle.loadString('FontManifest.json'),
      ) as List<dynamic>;
      for (final family in fonts.entries) {
        final entry = manifest.cast<Map<String, dynamic>>().singleWhere(
          (entry) => entry['family'] == family.key,
        );
        final faces = (entry['fonts'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(faces.map((face) => face['asset']).toList(), family.value);
        expect(
          faces.map((face) => face['weight']).toList(),
          family.key == BrandAssets.uiFont ? [400, 600] : [400],
        );
      }
      expect(
        await rootBundle.loadString(BrandAssets.fontLicense),
        File('docs/brandbook/fonts/OFL.txt').readAsStringSync(),
      );
      for (final path in [
        BrandAssets.darkLogo,
        BrandAssets.lightLogo,
        BrandAssets.darkMark,
        BrandAssets.lightMark,
      ]) {
        final data = await rootBundle.load(path);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        expect(
          bytes,
          File(path.replaceFirst('assets/brand/', 'docs/brandbook/'))
              .readAsBytesSync(),
        );
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(
          frame.image.width,
          greaterThanOrEqualTo(path.contains('/logo-') ? 140 : 24),
        );
        expect(frame.image.height, greaterThan(0));
        frame.image.dispose();
        codec.dispose();
      }
      expect(BrandAssets.logo(Brightness.light), BrandAssets.lightLogo);
      expect(BrandAssets.logo(Brightness.dark), BrandAssets.darkLogo);
      expect(BrandAssets.mark(Brightness.light), BrandAssets.lightMark);
      expect(BrandAssets.mark(Brightness.dark), BrandAssets.darkMark);
      expect(
        File('windows/runner/resources/app_icon.ico').readAsBytesSync(),
        File('assets/brand/logos/serverdeck-dark.ico').readAsBytesSync(),
      );
    },
  );

  testWidgets('system brightness selects exact brand backgrounds', (
    tester,
  ) async {
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpWidget(FoundationApp(bootstrap: dormantBootstrap()));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold));
    expect(Theme.of(context).scaffoldBackgroundColor, const Color(0xffF3F6FA));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await tester.pumpAndSettle();
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).scaffoldBackgroundColor, const Color(0xff0C121C));
    expect(find.text('Локальная служба недоступна'), findsOneWidget);
  });
}
