import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cryptography/dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/theme/brand_assets.dart';
import 'package:serverdeck/theme/brand_theme.dart';

const _glyph = '例';
const _codePoint = 0x4f8b;
const _referenceFont = 'Bundled CJK reference';
const _fontHash =
    'a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da';
const _licenseHash =
    '1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9';
const _commit = 'e7db6ca603fd4862010383ff17ffd6cc4ffac1c0';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the original brandbook fonts do not contain the CJK stress glyph', () {
    for (final asset in [
      BrandAssets.regularFont,
      BrandAssets.semiboldFont,
      BrandAssets.monoRegularFont,
    ]) {
      expect(
        _glyphId(File(asset).readAsBytesSync(), _codePoint),
        0,
        reason: asset,
      );
    }
  });

  test(
    'the offline fallback bundle preserves upstream font and license',
    () async {
      final font = await rootBundle.load(BrandAssets.unicodeVariableFont);
      final bytes = font.buffer.asUint8List(
        font.offsetInBytes,
        font.lengthInBytes,
      );
      expect(bytes.length, 17772300);
      expect(_sha256(bytes), _fontHash);
      expect(_glyphId(bytes, _codePoint), greaterThan(0));
      expect(_glyphId(bytes, 0x10ffff), 0, reason: 'unsupported tofu control');

      final fvar = _fontTable(ByteData.sublistView(bytes), 0x66766172);
      final data = ByteData.sublistView(bytes);
      expect(data.getUint16(fvar + 8), 1, reason: 'one variable weight axis');
      final axis = fvar + data.getUint16(fvar + 4);
      expect(data.getUint32(axis), 0x77676874, reason: 'wght');
      expect(
        [
          for (final offset in [4, 8, 12]) data.getInt32(axis + offset) / 65536,
        ],
        [100, 100, 900],
      );

      final license = await rootBundle.load(BrandAssets.unicodeFontLicense);
      final licenseBytes = license.buffer.asUint8List(
        license.offsetInBytes,
        license.lengthInBytes,
      );
      expect(_sha256(licenseBytes), _licenseHash);
      expect(
        utf8.decode(licenseBytes),
        contains('SIL OPEN FONT LICENSE Version 1.1'),
      );
      final source = jsonDecode(
        await rootBundle.loadString(BrandAssets.unicodeFontSource),
      ) as Map<String, dynamic>;
      expect(source['family'], BrandAssets.unicodeFont);
      expect(source['commit'], _commit);
      expect(source['fontSHA256'], _fontHash);
      expect(source['fontBytes'], bytes.length);
      expect(source['licenseSHA256'], _licenseHash);
      const upstream =
          'https://raw.githubusercontent.com/google/fonts/$_commit/'
          'ofl/notosanssc/';
      expect(source['fontUrl'], '${upstream}NotoSansSC%5Bwght%5D.ttf');
      expect(source['licenseUrl'], '${upstream}OFL.txt');
      expect(source['metadataUrl'], '${upstream}METADATA.pb');

      final manifest = jsonDecode(
        await rootBundle.loadString('FontManifest.json'),
      ) as List<dynamic>;
      final entry = manifest.cast<Map<String, dynamic>>().singleWhere(
        (entry) => entry['family'] == BrandAssets.unicodeFont,
      );
      expect(entry['fonts'], [
        {'asset': BrandAssets.unicodeVariableFont},
      ]);
    },
  );

  testWidgets(
    'brand roles render the CJK stress glyph at regular and semibold',
    (tester) async {
      await tester.runAsync(() async {
        for (final entry in {
          BrandAssets.uiFont: [BrandAssets.regularFont],
          BrandAssets.semiboldFamily: [BrandAssets.semiboldFont],
          BrandAssets.monoFont: [BrandAssets.monoRegularFont],
          BrandAssets.unicodeFont: [BrandAssets.unicodeVariableFont],
        }.entries) {
          final loader = FontLoader(entry.key);
          for (final asset in entry.value) {
            loader.addFont(rootBundle.load(asset));
          }
          await loader.load();
        }
      });

      // The production chain is rendered before the reference alias is loaded.
      final actual = <Uint8List>[];
      for (final style in [
        BrandTypography.body,
        BrandTypography.button,
        BrandTypography.log,
      ]) {
        actual.add(await _renderGlyph(tester, _glyph, style));
      }
      await tester.runAsync(() async {
        final loader = FontLoader(_referenceFont)
          ..addFont(rootBundle.load(BrandAssets.unicodeVariableFont));
        await loader.load();
      });

      for (final (index, weight) in [
        FontWeight.w400,
        FontWeight.w600,
        FontWeight.w400,
      ].indexed) {
        final expected = await _renderGlyph(
          tester,
          _glyph,
          TextStyle(
            fontFamily: _referenceFont,
            fontWeight: weight,
            fontVariations: [ui.FontVariation('wght', weight.value.toDouble())],
          ),
        );
        expect(
          _pixelDifference(actual[index], expected),
          0,
          reason: 'CJK glyph pixels for brand role $index / ${weight.value}',
        );
        final tofu = await _renderGlyph(
          tester,
          String.fromCharCode(0x10ffff),
          TextStyle(fontFamily: _referenceFont, fontWeight: weight),
        );
        expect(
          _pixelDifference(actual[index], tofu),
          greaterThan(0),
          reason: 'role $index must draw the glyph, not missing-glyph tofu',
        );
        expect(
          _inkPixels(actual[index]),
          greaterThan(100),
          reason: 'role $index contains a visible glyph',
        );
      }
      expect(
        _pixelDifference(actual[0], actual[1]),
        greaterThan(0),
        reason: 'the fallback really renders different 400 and 600 weights',
      );
    },
  );
}

String _sha256(List<int> bytes) => const DartSha256()
    .hashSync(bytes)
    .bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

int _inkPixels(Uint8List bytes) {
  var count = 0;
  for (var offset = 0; offset < bytes.length; offset += 4) {
    if (bytes[offset] < 255) count++;
  }
  return count;
}

int _pixelDifference(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var differences = 0;
  for (var offset = 0; offset < a.length; offset += 4) {
    if (a[offset] != b[offset] ||
        a[offset + 1] != b[offset + 1] ||
        a[offset + 2] != b[offset + 2] ||
        a[offset + 3] != b[offset + 3]) {
      differences++;
    }
  }
  return differences;
}

Future<Uint8List> _renderGlyph(
  WidgetTester tester,
  String value,
  TextStyle style,
) async {
  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: 80,
            height: 80,
            child: ColoredBox(
              color: Colors.white,
              child: Text(
                value,
                textScaler: TextScaler.noScaling,
                style: style.copyWith(
                  inherit: false,
                  color: Colors.black,
                  fontSize: 48,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  image.dispose();
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// Minimal sfnt cmap reader for bundled TTF test fixtures, never runtime code.
int _glyphId(Uint8List bytes, int codePoint) {
  final data = ByteData.sublistView(bytes);
  final cmap = _fontTable(data, 0x636d6170);
  final count = data.getUint16(cmap + 2);
  for (var index = 0; index < count; index++) {
    final record = cmap + 4 + index * 8;
    final platform = data.getUint16(record);
    final encoding = data.getUint16(record + 2);
    if (platform != 0 &&
        !(platform == 3 && (encoding == 1 || encoding == 10))) {
      continue;
    }
    final table = cmap + data.getUint32(record + 4);
    switch (data.getUint16(table)) {
      case 12:
        final groups = data.getUint32(table + 12);
        for (var group = 0; group < groups; group++) {
          final start = table + 16 + group * 12;
          final first = data.getUint32(start);
          final last = data.getUint32(start + 4);
          if (codePoint >= first && codePoint <= last) {
            return data.getUint32(start + 8) + codePoint - first;
          }
        }
      case 4:
        if (codePoint > 0xffff) continue;
        final segments = data.getUint16(table + 6) ~/ 2;
        final ends = table + 14;
        final starts = ends + segments * 2 + 2;
        final deltas = starts + segments * 2;
        final offsets = deltas + segments * 2;
        for (var segment = 0; segment < segments; segment++) {
          final first = data.getUint16(starts + segment * 2);
          final last = data.getUint16(ends + segment * 2);
          if (codePoint < first || codePoint > last) continue;
          final delta = data.getInt16(deltas + segment * 2);
          final rangeOffset = data.getUint16(offsets + segment * 2);
          if (rangeOffset == 0) return (codePoint + delta) & 0xffff;
          final glyph = data.getUint16(
            offsets + segment * 2 + rangeOffset + (codePoint - first) * 2,
          );
          return glyph == 0 ? 0 : (glyph + delta) & 0xffff;
        }
    }
  }
  return 0;
}

int _fontTable(ByteData data, int tag) {
  final tables = data.getUint16(4);
  for (var index = 0; index < tables; index++) {
    final record = 12 + index * 16;
    if (data.getUint32(record) == tag) return data.getUint32(record + 8);
  }
  fail('font has no sfnt table 0x${tag.toRadixString(16)}');
}
