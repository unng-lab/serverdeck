import 'dart:convert';

import 'package:cryptography/dart.dart';

import 'direct_ssh.dart';

Never _invalid() => throw DirectSshFailure('QUALIFICATION_REQUIRED');
Never _limit() => throw DirectSshFailure('RESOURCE_LIMIT');

/// Passive Debian control-format data only. A stanza, Trusted field or signer
/// string is never evidence that a native verifier actually ran successfully.
abstract final class DirectAptDeb822 {
  static List<Map<String, String>> parse(
    String text, {
    int maximumBytes = 4 * 1024 * 1024,
    int maximumStanzas = 64,
    bool comments = false,
  }) {
    if (maximumBytes < 1 ||
        maximumBytes > 4 * 1024 * 1024 ||
        maximumStanzas < 1 ||
        maximumStanzas > 256)
      _invalid();
    if (utf8.encode(text).length > maximumBytes) _limit();
    if (text.contains('\u0000') || RegExp(r'\r(?!\n)').hasMatch(text))
      _invalid();
    final result = <Map<String, String>>[];
    var row = <String, StringBuffer>{};
    String? previous;
    void finish() {
      if (row.isEmpty) return;
      if (result.length >= maximumStanzas) _limit();
      result.add(
        Map.unmodifiable(
          row.map((name, value) => MapEntry(name, value.toString())),
        ),
      );
      row = <String, StringBuffer>{};
      previous = null;
    }

    for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
      if (utf8.encode(line).length > 8192) _limit();
      if (line.codeUnits.any(
        (value) => value < 32 && value != 9 || value == 127,
      ))
        _invalid();
      if (comments && line.startsWith('#')) continue;
      if (line.isEmpty) {
        finish();
        continue;
      }
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (previous == null) _invalid();
        row[previous!]!
          ..write('\n')
          ..write(line.substring(1));
        continue;
      }
      final colon = line.indexOf(':');
      if (colon < 1) _invalid();
      final name = line.substring(0, colon).toLowerCase();
      if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(name) ||
          row.containsKey(name))
        _invalid();
      final value = line.substring(colon + 1);
      row[name] = StringBuffer(value.replaceFirst(RegExp(r'^[ \t]*'), ''));
      previous = name;
    }
    finish();
    return List.unmodifiable(result);
  }
}

final class DirectAptIndexDigest {
  DirectAptIndexDigest._(this.sha256, this.size);
  final String sha256;
  final int size;
}

/// Parsed signed-payload fields, NOT a signature/host/installation certificate.
/// The collector must bind these exact bytes to successful native gpgv and to
/// actual index contents, source policy, custody and unchanged file snapshots.
final class DirectAptReleaseFields {
  DirectAptReleaseFields._(
    this.payloadDigest,
    this.published,
    this.expires,
    this.indexes,
  );
  factory DirectAptReleaseFields.parse(
    String payload, {
    required DateTime now,
  }) {
    final stanzas = DirectAptDeb822.parse(payload, maximumStanzas: 1);
    if (stanzas.length != 1) _invalid();
    final fields = stanzas.single;
    final published = _date(fields['date']);
    final expires = fields.containsKey('valid-until')
        ? _date(fields['valid-until'])
        : null;
    final at = now.toUtc();
    if (published.isAfter(at.add(const Duration(minutes: 5))) ||
        expires != null &&
            (!expires.isAfter(published) || !at.isBefore(expires)))
      _invalid();
    final hashes = fields['sha256'];
    if (hashes == null) _invalid();
    final indexes = <String, DirectAptIndexDigest>{};
    for (final raw in hashes.split('\n')) {
      if (raw.trim().isEmpty) continue;
      if (indexes.length >= 16384) _limit();
      final values = raw.trim().split(RegExp(r'[ \t]+'));
      if (values.length != 3 ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(values[0]) ||
          !RegExp(r'^(0|[1-9][0-9]{0,8})$').hasMatch(values[1]))
        _invalid();
      final size = int.parse(values[1]), path = values[2];
      if (size > 512 * 1024 * 1024 ||
          !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._+~/-]{0,1023}$').hasMatch(path) ||
          path
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..') ||
          indexes.containsKey(path))
        _invalid();
      indexes[path] = DirectAptIndexDigest._(values[0].toLowerCase(), size);
    }
    if (indexes.isEmpty) _invalid();
    final digest = const DartSha256()
        .hashSync(utf8.encode(payload))
        .bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return DirectAptReleaseFields._(
      digest,
      published,
      expires,
      Map.unmodifiable(indexes),
    );
  }

  /// SHA256 of the exact plaintext Release payload, not the InRelease file.
  final String payloadDigest;
  final DateTime published;
  final DateTime? expires;
  final Map<String, DirectAptIndexDigest> indexes;
  bool matchesIndex(String metaKey, String sha256, int size) =>
      indexes[metaKey]?.sha256 == sha256 && indexes[metaKey]?.size == size;
  @override
  String toString() => 'DirectAptReleaseFields';
}

DateTime _date(String? text) {
  if (text == null || text.length > 80) _invalid();
  final match = RegExp(
    r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun),[ \t]+([0-9]{1,2})[ \t]+'
    r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[ \t]+([0-9]{4})[ \t]+'
    r'([0-9]{2}):([0-9]{2}):([0-9]{2})[ \t]+(UTC|GMT|[+-][0-9]{4})$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) _invalid();
  const months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];
  const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  final day = int.parse(match[2]!),
      month = months.indexOf(match[3]!.toLowerCase()) + 1,
      year = int.parse(match[4]!),
      hour = int.parse(match[5]!),
      minute = int.parse(match[6]!),
      second = int.parse(match[7]!);
  if (year < 1970 || hour > 23 || minute > 59 || second > 59) _invalid();
  final date = DateTime.utc(year, month, day, hour, minute, second);
  if (date.year != year ||
      date.month != month ||
      date.day != day ||
      days[date.weekday - 1] != match[1]!.toLowerCase())
    _invalid();
  final zone = match[8]!;
  if (zone.toUpperCase() == 'UTC' || zone.toUpperCase() == 'GMT') return date;
  final hours = int.parse(zone.substring(1, 3)),
      minutes = int.parse(zone.substring(3));
  if (hours > 23 || minutes > 59) _invalid();
  final offset = Duration(
    minutes: (hours * 60 + minutes) * (zone[0] == '+' ? 1 : -1),
  );
  return date.subtract(offset);
}

/// Passive gpgv status grammar only. It cannot establish that gpgv ran, selected
/// the configured keyrings or verified the same Release payload. Those belong
/// to the closed native command and its current SSH/file custody proof.
final class DirectAptSignatureFields {
  DirectAptSignatureFields._(this.signers);
  factory DirectAptSignatureFields.parse(
    String text, {
    required DateTime now,
    Set<String> allowedFingerprints = const {},
  }) {
    if (utf8.encode(text).length > 64 * 1024) _limit();
    final allowed = <String>{};
    for (final fingerprint in allowedFingerprints) {
      if (!RegExp(r'^(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{64})!?$')
          .hasMatch(fingerprint))
        _invalid();
      allowed.add(fingerprint.toLowerCase());
    }
    if (allowed.length > 16) _limit();
    final good = <String>[], valid = <(String, String)>[];
    var inSignature = false;
    String? groupGood, groupValid;
    void finishSignature() {
      if (!inSignature) return;
      if (groupGood == null ||
          groupValid == null ||
          !groupValid.endsWith(groupGood))
        _invalid();
    }

    final seconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    for (final line in text.split('\n')) {
      if (line.isEmpty) continue;
      if (line.length > 4096 ||
          line.codeUnits.any((value) => value < 32 || value == 127) ||
          !line.startsWith('[GNUPG:] '))
        _invalid();
      final parts = line.substring(9).split(' '), status = parts.first;
      if (status == 'NEWSIG') {
        finishSignature();
        inSignature = true;
        groupGood = null;
        groupValid = null;
      } else if (status == 'GOODSIG') {
        if (!inSignature ||
            groupGood != null ||
            parts.length < 3 ||
            !RegExp(r'^(?:[a-fA-F0-9]{16}|[a-fA-F0-9]{40}|[a-fA-F0-9]{64})$')
                .hasMatch(parts[1]))
          _invalid();
        groupGood = parts[1].toLowerCase();
        good.add(groupGood);
      } else if (status == 'VALIDSIG') {
        if (!inSignature ||
            groupValid != null ||
            parts.length != 10 && parts.length != 11)
          _invalid();
        final signer = parts[1].toLowerCase(),
            primary = parts.length == 11 ? parts[10].toLowerCase() : signer;
        if (!RegExp(r'^(?:[a-f0-9]{40}|[a-f0-9]{64})$').hasMatch(signer) ||
            !RegExp(r'^(?:[a-f0-9]{40}|[a-f0-9]{64})$').hasMatch(primary) ||
            !RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(parts[2]) ||
            !RegExp(r'^(0|[1-9][0-9]{0,11})$').hasMatch(parts[3]) ||
            !RegExp(r'^(0|[1-9][0-9]{0,11})$').hasMatch(parts[4]) ||
            !{'4', '5'}.contains(parts[5]) ||
            parts[6] != '0' ||
            !{'1', '3', '17', '19', '22', '27', '28'}.contains(parts[7]) ||
            !{'8', '9', '10'}.contains(parts[8]) ||
            !{'00', '01'}.contains(parts[9]))
          _invalid();
        final issued = int.parse(parts[3]), expires = int.parse(parts[4]);
        if (issued > seconds + 300 ||
            expires != 0 && (expires <= issued || seconds >= expires))
          _invalid();
        final created = DateTime.fromMillisecondsSinceEpoch(
          issued * 1000,
          isUtc: true,
        );
        if (created.toIso8601String().substring(0, 10) != parts[2]) _invalid();
        if (allowed.isNotEmpty &&
            !allowed.any(
              (pin) => pin.endsWith('!')
                  ? pin.substring(0, pin.length - 1) == signer
                  : pin == signer || pin == primary,
            ))
          _invalid();
        if (valid.length >= 16 || valid.any((row) => row.$1 == signer))
          _invalid();
        valid.add((signer, primary));
        groupValid = signer;
      } else if (status == 'KEY_CONSIDERED') {
        if (parts.length != 3 ||
            !RegExp(r'^(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{64})$')
                .hasMatch(parts[1]) ||
            !{'0', '1', '2', '3'}.contains(parts[2]))
          _invalid();
      } else if (status == 'KEYEXPIRED') {
        // An unused expired subkey may emit this even for a good signature.
        // EXPKEYSIG identifies an actually expired signer and is refused below.
        if (parts.length != 2 ||
            !RegExp(r'^(0|[1-9][0-9]{0,11})$').hasMatch(parts[1]))
          _invalid();
      } else if (status.startsWith('TRUST_')) {
        if (!{
              'TRUST_UNDEFINED',
              'TRUST_FULLY',
              'TRUST_ULTIMATE',
            }.contains(status) ||
            parts.length < 2 ||
            parts.length > 4 ||
            parts[1] != '0' ||
            parts.length > 2 &&
                !{
                  'classic',
                  'pgp',
                  'external',
                  'tofu',
                  'tofu+pgp',
                  'always',
                  'direct',
                  'unknown',
                }.contains(parts[2]))
          _invalid();
      } else if (status == 'SIG_ID') {
        if (parts.length != 4 ||
            !RegExp(r'^[a-zA-Z0-9+/=]{16,64}$').hasMatch(parts[1]) ||
            !RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(parts[2]) ||
            !RegExp(r'^(0|[1-9][0-9]{0,11})$').hasMatch(parts[3]))
          _invalid();
      } else {
        _invalid();
      }
    }
    finishSignature();
    if (valid.isEmpty ||
        good.length != valid.length ||
        valid.any((row) => !good.any((id) => row.$1.endsWith(id))) ||
        good.toSet().length != good.length)
      _invalid();
    return DirectAptSignatureFields._(
      List.unmodifiable(valid.map((row) => row.$1)),
    );
  }
  final List<String> signers;
  @override
  String toString() => 'DirectAptSignatureFields';
}
