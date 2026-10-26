import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureDefine = String.fromEnvironment('DESIGN_STOCK_CAPTURE_DIR');
const _captureTasks = {
  'focus': 'T080',
  'disabled': 'T081',
  'versions': 'T085',
  'scroll': 'T087',
};
const _expectedCaptureCounts = {
  'focus': 24,
  'disabled': 32,
  'versions': 64,
  'scroll': 64,
};
final _familyWriters = <String, _StockCaptureWriter>{};

/// Opt-in evidence from the existing, asserted production paint scenario.
///
/// Each test file owns one fresh family directory and its own records.jsonl.
/// There is no shared writer between the named family test isolates.
/// Creation records evidence only; review and the enclosing test exit are
/// separate acceptance gates.
Future<void> captureStockPaint(
  WidgetTester tester, {
  required GlobalKey boundary,
  required String family,
  required String componentCaseId,
  required String caseId,
  required List<String> originIds,
  required List<String> productionOwners,
  required List<String> components,
  required double width,
  double height = 800,
  required String theme,
  required double scale,
  required bool reducedMotion,
  required Map<String, Object?> state,
  required Map<String, Object?> counters,
  List<String> usageOriginIds = const [],
  List<String> limitations = const [],
}) async {
  final configured = _captureDefine.isNotEmpty
      ? _captureDefine
      : Platform.environment['DESIGN_STOCK_CAPTURE_DIR'] ?? '';
  if (configured.trim().isEmpty) return;
  final captureTask = _captureTasks[family];
  if (captureTask == null) {
    throw ArgumentError.value(
      family,
      'family',
      'Expected focus, disabled, versions or scroll',
    );
  }
  final versionTypography = family == 'versions';
  final keyboardScroll = family == 'scroll';
  final slug = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
  if (!slug.hasMatch(componentCaseId) || !slug.hasMatch(caseId)) {
    throw ArgumentError('Capture IDs must be nonempty lowercase slugs');
  }
  if (theme != 'light' && theme != 'dark') {
    throw ArgumentError.value(theme, 'theme', 'Expected light or dark');
  }
  if (!width.isFinite ||
      !height.isFinite ||
      !scale.isFinite ||
      width <= 0 ||
      height <= 0 ||
      scale <= 0) {
    throw ArgumentError('Frame and text scale must be finite and positive');
  }
  final command = Platform.environment['DESIGN_STOCK_CAPTURE_COMMAND'];
  if (command == null || command.trim().isEmpty) {
    throw StateError('Opt-in capture requires DESIGN_STOCK_CAPTURE_COMMAND');
  }

  final boundaryFinder = find.byKey(boundary);
  final imageElements = find
      .descendant(of: boundaryFinder, matching: find.byType(Image))
      .evaluate()
      .toList();
  final failures = <String>[];
  await tester.runAsync<void>(() async {
    for (final element in imageElements) {
      final widget = element.widget as Image;
      await precacheImage(
        widget.image,
        element,
        onError: (error, stack) => failures.add('$error'),
      );
    }
  });
  expect(failures, isEmpty, reason: 'Mounted image assets must decode');
  await tester.pumpAndSettle();
  final rawImages = find
      .descendant(of: boundaryFinder, matching: find.byType(RawImage))
      .evaluate()
      .map((element) => element.widget as RawImage)
      .toList();
  for (final image in rawImages) {
    expect(image.image, isNotNull, reason: 'Mounted RawImage must be ready');
  }
  final render = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
  expect(render.size, Size(width, height));
  expect(render.debugNeedsPaint, isFalse);
  expect(tester.view.devicePixelRatio, 1);

  await tester.runAsync<void>(() async {
    var writer = _familyWriters[family];
    if (writer == null) {
      writer = await _StockCaptureWriter.create(configured, family, command);
      _familyWriters[family] = writer;
    }
    if (writer.configured != configured || writer.command != command) {
      throw StateError(
        'Capture destination/command changed during this family',
      );
    }
    if (!writer.caseIds.add(caseId)) {
      throw StateError('Duplicate capture case ID: $caseId');
    }
    final pngName = '$caseId.png';
    final pngFile = File.fromUri(writer.output.uri.resolve(pngName));
    if (await pngFile.exists()) {
      throw StateError('Refusing to overwrite capture ${pngFile.path}');
    }
    final image = await render.toImage(pixelRatio: 1);
    try {
      expect(image.width, width.toInt());
      expect(image.height, height.toInt());
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('PNG encoding returned null');
      await pngFile.writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        flush: true,
      );
      final record = <String, Object?>{
        'caseId': caseId,
        'screenId': componentCaseId,
        'componentCaseId': componentCaseId,
        'originIds': originIds,
        'usageOriginIds': usageOriginIds,
        'sourceOwners': productionOwners,
        'components': components,
        'group': 'stock-$family',
        'captureStage': '003.2',
        'captureTask': captureTask,
        'taskIds': [
          captureTask,
          keyboardScroll
              ? 'T088'
              : versionTypography
              ? 'T086'
              : 'T082',
        ],
        'variant': keyboardScroll
            ? 'keyboard-focused-bounded-scroll'
            : versionTypography
            ? 'precise-machine-version'
            : 'stock-$family-paint',
        'state': keyboardScroll
            ? 'keyboard-focused-bounded-scroll'
            : versionTypography
            ? 'precise-machine-version'
            : family == 'focus'
            ? 'keyboard-focused'
            : 'pending-checkbox',
        'observedState': state,
        if (keyboardScroll) 'view': state['view'],
        'frame': {'width': width.toInt(), 'height': height.toInt()},
        'theme': theme,
        'scale': scale,
        'devicePixelRatio': 1,
        'reducedMotion': reducedMotion,
        'command': command,
        'commandSource': 'DESIGN_STOCK_CAPTURE_COMMAND shell environment',
        'callbackCounters': counters,
        'imageReadiness':
            'Every mounted Image provider decoded and every '
            'mounted RawImage has a non-null image after a settled frame.',
        'decodedImageCount': rawImages.length,
        'png': pngName,
        'result': versionTypography || keyboardScroll
            ? 'captured-after-render-assertions'
            : 'captured-after-paint-assertions',
        'scope': keyboardScroll
            ? 'production-component-keyboard-scroll'
            : versionTypography
            ? 'production-component-glyph-typography'
            : 'production-component-paint',
        'fixtureScope':
            'The already asserted production widget and existing '
            'test handlers; no separate capture UI or native service lifecycle.',
        'limitations': [
          'Component paint evidence does not accept a complete runtime origin, '
              'its enclosing owner lifecycle, or native effects/security.',
          if (keyboardScroll)
            'Only the named focused bounded scroll region and current view '
                'at the recorded frame/theme/scale is captured. '
                'Creation is not visual or native authority acceptance.'
          else if (versionTypography)
            'Only the named precise machine version and its actual rendered '
                'typography at the recorded frame/theme/scale is captured. '
                'Creation is not visual acceptance.'
          else
            'Only the named focused or pending checkbox state at the recorded '
                'frame/theme/scale is captured. Creation is not visual acceptance.',
          ...limitations,
        ],
      };
      await writer.records.writeAsString(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } finally {
      image.dispose();
    }
  });
}

class _StockCaptureWriter {
  _StockCaptureWriter(this.configured, this.command, this.output, this.records);

  final String configured;
  final String command;
  final Directory output;
  final File records;
  final caseIds = <String>{};

  static Future<_StockCaptureWriter> create(
    String configured,
    String family,
    String command,
  ) async {
    final requested = Directory(configured);
    if (!requested.isAbsolute) {
      throw ArgumentError('DESIGN_STOCK_CAPTURE_DIR must be absolute');
    }
    final workspace = Directory(await Directory.current.resolveSymbolicLinks());
    final intended = Directory.fromUri(
      workspace.uri.resolve('.local/design-003/003.2/'),
    );
    final normalized = Directory.fromUri(requested.uri.normalizePath());
    if (!_strictlyUnder(normalized.path, intended.path)) {
      throw ArgumentError('Stock capture run must be below ${intended.path}');
    }
    var ancestor = normalized;
    final missing = <String>[];
    while (!await ancestor.exists()) {
      missing.insert(
        0,
        ancestor.uri.pathSegments.where((part) => part.isNotEmpty).last,
      );
      if (ancestor.parent.path == ancestor.path) {
        throw StateError('Cannot resolve capture output ancestor');
      }
      ancestor = ancestor.parent;
    }
    var resolved = Directory(await ancestor.resolveSymbolicLinks());
    for (final segment in missing) {
      resolved = Directory.fromUri(
        resolved.uri.resolve('${Uri.encodeComponent(segment)}/'),
      );
    }
    if (!_strictlyUnder(resolved.path, intended.path)) {
      throw ArgumentError('Resolved stock capture path leaves intended base');
    }
    if (await resolved.exists()) {
      for (final entity in await resolved.list(followLinks: false).toList()) {
        final name = entity.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last;
        if (!_captureTasks.containsKey(name) || entity is! Directory) {
          throw StateError('Capture run contains unexpected prior evidence');
        }
      }
    }
    final output = Directory.fromUri(resolved.uri.resolve('$family/'));
    if (await FileSystemEntity.type(output.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Capture family must be fresh: ${output.path}');
    }
    await output.create(recursive: true);
    final records = File.fromUri(output.uri.resolve('records.jsonl'));
    await records.writeAsString('', flush: true);
    await File.fromUri(
      output.uri.resolve('family-manifest.json'),
    ).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'schema': 'serverdeck-stock-paint-capture-v1', 'family': family, 'expectedCaseCount': _expectedCaptureCounts[family], 'command': command, 'writerPid': pid, 'startedAtUtc': DateTime.now().toUtc().toIso8601String(), 'concurrency': 'Separate fresh family directories and records.jsonl; '
          'one writer per test file. No shared cross-isolate append.', 'completion': 'Validate all expected records, PNGs and enclosing test '
          'exit separately; this manifest is not a completion assertion.'})}\n',
      flush: true,
    );
    return _StockCaptureWriter(configured, command, output, records);
  }
}

bool _strictlyUnder(String candidate, String parent) {
  String key(String value) {
    final normalized = value
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  return key(candidate).startsWith('${key(parent)}/');
}
