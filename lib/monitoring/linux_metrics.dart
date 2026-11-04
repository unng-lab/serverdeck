import 'dart:convert';
import 'dart:typed_data';

import 'monitoring_models.dart';

// No interpolation, user values, installation, sudo, PTY or stdin. sh is explicit
// so the collector grammar does not depend on the SSH account's interactive shell.
const linuxMonitoringCommand = r'''sh -c '
LC_ALL=C
export LC_ALL
printf "SDM1\nOS\n"
os=$(uname -s 2>/dev/null)
printf "%s\n" "$os"
if [ "$os" != "Linux" ]; then
  printf "CPU\nMEM\nDISK\nEND\n"
  exit 0
fi
printf "CPU\n"
{ while IFS= read -r line; do
  case "$line" in cpu\ *) printf "%s\n" "$line"; break;; esac
done < /proc/stat; } 2>/dev/null
printf "MEM\n"
{ while IFS= read -r line; do
  case "$line" in MemTotal:*|MemAvailable:*) printf "%s\n" "$line";; esac
done < /proc/meminfo; } 2>/dev/null
printf "DISK\n"
df -Pk / 2>/dev/null || :
printf "END\n"
' ''';

/// A normalized owner-only sample: no raw output or remote error text.
final class LinuxSample {
  const LinuxSample({
    this.cpu,
    this.memoryPercent,
    this.diskPercent,
    this.cpuReason,
    this.memoryReason,
    this.diskReason,
  }) : failure = null;
  const LinuxSample.failed(this.failure)
    : cpu = null,
      memoryPercent = null,
      diskPercent = null,
      cpuReason = null,
      memoryReason = null,
      diskReason = null;
  final CpuCounters? cpu;
  final double? memoryPercent, diskPercent;
  final MonitoringReason? failure, cpuReason, memoryReason, diskReason;

  MonitoringReason? reasonFor(MetricKind kind) {
    if (failure != null) return failure;
    return switch (kind) {
      MetricKind.cpu =>
        cpuReason ?? (cpu == null ? MonitoringReason.sourceUnavailable : null),
      MetricKind.memory =>
        memoryReason ??
            (memoryPercent == null ? MonitoringReason.sourceUnavailable : null),
      MetricKind.disk =>
        diskReason ??
            (diskPercent == null ? MonitoringReason.sourceUnavailable : null),
    };
  }
}

LinuxSample parseLinuxMetrics(Uint8List stdout, {required int? exitCode}) {
  const invalid = LinuxSample.failed(MonitoringReason.invalidResponse);
  if (exitCode != 0 || stdout.length > 65536) return invalid;
  try {
    final text = utf8.decode(stdout).replaceAll('\r\n', '\n');
    if (text.runes.any((c) => (c < 32 && c != 9 && c != 10) || c == 127))
      return invalid;
    final lines = text.split('\n');
    if (lines.last.isEmpty) lines.removeLast();
    if (lines.any((line) => utf8.encode(line).length > 4096)) return invalid;
    const markers = ['SDM1', 'OS', 'CPU', 'MEM', 'DISK', 'END'];
    if (markers.any(
      (marker) => lines.where((line) => line == marker).length != 1,
    ))
      return invalid;
    final positions = markers.map(lines.indexOf).toList();
    if (positions[0] != 0 ||
        positions[1] != 1 ||
        positions[2] != 3 ||
        positions.last != lines.length - 1)
      return invalid;
    for (var i = 1; i < positions.length; i++) {
      if (positions[i] <= positions[i - 1]) return invalid;
    }
    if (lines[2].isEmpty)
      return const LinuxSample.failed(MonitoringReason.sourceUnavailable);
    if (lines[2] != 'Linux')
      return const LinuxSample.failed(MonitoringReason.unsupportedOs);
    List<String> section(int index) => lines
        .sublist(positions[index] + 1, positions[index + 1])
        .where((line) => line.isNotEmpty)
        .toList();
    final (cpu, cpuReason) = _cpu(section(2));
    final (memory, memoryReason) = _memory(section(3));
    final (disk, diskReason) = _disk(section(4));
    return LinuxSample(
      cpu: cpu,
      memoryPercent: memory,
      diskPercent: disk,
      cpuReason: cpuReason,
      memoryReason: memoryReason,
      diskReason: diskReason,
    );
  } catch (_) {
    return invalid; // No source bytes in exceptions, UI or logs.
  }
}

int? _unsigned(String value) {
  if (!RegExp(r'^[0-9]+$').hasMatch(value)) return null;
  return int.tryParse(value); // VM target: rejects values above signed64.
}

(CpuCounters?, MonitoringReason?) _cpu(List<String> lines) {
  if (lines.isEmpty) return (null, MonitoringReason.sourceUnavailable);
  if (lines.length != 1) return (null, MonitoringReason.invalidResponse);
  final fields = lines.single.trim().split(RegExp(r'\s+'));
  if (fields.length < 9 || fields.first != 'cpu')
    return (null, MonitoringReason.invalidResponse);
  final counters = fields.skip(1).take(8).map(_unsigned).toList();
  if (counters.any((value) => value == null))
    return (null, MonitoringReason.invalidResponse);
  return (CpuCounters(counters.cast<int>()), null);
}

(double?, MonitoringReason?) _memory(List<String> lines) {
  final fields = <String, int>{};
  for (final line in lines) {
    final match = RegExp(r'^(MemTotal|MemAvailable):\s+([0-9]+)\s+kB$')
        .firstMatch(line);
    if (match == null) return (null, MonitoringReason.invalidResponse);
    final key = match[1]!, value = _unsigned(match[2]!);
    if (value == null || fields.containsKey(key))
      return (null, MonitoringReason.invalidResponse);
    fields[key] = value;
  }
  final total = fields['MemTotal'], available = fields['MemAvailable'];
  if (total == null || available == null)
    return (null, MonitoringReason.sourceUnavailable);
  if (total <= 0 || available > total)
    return (null, MonitoringReason.invalidResponse);
  return ((total - available) / total * 100, null);
}

(double?, MonitoringReason?) _disk(List<String> lines) {
  if (lines.isEmpty) return (null, MonitoringReason.sourceUnavailable);
  if (lines.length != 2) return (null, MonitoringReason.invalidResponse);
  final fields = lines.last.trim().split(RegExp(r'\s+'));
  if (fields.length < 6 || fields.last != '/')
    return (null, MonitoringReason.invalidResponse);
  final tail = fields.sublist(fields.length - 5);
  final blocks = _unsigned(tail[0]),
      used = _unsigned(tail[1]),
      available = _unsigned(tail[2]);
  if (blocks == null ||
      used == null ||
      available == null ||
      !RegExp(r'^[0-9]+%$').hasMatch(tail[3]) ||
      _unsigned(tail[3].substring(0, tail[3].length - 1)) == null) {
    return (null, MonitoringReason.invalidResponse);
  }
  final total = BigInt.from(used) + BigInt.from(available);
  if (total == BigInt.zero) return (null, MonitoringReason.invalidResponse);
  return (used / total.toDouble() * 100, null);
}
