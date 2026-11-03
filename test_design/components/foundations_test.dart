import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/theme/brand_assets.dart';
import 'package:serverdeck/theme/brand_theme.dart';

void main() {
  double contrast(Color a, Color b) {
    final first = a.computeLuminance(), second = b.computeLuminance();
    return first > second
        ? (first + .05) / (second + .05)
        : (second + .05) / (first + .05);
  }

  test('canonical roles, text/control contrast and bundled foundations', () {
    final source = jsonDecode(
      File('docs/brandbook/tokens/serverdeck.tokens.json').readAsStringSync(),
    ) as Map;
    for (final entry in {
      'dark': BrandColors.dark,
      'light': BrandColors.light,
    }.entries) {
      final palette = source['themes'][entry.key] as Map;
      expect(entry.value.roles.keys.toSet(), palette.keys.toSet());
      for (final role in palette.entries) {
        expect(
          entry.value[role.key].toARGB32(),
          int.parse('ff${(role.value as String).substring(1)}', radix: 16),
        );
      }
      for (final bg in ['bg', 'surface', 'raised', 'hover', 'selected']) {
        for (final text in [
          'text',
          'muted',
          'disabled',
          'available',
          'unavailable',
          'unknown',
          'warning',
          'error',
          'running',
          'success',
        ]) {
          expect(
            contrast(entry.value[text], entry.value[bg]),
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} $text on $bg',
          );
        }
        for (final control in [
          'control',
          'focus',
          'accent',
          'chart2',
          'chart3',
        ]) {
          expect(
            contrast(entry.value[control], entry.value[bg]),
            greaterThanOrEqualTo(3),
            reason: '${entry.key} $control on $bg',
          );
        }
      }
      expect(
        contrast(entry.value['onAccent'], entry.value['accent']),
        greaterThanOrEqualTo(4.5),
      );
    }
    for (final path in [
      BrandAssets.regularFont,
      BrandAssets.semiboldFont,
      BrandAssets.monoRegularFont,
      BrandAssets.fontLicense,
      BrandAssets.darkLogo,
      BrandAssets.lightLogo,
      BrandAssets.darkMark,
      BrandAssets.lightMark,
    ]) {
      expect(File(path).lengthSync(), greaterThan(0), reason: path);
    }
  });
}
