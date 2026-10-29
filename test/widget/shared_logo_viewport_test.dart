import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/design_stock_paint_support.dart' show StockPaintRaster;

void main() {
  for (final theme in ['dark', 'light']) {
    for (final frame in [(145.0, 44.0, 104.0), (160.0, 48.0, 115.0)]) {
      testWidgets('approved SVG viewport and clear space $theme ${frame.$1}', (
        tester,
      ) async {
        final boundary = GlobalKey();
        final asset = 'assets/brand/logos/logo-$theme.svg';
        final background = theme == 'dark'
            ? const Color(0xff151e2b)
            : Colors.white;
        final source = File('docs/brandbook/logos/logo-$theme.svg')
            .readAsBytesSync();
        final bundled = await rootBundle.load(asset);
        expect(
          bundled.buffer.asUint8List(
            bundled.offsetInBytes,
            bundled.lengthInBytes,
          ),
          orderedEquals(source),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              home: Scaffold(
                backgroundColor: background,
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: frame.$1,
                    height: frame.$2,
                    child: SvgPicture.asset(asset),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
          await svg.bytesLoader.loadBytes(
            tester.element(find.byType(SvgPicture)),
          );
          await vg.waitForPendingDecodes();
        });
        await tester.pump();
        final picture = await tester.runAsync(
          () => vg.loadPicture(SvgAssetLoader(asset), null),
        );
        final raster = await StockPaintRaster.capture(tester, boundary);
        Rect? ink;
        for (var y = 0; y < frame.$2; y++) {
          for (var x = 0; x < frame.$1; x++) {
            final p = raster.pixel(Offset(x.toDouble(), y.toDouble()));
            if (p != background) {
              final point = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1);
              ink = ink?.expandToInclude(point) ?? point;
            }
          }
        }
        debugPrint(
          'SVG source viewport=${picture!.size}; widget=${tester.getRect(find.byType(SvgPicture))}; ink=$ink',
        );
        picture.picture.dispose();
        expect(picture.size, const Size(520, 112));
        expect(
          tester.getSize(find.byType(SvgPicture)),
          Size(frame.$1, frame.$2),
        );
        expect(ink!.width, closeTo(frame.$3, 1));
      });
    }
  }
}
