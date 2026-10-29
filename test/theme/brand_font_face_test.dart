import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/theme/brand_assets.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_page.dart';

import '../support/design_fonts.dart';

const _sample = 'Запуск рабочего пространства';

double _advance(TextStyle style, double scale) {
  final painter = TextPainter(
    text: TextSpan(text: _sample, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

Future<List<int>> _raster(
  TextStyle style,
  double scale, {
  String text = _sample,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: style.copyWith(color: Colors.white),
    ),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
  )..layout();
  painter.paint(canvas, Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1100, 100);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final pixels = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  painter.dispose();
  image.dispose();
  picture.dispose();
  return pixels;
}

void main() {
  setUpAll(() async {
    await loadDesignFonts();
    await (FontLoader(
      'Reference Noto Regular',
    )..addFont(rootBundle.load(BrandAssets.regularFont))).load();
    await (FontLoader(
      'Reference Noto Semibold',
    )..addFont(rootBundle.load(BrandAssets.semiboldFont))).load();
  });

  for (final width in [1100.0, 390.0]) {
    for (final role in [BrandTypography.body, BrandTypography.log]) {
      testWidgets(
        'explicit regular CJK in first table cell stays regular $width ${role.fontFamily}',
        (tester) async {
          await (FontLoader(
            'Reference Noto CJK',
          )..addFont(rootBundle.load(BrandAssets.unicodeVariableFont))).load();
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: BrandTheme.dark,
              home: Scaffold(
                body: AutomationRecordTable(
                  columns: const ['Поле'],
                  rows: [
                    [Text('漢', style: role)],
                  ],
                ),
              ),
            ),
          );
          final span =
              tester.renderObject<RenderParagraph>(find.text('漢')).text
                  as TextSpan;
          final actual = span.style!;
          expect(actual.fontFamily, role.fontFamily);
          expect(actual.fontWeight, FontWeight.w400);
          final reference = actual.copyWith(
            fontFamily: 'Reference Noto CJK',
            fontVariations: const [ui.FontVariation('wght', 400)],
          );
          await tester.runAsync(() async {
            expect(
              await _raster(actual, 1, text: '漢'),
              orderedEquals(await _raster(reference, 1, text: '漢')),
            );
          });
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('semibold outlines have no extra synthetic bold at $scale', (
      tester,
    ) async {
      await tester.runAsync(() async {
        for (final style in [
          BrandTypography.title,
          BrandTypography.button,
          BrandTypography.tableHeader,
        ]) {
          final reference = style.copyWith(
            fontFamily: 'Reference Noto Semibold',
            fontWeight: FontWeight.w400,
            fontVariations: const [],
          );
          expect(
            await _raster(style, scale),
            orderedEquals(await _raster(reference, scale)),
          );
        }
      });
    });
    testWidgets('brand roles select original faces at scale $scale', (
      tester,
    ) async {
      for (final style in [
        BrandTypography.body,
        BrandTypography.table,
        BrandTypography.caption,
        BrandTypography.title,
        BrandTypography.button,
        BrandTypography.tableHeader,
      ]) {
        final semibold = style.fontFamily == BrandAssets.semiboldFamily;
        final reference = semibold
            ? 'Reference Noto Semibold'
            : 'Reference Noto Regular';
        expect(
          _advance(style, scale),
          closeTo(_advance(style.copyWith(fontFamily: reference), scale), .01),
          reason: '${style.fontFamily}/${style.fontSize}/${style.fontWeight}',
        );
      }
      expect(
        _advance(BrandTypography.title, scale),
        greaterThan(
          _advance(
                BrandTypography.title.copyWith(
                  fontFamily: 'Reference Noto Regular',
                ),
                scale,
              ) +
              10 * scale,
        ),
      );
      expect(BrandTypography.log.fontFamily, BrandAssets.monoFont);
    });
    for (final brightness in Brightness.values) {
      testWidgets(
        'production header and button select SemiBold $brightness $scale',
        (tester) async {
          tester.view.physicalSize = const Size(1100, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: brightness == Brightness.dark
                  ? BrandTheme.dark
                  : BrandTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: DeckPage(
                    title: _sample,
                    eyebrow: 'Контекст',
                    actions: [
                      FilledButton(
                        onPressed: () {},
                        child: const Text('Сохранить'),
                      ),
                    ],
                    child: const SizedBox(),
                  ),
                ),
              ),
            ),
          );
          for (final label in [_sample, 'КОНТЕКСТ', 'Сохранить']) {
            final element = tester.element(find.text(label));
            final text = tester.widget<Text>(find.text(label));
            final style = DefaultTextStyle.of(element).style.merge(text.style);
            expect(style.fontFamily, BrandAssets.semiboldFamily);
            expect(style.fontWeight, BrandTypography.semiboldWeight);
            expect(
              _advance(style, scale),
              closeTo(
                _advance(
                  style.copyWith(fontFamily: 'Reference Noto Semibold'),
                  scale,
                ),
                .01,
              ),
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
