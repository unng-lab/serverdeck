import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_state_matrix.dart';

/// Wrap the actual test app, including its Navigator/Overlay, with this key.
const designStateCaptureBoundaryKey = ValueKey('design-state-capture-root');
const _directory = String.fromEnvironment('DESIGN_STATE_CAPTURE_DIR');
const _families = {'foundation', 'server', 'automation', 'privacy'};
final _writers = <String, _Writer>{};

/// Optional evidence from the already asserted production state journey.
/// Ordinary tests write nothing. A capture records only this named checkpoint;
/// its enclosing test exit and independent visual review remain separate gates.
Future<void> captureDesignState(
  WidgetTester tester, {
  required String family,
  required List<String> caseIds,
  required String phase,
  required String theme,
  required double scale,
  required Map<String, Object?> counters,
  required List<String> assertions,
  required String scope,
  List<String> limitations = const [],
}) async {
  final configured = _directory.isNotEmpty
      ? _directory
      : Platform.environment['DESIGN_STATE_CAPTURE_DIR'] ?? '';
  if (configured.isEmpty) return;
  if (!_families.contains(family) ||
      !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(phase)) {
    throw ArgumentError(
      'Expected a known state family and lowercase phase slug',
    );
  }
  if (caseIds.isEmpty || caseIds.toSet().length != caseIds.length) {
    throw ArgumentError('Capture requires explicit unique planned case IDs');
  }
  for (final id in caseIds) {
    if (!designStateCasesById.containsKey(id)) {
      throw ArgumentError.value(id, 'caseIds', 'Unknown planned case');
    }
  }
  if (!{'light', 'dark'}.contains(theme) ||
      !scale.isFinite ||
      scale <= 0 ||
      scope.isEmpty ||
      assertions.isEmpty) {
    throw ArgumentError(
      'Capture requires theme, positive scale and assertions',
    );
  }
  final command = Platform.environment['DESIGN_STATE_CAPTURE_COMMAND'];
  if (command == null || command.trim().isEmpty) {
    throw StateError(
      'Opt-in state capture requires DESIGN_STATE_CAPTURE_COMMAND',
    );
  }
  final boundary = find.byKey(designStateCaptureBoundaryKey);
  expect(boundary, findsOneWidget);
  final scaffoldContext = tester.element(find.byType(Scaffold).first);
  expect(Theme.of(scaffoldContext).brightness.name, theme);
  final media = MediaQuery.of(scaffoldContext);
  expect(media.textScaler.scale(10) / 10, closeTo(scale, 0.00001));
  expect(media.disableAnimations, isTrue);
  final errors = <String>[];
  await tester.runAsync<void>(() async {
    for (final element
        in find
            .descendant(of: boundary, matching: find.byType(Image))
            .evaluate()) {
      final widget = element.widget as Image;
      await precacheImage(
        widget.image,
        element,
        onError: (error, stack) => errors.add('$error'),
      );
    }
  });
  expect(errors, isEmpty, reason: 'Mounted brand images must decode');
  await tester.pumpAndSettle();
  for (final element
      in find
          .descendant(of: boundary, matching: find.byType(RawImage))
          .evaluate()) {
    expect((element.widget as RawImage).image, isNotNull);
  }
  final render = tester.renderObject<RenderRepaintBoundary>(boundary);
  expect(render.size, tester.view.physicalSize);
  expect(tester.view.devicePixelRatio, 1);
  expect(render.debugNeedsPaint, isFalse);
  final width = render.size.width.toInt();
  final height = render.size.height.toInt();
  final id = '$phase-${width}x$height-$theme-${(scale * 100).toInt()}';
  await tester.runAsync<void>(() async {
    final writer = _writers[family] ??= await _Writer.create(
      configured,
      family,
      command,
    );
    if (writer.configured != configured || writer.command != command) {
      throw StateError('State capture configuration changed within one family');
    }
    if (!writer.ids.add(id)) throw StateError('Duplicate state checkpoint $id');
    final pngName = '$id.png';
    final file = File.fromUri(writer.output.uri.resolve(pngName));
    if (await file.exists()) throw StateError('Refusing to overwrite $pngName');
    final image = await render.toImage(pixelRatio: 1);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('PNG encoding returned null');
      await file.writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        flush: true,
      );
      await writer.records.writeAsString(
        '${jsonEncode({
          'schema': 'serverdeck-design-state-capture-v1',
          'family': family,
          'caseIds': caseIds,
          'screenId': designStateCasesById[caseIds.first]!.originId,
          'originIds': caseIds.map((id) => designStateCasesById[id]!.originId).toSet().toList(),
          'phase': phase,
          'state': phase,
          'variant': 'actual-state-checkpoint',
          'sourceOwners': caseIds.expand((id) => designStateCasesById[id]!.sources).map((source) => source.path).toSet().toList(),
          'frame': {'width': width, 'height': height},
          'theme': theme,
          'scale': scale,
          'devicePixelRatio': 1,
          'reducedMotion': media.disableAnimations,
          'captureStage': '003.3',
          'captureTask': 'T039',
          'result': 'captured',
          'scope': scope,
          'assertions': assertions,
          'callbackCounters': counters,
          'command': command,
          'png': pngName,
          'limitations': ['Only the named actual production checkpoint is pictured. '
              'Capture creation does not establish the enclosing test result, '
              'visual acceptance, native authority or full runtime recovery.', ...limitations],
        })}\n',
        mode: FileMode.append,
        flush: true,
      );
    } finally {
      image.dispose();
    }
  });
}

class _Writer {
  _Writer(this.configured, this.command, this.output, this.records);
  final String configured, command;
  final Directory output;
  final File records;
  final ids = <String>{};

  static Future<_Writer> create(
    String configured,
    String family,
    String command,
  ) async {
    final requested = Directory(configured);
    if (!requested.isAbsolute)
      throw ArgumentError('Capture path must be absolute');
    final workspace = Directory(await Directory.current.resolveSymbolicLinks());
    final intended = Directory.fromUri(
      workspace.uri.resolve('.local/design-003/003.3/'),
    );
    final normalized = Directory.fromUri(requested.uri.normalizePath());
    if (!_under(normalized.path, intended.path)) {
      throw ArgumentError('State run must be below ${intended.path}');
    }
    var ancestor = normalized;
    final missing = <String>[];
    while (!await ancestor.exists()) {
      missing.insert(
        0,
        ancestor.uri.pathSegments.where((part) => part.isNotEmpty).last,
      );
      if (ancestor.parent.path == ancestor.path) {
        throw StateError('Cannot resolve capture ancestor');
      }
      ancestor = ancestor.parent;
    }
    var resolved = Directory(await ancestor.resolveSymbolicLinks());
    for (final segment in missing) {
      resolved = Directory.fromUri(
        resolved.uri.resolve('${Uri.encodeComponent(segment)}/'),
      );
    }
    if (!_under(resolved.path, intended.path)) {
      throw ArgumentError('Resolved state run leaves intended base');
    }
    if (await resolved.exists()) {
      for (final entity in await resolved.list(followLinks: false).toList()) {
        final name = entity.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last;
        if (!_families.contains(name) || entity is! Directory) {
          throw StateError('State run contains unexpected prior evidence');
        }
      }
    }
    final output = Directory.fromUri(resolved.uri.resolve('$family/'));
    if (await FileSystemEntity.type(output.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('State family must be fresh: ${output.path}');
    }
    await output.create(recursive: true);
    final records = File.fromUri(output.uri.resolve('records.jsonl'));
    await records.writeAsString('', flush: true);
    await File.fromUri(
      output.uri.resolve('family-manifest.json'),
    ).writeAsString(
      '${jsonEncode({'schema': 'serverdeck-design-state-family-v1', 'family': family, 'command': command, 'writerPid': pid, 'startedAtUtc': DateTime.now().toUtc().toIso8601String(), 'completion': 'Validate PNGs, planned IDs, actual enclosing test exits '
          'and visual review separately. This manifest is not acceptance.'})}\n',
      flush: true,
    );
    return _Writer(configured, command, output, records);
  }
}

bool _under(String candidate, String parent) {
  String key(String value) {
    final normalized = value
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  return key(candidate).startsWith('${key(parent)}/');
}
