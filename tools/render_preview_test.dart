// Renders fixture previews for visual review, not a native Windows screenshot.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/ui/app.dart';

void main() {
  testWidgets('Render synthetic fixture previews with Windows fonts', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final font in [
        ('Segoe UI', 'segoeui.ttf'),
        ('Consolas', 'consola.ttf'),
      ]) {
        final loader = FontLoader(font.$1);
        loader.addFont(
          File('C:/Windows/Fonts/${font.$2}')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
        await loader.load();
      }
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File(
          'H:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await icons.load();
    });
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const ServerDeckApp()),
    );
    await tester.pumpAndSettle();
    for (final page in ['servers', 'journal', 'jobs']) {
      await tester.tap(find.byKey(ValueKey('nav-$page')));
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('work/previews').create(recursive: true);
        await File('work/previews/$page.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }
  });
}
