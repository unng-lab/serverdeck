import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/codec.dart';

import 'direct_ssh.dart';

String _hash(Object value) => const DartSha256()
    .hashSync(StrictCodec().canonical(value))
    .bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

/// Actual bounded dpkg facts, not APT qualification, a transaction or authority.
/// No raw rows cross the public API; retained privately for later revalidation.
final class DirectPackageSnapshot {
  DirectPackageSnapshot._(this._json, this.digest, this.netbirdDigest);
  factory DirectPackageSnapshot.capture(DirectSshOutput output) {
    if (output.truncated || output.bytes.length > 8 * 1024 * 1024) {
      throw DirectSshFailure('RESOURCE_LIMIT');
    }
    return DirectPackageSnapshot.captureText(
      output.textRows(const {'packages'})['packages']!,
    );
  }

  /// Actual dpkg text from a composed read, with the same validation as the
  /// single packages command. Factual data only, never install authority.
  factory DirectPackageSnapshot.captureText(String text) {
    if (utf8.encode(text).length > 4 * 1024 * 1024)
      throw DirectSshFailure('RESOURCE_LIMIT');
    final rows = <List<String>>[], identities = <String>{};
    if (text.isNotEmpty) {
      final lines = text.split('\n');
      if (lines.length > 16384) throw DirectSshFailure('RESOURCE_LIMIT');
      for (final line in lines) {
        final row = line.split('\t');
        if (row.length != 4 ||
            !RegExp(
              r'^[a-z0-9][a-z0-9+.-]{0,127}(?::[a-z0-9][a-z0-9-]{0,31})?$',
            ).hasMatch(row[0]) ||
            !(row[3] == 'not-installed' && row[1].isEmpty ||
                RegExp(r'^[a-z0-9][a-z0-9-]{0,31}$').hasMatch(row[1])) ||
            !(row[3] == 'not-installed' && row[2].isEmpty ||
                RegExp(r'^[0-9A-Za-z.+:~\-]{1,256}$').hasMatch(row[2])) ||
            !const {
              'installed',
              'config-files',
              'not-installed',
            }.contains(row[3]) ||
            row[0].contains(':') && row[0].split(':').last != row[1] ||
            !identities.add(row[0].split(':').first + '\t' + row[1])) {
          throw DirectSshFailure('QUALIFICATION_REQUIRED');
        }
        rows.add(row);
      }
    }
    // An empty, successful response cannot establish a supported installed OS.
    if (rows.isEmpty) throw DirectSshFailure('QUALIFICATION_REQUIRED');
    rows.sort((a, b) {
      for (var i = 0; i < 4; i++) {
        final order = a[i].compareTo(b[i]);
        if (order != 0) return order;
      }
      return 0;
    });
    final netbird = rows.where((row) {
      final name = row[0].split(':').first;
      return name == 'netbird' || name.startsWith('netbird-');
    }).toList();
    return DirectPackageSnapshot._(
      jsonEncode(rows),
      _hash(rows),
      _hash(netbird),
    );
  }
  final String _json;
  final String digest, netbirdDigest;
  int get byteLength => utf8.encode(_json).length;
  Set<String> get installedOrConfiguredNames => Set.unmodifiable(
    (jsonDecode(_json) as List)
        .where((row) => row[3] != 'not-installed')
        .map<String>((row) => (row[0] as String).split(':').first),
  );
  @override
  String toString() => 'DirectPackageSnapshot';
}
