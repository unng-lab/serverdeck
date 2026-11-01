import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/theme/brand_assets.dart';
import 'package:serverdeck/theme/brand_theme.dart';

import '../../../tool/component_catalog/examples.dart';
import '../../../tool/component_catalog/names.dart';
import '../../support/component_cases.dart';
import '../../support/component_state_driver.dart';

const captureDirectory = String.fromEnvironment('COMPONENT_CAPTURE_DIR');

void main() {
  testWidgets(
    'opt-in production component visual matrix',
    (tester) async {
      final root = Directory(
        Directory(captureDirectory).absolute.uri.normalizePath().toFilePath(),
      );
      final allowed = Directory('.local/design-003/003.4').absolute.uri
          .normalizePath()
          .toFilePath();
      expect(
        root.path.startsWith(allowed) && root.path != allowed,
        isTrue,
        reason: 'Captures must stay in a new stage 003.4 directory',
      );
      expect(
        root.existsSync() && root.listSync().isNotEmpty,
        isFalse,
        reason: 'Never overwrite previous evidence',
      );
      root.createSync(recursive: true);
      final uiFont = FontLoader(BrandAssets.uiFont)
        ..addFont(rootBundle.load(BrandAssets.regularFont))
        ..addFont(rootBundle.load(BrandAssets.semiboldFont));
      final mono = FontLoader(BrandAssets.monoFont)
        ..addFont(rootBundle.load(BrandAssets.monoRegularFont));
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await uiFont.load();
      await mono.load();
      await icons.load();
      final records = <Map<String, Object?>>[];
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final dark in [true, false]) {
        for (final frame in componentFrames) {
          tester.view.physicalSize = frame;
          for (final scale in [1.0, 2.0]) {
            for (final id in componentNames.keys) {
              for (final state in componentStates[id]!) {
                final boundary = GlobalKey();
                await tester.pumpWidget(
                  MaterialApp(
                    theme: dark ? BrandTheme.dark : BrandTheme.light,
                    home: MediaQuery(
                      data: MediaQueryData.fromView(tester.view).copyWith(
                        textScaler: TextScaler.linear(scale),
                        disableAnimations: true,
                      ),
                      child: Scaffold(
                        body: SingleChildScrollView(
                          padding: id == 'C17'
                              ? EdgeInsets.zero
                              : const EdgeInsets.all(16),
                          child: RepaintBoundary(
                            key: boundary,
                            child: Material(
                              color: (dark
                                  ? BrandColors.dark
                                  : BrandColors.light)['bg'],
                              child: Padding(
                                padding: id == 'C17'
                                    ? EdgeInsets.zero
                                    : const EdgeInsets.all(16),
                                child: ComponentExample(
                                  key: ValueKey('$id-$state'),
                                  id: id,
                                  state: state,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                await tester.pump();
                await tester.pump(const Duration(milliseconds: 200));
                final releaseInteraction = await driveComponentState(
                  tester,
                  state,
                );
                // Decode bundled logo before recording the C01 frame.
                if (id == 'C01') {
                  await tester.runAsync(
                    () => precacheImage(
                      AssetImage(
                        BrandAssets.logo(
                          dark ? Brightness.dark : Brightness.light,
                        ),
                      ),
                      boundary.currentContext!,
                    ),
                  );
                  await tester.pump();
                }
                expect(
                  tester.takeException(),
                  null,
                  reason: '$id/$state $frame scale $scale',
                );
                final render =
                    boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final bytes = await tester.runAsync(() async {
                  final image = await render.toImage(pixelRatio: 1);
                  final data = (await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  ))!;
                  image.dispose();
                  return data;
                });
                expect(bytes, isNotNull, reason: '$id/$state image encoding');
                final filename =
                    '$id-$state-${dark ? 'dark' : 'light'}-${frame.width.round()}-${(scale * 100).round()}.png';
                await tester.runAsync(
                  () =>
                      File('${root.path}/$filename')
                          .writeAsBytes(bytes!.buffer.asUint8List()),
                );
                records.add({
                  'interaction': switch (state) {
                    'focus' => 'keyboard-tab',
                    'hover' => 'pointer-hover',
                    'pressed' => 'pointer-down-cancel',
                    _ => 'fixture',
                  },
                  'id': id,
                  'state': state,
                  'theme': dark ? 'dark' : 'light',
                  'width': frame.width,
                  'height': frame.height,
                  'scale': scale,
                  'file': filename,
                });
                await releaseInteraction();
              }
            }
          }
        }
      }
      await tester.runAsync(
        () => File('${root.path}/manifest.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'scope': 'Production Flutter components; synthetic owners; reduced motion; no native authority or server effects',
            'captures': records,
          }),
        ),
      );
    },
    skip: captureDirectory.isEmpty,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
