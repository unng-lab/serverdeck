import 'dart:convert';

import 'package:serverdeck_protocol/codec.dart';

import 'ssh_transport.dart';

Map<String, Object?> observation(
  String source,
  Object? value, {
  String quality = 'known',
  DateTime? observedAt,
  String? code,
  bool truncated = false,
}) => {
  'source': source,
  'observedAt': observedAt?.toUtc().toIso8601String(),
  'receivedAt': DateTime.now().toUtc().toIso8601String(),
  'quality': quality,
  'value': value,
  if (code != null) 'code': code,
  if (truncated) 'truncated': true,
};

String sourceQuality(SshReadOutput output) => output.permissionDenied
    ? 'denied'
    : output.unavailable
    ? 'unsupported'
    : output.exitCode != 0 || output.truncated
    ? 'incomplete'
    : 'known';

Map<String, String> _sections(SshReadOutput output) {
  final result = <String, String>{};
  for (final line in const LineSplitter().convert(
    utf8.decode(output.bytes, allowMalformed: true),
  )) {
    final fields = line.split('\t');
    if (fields.length != 3 || fields[1] != '0' || result.containsKey(fields[0]))
      continue;
    try {
      final bytes = base64.decode(fields[2]);
      if (bytes.length > 256 * 1024) continue;
      result[fields[0]] = utf8.decode(bytes);
    } on FormatException {
      /* A missing/invalid source remains explicitly absent. */
    }
  }
  return result;
}

String? _text(String? value, [int max = 4096]) {
  if (value == null || value.isEmpty || utf8.encode(value).length > max)
    return null;
  return value;
}

int? _integer(String? value) {
  if (value == null || !RegExp(r'^[0-9]{1,19}$').hasMatch(value)) return null;
  final parsed = int.tryParse(value);
  return parsed != null && parsed >= 0 && parsed <= 0x7fffffffffffffff
      ? parsed
      : null;
}

DateTime? _time(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  return parsed != null && parsed.isUtc ? parsed : null;
}

Map<String, Object?> parseSystem(SshReadOutput output) {
  final source = _sections(output), os = <String, String>{};
  for (final line in const LineSplitter().convert(source['osRelease'] ?? '')) {
    final equal = line.indexOf('=');
    if (equal < 1) continue;
    final key = line.substring(0, equal);
    var value = line.substring(equal + 1);
    if (value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'")))
      value = value.substring(1, value.length - 1);
    if (const {'ID', 'VERSION_ID', 'PRETTY_NAME', 'NAME'}.contains(key) &&
        _text(value, 2048) != null)
      os[key] = value;
  }
  final uptime = double.tryParse((source['uptime'] ?? '').split(' ').first);
  final value = <String, Object?>{
    'os': os.isEmpty ? null : os,
    'kernel': _text(source['kernel']),
    'architecture': _text(source['architecture']),
    'hostname': _text(source['hostname']),
    'uptimeSeconds':
        uptime != null &&
            uptime.isFinite &&
            uptime >= 0 &&
            uptime < 9223372036854775807
        ? uptime.floor()
        : null,
    'bootId': _text(source['bootId'], 64),
  };
  final complete = value.values.every((v) => v != null);
  final quality = sourceQuality(output);
  return observation(
    'ssh:os-release/uname/proc',
    value,
    quality: quality == 'known' && !complete ? 'incomplete' : quality,
    observedAt: _time(source['observedAt']),
    truncated: output.truncated,
  );
}

final class CpuSample {
  CpuSample(this.total, this.idle);
  final int total, idle;
}

final class MetricsParse {
  MetricsParse(this.value, this.cpu);
  final Map<String, Object?> value;
  final CpuSample? cpu;
}

MetricsParse parseMetrics(SshReadOutput output, CpuSample? previous) {
  final source = _sections(output);
  CpuSample? cpu;
  final first = (source['cpu'] ?? '')
      .split('\n')
      .first
      .trim()
      .split(RegExp(r'\s+'));
  if (first.length >= 5 && first.first == 'cpu') {
    final counters = first.skip(1).take(8).map(_integer).toList();
    if (counters.every((v) => v != null)) {
      final values = counters.cast<int>();
      final total = values.fold<BigInt>(
        BigInt.zero,
        (a, b) => a + BigInt.from(b),
      );
      if (total <= BigInt.from(0x7fffffffffffffff)) {
        final idle = values[3] + (values.length > 4 ? values[4] : 0);
        if (total >= BigInt.from(idle)) cpu = CpuSample(total.toInt(), idle);
      }
    }
  }
  double? cpuPercent;
  if (cpu != null &&
      previous != null &&
      cpu.total > previous.total &&
      cpu.idle >= previous.idle) {
    final busy = (cpu.total - previous.total) - (cpu.idle - previous.idle);
    if (busy >= 0)
      cpuPercent = (100.0 * busy / (cpu.total - previous.total)).clamp(
        0.0,
        100.0,
      );
  }
  final memory = <String, int>{};
  for (final line in const LineSplitter().convert(source['memory'] ?? '')) {
    final match = RegExp(r'^([A-Za-z_()]+):\s+([0-9]+) kB$').firstMatch(line);
    if (match != null) {
      final value = _integer(match[2]);
      if (value != null && value <= 0x7fffffffffffffff ~/ 1024)
        memory[match[1]!] = value * 1024;
    }
  }
  final totalMemory = memory['MemTotal'],
      availableMemory = memory['MemAvailable'];
  final usedMemory =
      totalMemory != null &&
          availableMemory != null &&
          availableMemory <= totalMemory
      ? totalMemory - availableMemory
      : null;
  int? diskTotal, diskUsed, diskAvailable;
  final diskRows = const LineSplitter().convert(source['disk'] ?? '');
  if (diskRows.length >= 2) {
    final fields = diskRows.last.trim().split(RegExp(r'\s+'));
    if (fields.length >= 6 && fields.last == '/') {
      diskTotal = _integer(fields[1]);
      diskUsed = _integer(fields[2]);
      diskAvailable = _integer(fields[3]);
    }
  }
  if (diskTotal == null || diskUsed == null || diskUsed > diskTotal) {
    diskTotal = null;
    diskUsed = null;
    diskAvailable = null;
  }
  final network = <Map<String, Object?>>[];
  for (final line in const LineSplitter().convert(source['network'] ?? '')) {
    final colon = line.indexOf(':');
    if (colon <= 0 || network.length >= 256) continue;
    final name = line.substring(0, colon).trim(),
        fields = line.substring(colon + 1).trim().split(RegExp(r'\s+'));
    if (fields.length < 16 || _text(name, 128) == null) continue;
    final received = _integer(fields[0]), sent = _integer(fields[8]);
    if (received != null && sent != null)
      network.add({'name': name, 'receivedBytes': received, 'sentBytes': sent});
  }
  final value = <String, Object?>{
    'cpuPercent': cpuPercent?.round(),
    'cpuSampleAvailable': cpu != null,
    'memory': {
      'totalBytes': totalMemory,
      'availableBytes': availableMemory,
      'usedBytes': usedMemory,
      'usedPercent':
          totalMemory != null && totalMemory > 0 && usedMemory != null
          ? (100.0 * usedMemory / totalMemory).round()
          : null,
    },
    'rootDisk': {
      'totalBytes': diskTotal,
      'usedBytes': diskUsed,
      'availableBytes': diskAvailable,
      'usedPercent': diskTotal != null && diskTotal > 0 && diskUsed != null
          ? (100.0 * diskUsed / diskTotal).round()
          : null,
    },
    'network': network,
  };
  final quality = sourceQuality(output);
  return MetricsParse(
    observation(
      'ssh:proc/stat+meminfo+net/dev+df',
      value,
      quality:
          quality == 'known' &&
              (cpu == null || usedMemory == null || diskTotal == null)
          ? 'incomplete'
          : quality,
      observedAt: _time(source['observedAt']),
      truncated: output.truncated,
    ),
    cpu,
  );
}

Map<String, Object?> parsePackages(SshReadOutput output) {
  final rows = <Map<String, Object?>>[];
  var invalid = 0, limited = output.truncated;
  for (final line in const LineSplitter().convert(
    utf8.decode(output.bytes, allowMalformed: true),
  )) {
    final fields = line.split('\t');
    if (fields.length != 3 ||
        !RegExp(r'^[a-z0-9][a-z0-9+.:_-]{0,191}$').hasMatch(fields[0]) ||
        _text(fields[1], 256) == null ||
        fields[2].length != 3) {
      invalid++;
      continue;
    }
    if (rows.length >= 2048) {
      limited = true;
      break;
    }
    rows.add({
      'name': fields[0],
      'version': fields[1],
      'type': 'deb',
      'state': fields[2].startsWith('ii') ? 'installed' : fields[2],
    });
  }
  final quality = sourceQuality(output);
  return observation(
    'ssh:dpkg-query',
    rows,
    quality: quality == 'known' && (invalid > 0 || limited)
        ? 'incomplete'
        : quality,
    observedAt: DateTime.now().toUtc(),
    truncated: limited,
  )..['parseErrors'] = invalid;
}

Map<String, Object?> parseUnits(SshReadOutput output) {
  final rows = <Map<String, Object?>>[];
  var invalid = 0, limited = output.truncated;
  for (final line in const LineSplitter().convert(
    utf8.decode(output.bytes, allowMalformed: true),
  )) {
    if (line.trim().isEmpty) continue;
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 4 ||
        !RegExp(r'^[A-Za-z0-9_.@:\\-]{1,240}\.service$').hasMatch(fields[0])) {
      invalid++;
      continue;
    }
    if (rows.length >= 2048) {
      limited = true;
      break;
    }
    rows.add({
      'name': fields[0],
      'type': 'systemd',
      'loadState': fields[1],
      'activeState': fields[2],
      'subState': fields[3],
      'description': fields
          .skip(4)
          .join(' ')
          .substring(0, fields.skip(4).join(' ').length.clamp(0, 1024)),
    });
  }
  final quality = sourceQuality(output);
  return observation(
    'ssh:systemctl',
    rows,
    quality: quality == 'known' && (invalid > 0 || limited)
        ? 'incomplete'
        : quality,
    observedAt: DateTime.now().toUtc(),
    truncated: limited,
  )..['parseErrors'] = invalid;
}

final class JournalParse {
  JournalParse(
    this.records,
    this.parseErrors,
    this.duplicates,
    this.truncated,
    this.oldestCursor,
  );
  final List<Map<String, Object?>> records;
  final int parseErrors, duplicates;
  final bool truncated;
  final String? oldestCursor;
}

JournalParse parseJournal(
  SshReadOutput output, {
  String? skipCursor,
  String? text,
  int limit = 100,
}) {
  final records = <Map<String, Object?>>[], seen = <String>{};
  var errors = 0, duplicates = 0, truncated = output.truncated, bytes = 0;
  String? oldest;
  String source;
  try {
    source = utf8.decode(output.bytes);
  } on FormatException {
    return JournalParse([], 1, 0, true, null);
  }
  final codec = StrictCodec();
  var scanned = 0;
  for (final line in const LineSplitter().convert(source)) {
    scanned++;
    try {
      final rawRecord = utf8.encode(line);
      if (rawRecord.length > 64 * 1024) {
        truncated = true;
        errors++;
        continue;
      }
      final value = codec.decode(rawRecord, maxBytes: 64 * 1024);
      final cursor = _text(value['__CURSOR'] as String?, 2048);
      if (cursor == null) throw const FormatException();
      if (cursor == skipCursor || !seen.add(cursor)) {
        duplicates++;
        continue;
      }
      final timestamp = _integer(value['__REALTIME_TIMESTAMP'] as String?);
      if (timestamp == null) throw const FormatException();
      final time = DateTime.fromMicrosecondsSinceEpoch(
        timestamp,
        isUtc: true,
      ).toIso8601String();
      var message = value['MESSAGE'];
      if (message is List &&
          message.every((v) => v is int && v >= 0 && v <= 255))
        message = utf8.decode(message.cast<int>(), allowMalformed: true);
      if (message is List && message.every((v) => v is String))
        message = message.cast<String>().join('\n');
      if (message is! String) throw const FormatException();
      final raw = utf8.encode(message);
      final cut = raw.length > 52 * 1024;
      if (cut)
        message = utf8.decode(raw.sublist(0, 52 * 1024), allowMalformed: true);
      if (text != null && !message.contains(text)) {
        oldest = cursor;
        continue;
      }
      final priority = int.tryParse('${value['PRIORITY']}');
      final unit = value['_SYSTEMD_UNIT'] ?? value['_SYSTEMD_USER_UNIT'];
      final record = <String, Object?>{
        'cursor': cursor,
        'timestamp': time,
        'unit': unit is String ? _text(unit, 512) : null,
        'priority': priority != null && priority >= 0 && priority <= 7
            ? priority
            : null,
        'message': message,
        'truncated': cut,
        'fields': {
          for (final field in ['_BOOT_ID', '_PID', 'SYSLOG_IDENTIFIER'])
            if (value[field] is String &&
                _text(value[field] as String?, 512) != null)
              field: value[field],
        },
      };
      final length = utf8.encode(jsonEncode(record)).length;
      if (records.length >= limit || bytes + length > 2 * 1024 * 1024) {
        truncated = true;
        break;
      }
      records.add(record);
      bytes += length;
      oldest = cursor;
    } catch (_) {
      errors++;
    }
  }
  records.sort(
    (a, b) => (a['timestamp'] as String).compareTo(b['timestamp'] as String),
  );
  return JournalParse(
    records,
    errors,
    duplicates,
    truncated || scanned >= limit,
    oldest,
  );
}
