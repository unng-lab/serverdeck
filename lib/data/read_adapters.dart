import 'dart:convert';

import '../domain/models.dart';

/// Capability-shaped operations for future pinned SSH; no transport is enabled.
/// Callers cannot construct an arbitrary shell command through this API.
final class ReadOperation {
  const ReadOperation._(this.command);
  final String command;
  static const packages = ReadOperation._(
    r"LC_ALL=C dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Status}\n'",
  );
  static const units = ReadOperation._(
    'LC_ALL=C systemctl list-units --type=service --all --no-pager --output=json',
  );
  static const unitFiles = ReadOperation._(
    'LC_ALL=C systemctl list-unit-files --type=service --no-pager --output=json',
  );
  static const cpu = ReadOperation._('cat /proc/stat');
  static const memory = ReadOperation._('cat /proc/meminfo');
  static const uptime = ReadOperation._('cat /proc/uptime');
  static const network = ReadOperation._('cat /proc/net/dev');
  static const disk = ReadOperation._('LC_ALL=C df -P -B1 /');

  factory ReadOperation.journal({
    int limit = 100,
    String? unit,
    String? cursor,
    bool follow = false,
  }) {
    validateHistoryLimit(limit);
    if (unit != null) {
      validateUnit(unit);
    }
    if (cursor != null &&
        (!RegExp(r'^[a-zA-Z0-9_=;:.-]{1,1024}$').hasMatch(cursor))) {
      throw ArgumentError('Invalid journal cursor');
    }
    return ReadOperation._(
      'LC_ALL=C journalctl --output=json --no-pager --quiet -n $limit'
      '${unit == null ? '' : ' --unit=${posixQuote(unit)}'}'
      '${cursor == null ? '' : ' --after-cursor=${posixQuote(cursor)}'}'
      '${follow ? ' --follow' : ''}',
    );
  }
}

String posixQuote(String argument) =>
    "'${argument.replaceAll("'", "'\"'\"'")}'";

enum ReadFailure { denied, unsupported, transport, failed }

ReadFailure classifyReadFailure(int exitCode, String stderr) {
  final message = stderr.toLowerCase();
  if (exitCode == 255) {
    return ReadFailure.transport;
  }
  if (exitCode == 127) {
    return ReadFailure.unsupported;
  }
  if (message.contains('permission denied') ||
      message.contains('access denied') ||
      message.contains('insufficient permissions')) {
    return ReadFailure.denied;
  }
  return ReadFailure.failed;
}

class ParseResult<T> {
  ParseResult(Iterable<T> values, {this.malformed = 0, this.truncated = false})
    : values = List.unmodifiable(values);
  final List<T> values;
  final int malformed;
  final bool truncated;
  bool get complete => malformed == 0 && !truncated;
}

class PackageObservation {
  const PackageObservation(this.name, this.version);
  final String name, version;
}

ParseResult<PackageObservation> parsePackages(
  String output, {
  int maxRows = 10000,
}) {
  if (maxRows < 1 || maxRows > 10000) {
    throw ArgumentError('Package budget exceeded');
  }
  final values = <PackageObservation>[];
  var malformed = 0, truncated = false;
  var processed = 0;
  for (final line in const LineSplitter().convert(output)) {
    if (line.isEmpty) {
      continue;
    }
    if (++processed > maxRows) {
      truncated = true;
      break;
    }
    final fields = line.split('\t');
    if (fields.length != 3 ||
        fields[1].isEmpty ||
        !RegExp(r'^[a-z0-9][a-z0-9+.:\-]*$').hasMatch(fields[0])) {
      malformed++;
      continue;
    }
    if (fields[2] == 'installed') {
      values.add(PackageObservation(fields[0], fields[1]));
    }
  }
  return ParseResult(values, malformed: malformed, truncated: truncated);
}

class UnitObservation {
  const UnitObservation(
    this.name,
    this.load,
    this.active,
    this.sub,
    this.fileState,
  );
  final String name, load, active, sub;
  final String? fileState;
}

ParseResult<UnitObservation> parseUnits(
  String units,
  String files, {
  int maxRows = 10000,
}) {
  if (maxRows < 1 || maxRows > 10000) {
    throw ArgumentError('Unit budget exceeded');
  }
  final values = <String, UnitObservation>{};
  var malformed = 0, truncated = false, processed = 0;
  List<dynamic> decode(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is List) {
        return value;
      }
    } on FormatException {
      /* Explicit parse counter below. */
    }
    malformed++;
    return [];
  }

  for (final row in decode(units)) {
    if (++processed > maxRows) {
      truncated = true;
      break;
    }
    if (row is! Map ||
        row['unit'] is! String ||
        row['load'] is! String ||
        row['active'] is! String ||
        row['sub'] is! String) {
      malformed++;
      continue;
    }
    final name = row['unit'] as String;
    try {
      validateUnit(name);
    } on ArgumentError {
      malformed++;
      continue;
    }
    values[name] = UnitObservation(
      name,
      row['load'],
      row['active'],
      row['sub'],
      null,
    );
  }
  for (final row in decode(files)) {
    if (++processed > maxRows) {
      truncated = true;
      break;
    }
    if (row is! Map || row['unit_file'] is! String || row['state'] is! String) {
      malformed++;
      continue;
    }
    final name = row['unit_file'] as String;
    try {
      validateUnit(name);
    } on ArgumentError {
      malformed++;
      continue;
    }
    final previous = values[name];
    values[name] = UnitObservation(
      name,
      previous?.load ?? 'unknown',
      previous?.active ?? 'unknown',
      previous?.sub ?? 'unknown',
      row['state'],
    );
  }
  return ParseResult(values.values, malformed: malformed, truncated: truncated);
}

class CpuCounters {
  CpuCounters._(this.total, this.idle);
  final int total, idle;
  factory CpuCounters.parse(String output) {
    final row = const LineSplitter()
        .convert(output)
        .firstWhere((r) => r.startsWith('cpu '));
    final fields = row
        .trim()
        .split(RegExp(r'\s+'))
        .skip(1)
        .map(int.parse)
        .toList();
    if (fields.length < 4 || fields.any((v) => v < 0)) {
      throw const FormatException('Invalid CPU counters');
    }
    // guest/guest_nice are already included in user/nice. Linux adds up to steal.
    final total = fields.take(8).fold<int>(0, (sum, v) => sum + v);
    return CpuCounters._(
      total,
      fields[3] + (fields.length > 4 ? fields[4] : 0),
    );
  }
  double? utilizationSince(CpuCounters before) {
    final delta = total - before.total, idleDelta = idle - before.idle;
    if (delta <= 0 || idleDelta < 0 || idleDelta > delta) {
      return null;
    }
    return (delta - idleDelta) * 100 / delta;
  }
}

double? parseMemoryUsage(String output) {
  int? field(String name) {
    final match = RegExp(
      '^$name:\\s+(\\d+) kB',
      multiLine: true,
    ).firstMatch(output);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  final total = field('MemTotal'), available = field('MemAvailable');
  if (total == null || total <= 0 || available == null || available > total) {
    return null;
  }
  return (total - available) / total;
}
