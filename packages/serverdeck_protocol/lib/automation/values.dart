import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../codec.dart';

Never invalidAutomationValue() => throw const FormatException('VALIDATION');

DateTime automationTimestamp(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')
          .hasMatch(value)) {
    invalidAutomationValue();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toIso8601String() != value) {
    invalidAutomationValue();
  }
  return parsed;
}

DateTime? nullableAutomationTimestamp(Object? value) =>
    value == null ? null : automationTimestamp(value);

void requireAutomationInstant(DateTime value) {
  if (!value.isUtc || value.microsecondsSinceEpoch % 1000 != 0) {
    invalidAutomationValue();
  }
  automationTimestamp(value.toIso8601String());
}

String automationText(
  Object? value, {
  int min = 0,
  int max = 4096,
  bool multiline = false,
}) {
  if (value is! String ||
      value.runes.length < min ||
      value.runes.length > max ||
      unicode.nfc(value) != value ||
      value.runes.any(
        (r) =>
            (r < 32 && !(multiline && (r == 9 || r == 10))) ||
            (r >= 127 && r <= 159),
      )) {
    invalidAutomationValue();
  }
  // Also reject unpaired surrogates using the same canonical Unicode rules.
  try {
    StrictCodec().canonical({'value': value});
  } on FormatException {
    invalidAutomationValue();
  }
  return value;
}

String automationIdentifier(Object? value) {
  if (value is! String || !RegExp(r'^[a-z][a-z0-9_]{0,31}$').hasMatch(value)) {
    invalidAutomationValue();
  }
  return value;
}

void requireAutomationDocument(Map<String, Object?> value) {
  try {
    StrictCodec().encode(value, maxBytes: 256 * 1024);
  } on FormatException {
    invalidAutomationValue();
  }
}
