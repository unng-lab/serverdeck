import 'dart:collection';
import 'dart:convert';

enum ObservationStatus { available, unknown, unsupported, denied, failed }

class Observation<T> {
  const Observation({
    required this.value,
    required this.observedAt,
    this.status = ObservationStatus.available,
  });
  final T? value;
  final DateTime observedAt;
  final ObservationStatus status;
  bool isStale(DateTime now, {Duration ttl = const Duration(seconds: 15)}) =>
      now.difference(observedAt) > ttl;
}

class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.name,
    required this.endpoint,
    this.port = 22,
    this.user = 'observer',
    this.tags = const [],
    this.state = 'online',
    required this.observedAt,
  });
  final String id, name, endpoint, user, state;
  final int port;
  final List<String> tags;
  final DateTime observedAt;
}

class Software {
  const Software({
    required this.serverId,
    required this.name,
    this.version,
    required this.source,
    required this.unit,
    required this.state,
    this.confidence = 'подтверждено пакетом',
  });
  final String serverId, name, source, unit, state, confidence;
  final String? version;
}

class HostMetrics {
  const HostMetrics({
    required this.cpu,
    required this.ram,
    required this.disk,
    required this.network,
    required this.uptime,
  });
  final Observation<double> cpu, ram, disk, network;
  final String? uptime;
}

class JournalRecord {
  JournalRecord({
    required this.cursor,
    required this.bootId,
    required this.at,
    required this.unit,
    required this.priority,
    required this.message,
    Map<String, dynamic> fields = const {},
  }) : fields = Map.unmodifiable(fields);
  final String cursor, bootId, unit, message;
  final DateTime at;
  final int priority;
  final Map<String, dynamic> fields;
  Map<String, dynamic> toJson() => {
    '__CURSOR': cursor,
    '_BOOT_ID': bootId,
    '__REALTIME_TIMESTAMP': at.microsecondsSinceEpoch.toString(),
    '_SYSTEMD_UNIT': unit,
    'PRIORITY': priority.toString(),
    'MESSAGE': message,
    ...fields,
  };
  static JournalRecord fromJson(Map<String, dynamic> fields) {
    final cursor = fields['__CURSOR'];
    final boot = fields['_BOOT_ID'];
    final micros = int.tryParse('${fields['__REALTIME_TIMESTAMP']}');
    final priority = int.tryParse('${fields['PRIORITY']}');
    if (cursor is! String ||
        cursor.isEmpty ||
        boot is! String ||
        boot.isEmpty ||
        micros == null ||
        priority == null ||
        priority < 0 ||
        priority > 7 ||
        fields['MESSAGE'] is! String) {
      throw const FormatException('Incomplete journal identity or fields');
    }
    return JournalRecord(
      cursor: cursor,
      bootId: boot,
      at: DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true),
      unit: fields['_SYSTEMD_UNIT'] as String? ?? 'kernel',
      priority: priority,
      message: fields['MESSAGE'] as String,
      fields: fields,
    );
  }
}

class BoundedJournal {
  BoundedJournal({this.capacity = 500, this.maxRecordBytes = 64 * 1024}) {
    if (capacity < 1 ||
        capacity > 500 ||
        maxRecordBytes < 1 ||
        maxRecordBytes > 64 * 1024) {
      throw ArgumentError('Journal exceeds budget');
    }
  }
  final int capacity, maxRecordBytes;
  final Queue<JournalRecord> _records = Queue();
  final Set<String> _identities = {};
  int dropped = 0, malformed = 0, oversized = 0, duplicates = 0, gaps = 0;
  List<JournalRecord> get records => List.unmodifiable(_records);
  String _key(JournalRecord record) => '${record.bootId}\u0000${record.cursor}';
  void markGap() => gaps++;
  void add(JournalRecord record) {
    if (utf8.encode(jsonEncode(record.toJson())).length > maxRecordBytes) {
      oversized++;
      return;
    }
    if (!_identities.add(_key(record))) {
      duplicates++;
      return;
    }
    if (_records.length == capacity) {
      _identities.remove(_key(_records.removeFirst()));
      dropped++;
    }
    _records.addLast(record);
  }

  void addJson(String line) {
    if (utf8.encode(line).length > maxRecordBytes) {
      oversized++;
      return;
    }
    try {
      final fields = jsonDecode(line);
      if (fields is! Map<String, dynamic>) {
        throw const FormatException();
      }
      add(JournalRecord.fromJson(fields));
    } on FormatException {
      malformed++;
    } on TypeError {
      malformed++;
    }
  }
}

int validateHistoryLimit(int value) {
  if (value < 1 || value > 1000) {
    throw ArgumentError('History must be 1..1000');
  }
  return value;
}

String validateUnit(String value, {bool write = false}) {
  if (!RegExp(r'^[a-zA-Z0-9_@.:\-]+\.service$').hasMatch(value) ||
      value.length > 255 ||
      (write && value.toLowerCase().contains('netbird'))) {
    throw ArgumentError('Invalid or protected unit');
  }
  return value;
}

class JournalSession {
  final journal = BoundedJournal();
  String query = '', unit = 'all';
  int maxPriority = 7, minutes = 0, historyLimit = 100;
  bool paused = false;
  List<JournalRecord>? _snapshot;
  void togglePause() {
    paused = !paused;
    _snapshot = paused ? journal.records : null;
  }

  List<JournalRecord> visible(DateTime now) => (_snapshot ?? journal.records)
      .where(
        (record) =>
            record.message.toLowerCase().contains(query.toLowerCase()) &&
            (unit == 'all' || unit == record.unit) &&
            record.priority <= maxPriority &&
            (minutes == 0 ||
                now.difference(record.at) <= Duration(minutes: minutes)),
      )
      .toList()
      .reversed
      .toList();
  int get pending => paused
      ? journal.records
            .where(
              (r) => !_snapshot!.any(
                (old) => old.bootId == r.bootId && old.cursor == r.cursor,
              ),
            )
            .length
      : 0;
}
