import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/theme/motion.dart';

Widget stockPaintHost(
  Widget child, {
  required GlobalKey boundaryKey,
  required ThemeData theme,
  double scale = 2,
  bool reduced = true,
}) => RepaintBoundary(
  key: boundaryKey,
  child: MaterialApp(
    theme: Motion.theme(theme, reduced),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduced,
      ),
      child: child!,
    ),
    home: Scaffold(body: child),
  ),
);

void stockPaintFrame(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previous = FocusManager.instance.highlightStrategy;
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => FocusManager.instance.highlightStrategy = previous);
}

Future<void> stockShow(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .4);
  await tester.pumpAndSettle();
}

bool stockContainsFocus(WidgetTester tester, Finder finder) {
  final target = tester.element(finder);
  final current = FocusManager.instance.primaryFocus?.context;
  if (current == null) return false;
  if (identical(current, target)) return true;
  var contains = false;
  (current as Element).visitAncestorElements((element) {
    contains = identical(element, target);
    return !contains;
  });
  return contains;
}

/// Traverse real focus order; do not inject a node into the production control.
Future<void> stockTabTo(WidgetTester tester, Finder target) async {
  await stockShow(tester, target);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  for (var i = 0; i < 80; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    if (stockContainsFocus(tester, target)) return;
  }
  fail('Real keyboard traversal did not reach $target');
}

double stockContrast(Color foreground, Color background) {
  final f = foreground.computeLuminance();
  final b = background.computeLuminance();
  return ((f > b ? f : b) + .05) / ((f > b ? b : f) + .05);
}

class StockPaintRaster {
  StockPaintRaster(this.width, this.height, this.bytes);
  final int width, height;
  final ByteData bytes;

  static Future<StockPaintRaster> capture(
    WidgetTester tester,
    GlobalKey key,
  ) async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = (await tester.runAsync(
      () => boundary.toImage(pixelRatio: 1),
    ))!;
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    final result = StockPaintRaster(image.width, image.height, bytes);
    image.dispose();
    return result;
  }

  Color pixel(Offset point) {
    final x = point.dx.floor(), y = point.dy.floor();
    assert(x >= 0 && x < width && y >= 0 && y < height);
    final offset = (y * width + x) * 4;
    return Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }

  Map<Color, int> histogram(Rect rect) {
    final counts = <Color, int>{};
    final clipped = rect.intersect(
      Rect.fromLTWH(0, 0, width * 1.0, height * 1.0),
    );
    for (var y = clipped.top.ceil(); y < clipped.bottom.floor(); y++) {
      for (var x = clipped.left.ceil(); x < clipped.right.floor(); x++) {
        counts.update(
          pixel(Offset(x * 1.0, y * 1.0)),
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
    }
    return counts;
  }

  Color dominant(Rect rect, {Color? excluding}) {
    final values =
        histogram(rect).entries
            .where((entry) => entry.key != excluding)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    expect(values, isNotEmpty);
    return values.first.key;
  }
}

Future<Map<String, Object>> stockExpectReadable(
  WidgetTester tester,
  GlobalKey boundary,
  Finder text,
) async {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.didExceedMaxLines, isFalse);
  final style = (paragraph.text as TextSpan).style!;
  final raster = await StockPaintRaster.capture(tester, boundary);
  final rect = tester.getRect(text);
  final background = raster.dominant(rect);
  final foreground = Color.alphaBlend(style.color!, background);
  final ratio = stockContrast(foreground, background);
  expect(
    raster.histogram(rect)[foreground] ?? 0,
    greaterThan(0),
    reason: 'Resolved foreground must actually paint glyph pixels',
  );
  expect(
    ratio,
    greaterThanOrEqualTo(4.5),
    reason:
        'Focused text ${paragraph.text.toPlainText()} paints '
        '$foreground against actual $background: $ratio:1',
  );
  return {
    'foregroundArgb': foreground.toARGB32(),
    'backgroundArgb': background.toARGB32(),
    'textContrast': ratio,
  };
}
