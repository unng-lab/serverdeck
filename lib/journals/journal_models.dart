import 'dart:convert';

enum JournalKind { journal, file }

enum JournalStatus {
  loading,
  ready,
  empty,
  partial,
  paused,
  disconnected,
  waiting,
  unavailable,
  permissionDenied,
  storageError,
  invalidResponse,
  timeout,
  outputLimit,
}

String journalStatusLabel(JournalStatus value) => switch (value) {
  JournalStatus.loading => 'Чтение журнала',
  JournalStatus.ready => 'Сбор работает',
  JournalStatus.empty => 'Записей пока нет',
  JournalStatus.partial => 'История неполная',
  JournalStatus.paused => 'Сбор выключен',
  JournalStatus.disconnected => 'Нет подключения; показана локальная история',
  JournalStatus.waiting => 'Ожидание свободного канала',
  JournalStatus.unavailable => 'Источник недоступен или не поддерживается',
  JournalStatus.permissionDenied => 'Недостаточно прав для чтения',
  JournalStatus.storageError => 'Ошибка локального хранения',
  JournalStatus.invalidResponse => 'Некорректный ответ источника',
  JournalStatus.timeout => 'Время чтения истекло',
  JournalStatus.outputLimit => 'Превышен предел ответа; возможен пропуск',
};

bool _controls(String value) =>
    RegExp(r'[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]').hasMatch(value);
bool isJournalCursor(String value) =>
    value.isNotEmpty && utf8.encode(value).length <= 4096 && !_controls(value);
String validateJournalName(String value) {
  final name = value.trim();
  if (name.isEmpty || name.runes.length > 80 || _controls(name)) {
    throw ArgumentError('Название: от 1 до 80 символов без управляющих знаков');
  }
  return name;
}

void validateJournalTarget(JournalKind kind, String value) {
  final length = utf8.encode(value).length;
  if (value.isEmpty ||
      _controls(value) ||
      length > (kind == JournalKind.file ? 1024 : 256)) {
    throw ArgumentError('Некорректный источник журнала');
  }
  if (kind == JournalKind.journal) {
    if (value.startsWith('-') ||
        !RegExp(r'^[A-Za-z0-9_@.:\\-]+\.service$').hasMatch(value)) {
      throw ArgumentError('Укажите systemd unit с расширением .service');
    }
  } else if (!value.startsWith('/') ||
      value == '/' ||
      value.endsWith('/') ||
      value.split('/').any((p) => p == '.' || p == '..')) {
    throw ArgumentError('Укажите абсолютный путь к файлу без . и ..');
  }
}

(String, bool) boundedJournalText(String raw) {
  final output = StringBuffer();
  var bytes = 0, truncated = false;
  for (var rune in raw.runes) {
    if ((rune >= 0x202a && rune <= 0x202e) ||
        (rune >= 0x2066 && rune <= 0x2069))
      continue;
    if ((rune < 32 && rune != 9 && rune != 10) || (rune >= 127 && rune <= 159))
      rune = 0xfffd;
    final text = String.fromCharCode(rune),
        size = utf8.encode(String.fromCharCode(rune)).length;
    if (bytes + size > 16384) {
      truncated = true;
      break;
    }
    output.write(text);
    bytes += size;
  }
  return (output.toString(), truncated);
}

final class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.receivedAt,
    required this.text,
    this.sourceAt,
    this.priority,
    this.truncated = false,
  });
  final String id, text;
  final int receivedAt;
  final int? sourceAt, priority;
  final bool truncated;
  JournalEntry received(int at) => JournalEntry(
    id: id,
    receivedAt: at,
    text: text,
    sourceAt: sourceAt,
    priority: priority,
    truncated: truncated,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'receivedAt': receivedAt,
    'text': text,
    'sourceAt': sourceAt,
    'priority': priority,
    'truncated': truncated,
  };
  factory JournalEntry.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>)
      throw const FormatException('JOURNAL_STORAGE');
    final id = raw['id'],
        at = raw['receivedAt'],
        text = raw['text'],
        sourceAt = raw['sourceAt'],
        priority = raw['priority'];
    if (id is! String ||
        id.isEmpty ||
        utf8.encode(id).length > 4096 ||
        at is! int ||
        at < 0 ||
        at > 8640000000000000 ||
        text is! String ||
        utf8.encode(text).length > 16384 ||
        (sourceAt != null &&
            (sourceAt is! int ||
                sourceAt < 0 ||
                sourceAt > 8640000000000000)) ||
        (priority != null &&
            (priority is! int || priority < 0 || priority > 7)) ||
        raw['truncated'] is! bool) {
      throw const FormatException('JOURNAL_STORAGE');
    }
    return JournalEntry(
      id: id,
      receivedAt: at,
      text: boundedJournalText(text).$1,
      sourceAt: sourceAt as int?,
      priority: priority as int?,
      truncated: raw['truncated'] as bool,
    );
  }
}

final class JournalPayload {
  JournalPayload({
    Map<String, dynamic>? checkpoint,
    List<JournalEntry>? entries,
    this.partial = false,
  }) : checkpoint = checkpoint ?? {},
       entries = entries ?? [];
  final Map<String, dynamic> checkpoint;
  final List<JournalEntry> entries;
  bool partial;
  String encode() => jsonEncode({
    'version': 1,
    'checkpoint': checkpoint,
    'entries': entries.map((e) => e.toJson()).toList(),
    'partial': partial,
  });
  factory JournalPayload.decode(String value) {
    try {
      if (value.length > 64 * 1024 * 1024) throw const FormatException();
      final raw = jsonDecode(value);
      if (raw is! Map<String, dynamic> ||
          raw['version'] != 1 ||
          raw['checkpoint'] is! Map<String, dynamic> ||
          raw['entries'] is! List ||
          (raw['entries'] as List).length > 10000 ||
          raw['partial'] is! bool)
        throw const FormatException();
      final cp = Map<String, dynamic>.of(
        raw['checkpoint'] as Map<String, dynamic>,
      );
      const allowed = {
        'cursor',
        'identity',
        'offset',
        'fragment',
        'fragmentAt',
        'discard',
        'sequence',
      };
      if (cp.keys.any((k) => !allowed.contains(k)))
        throw const FormatException();
      for (final key in ['cursor', 'identity', 'fragment']) {
        final v = cp[key];
        if (v != null &&
            (v is! String ||
                utf8.encode(v).length >
                    (key == 'fragment'
                        ? 22000
                        : key == 'cursor'
                        ? 4096
                        : 128)))
          throw const FormatException();
      }
      if (cp['cursor'] is String && !isJournalCursor(cp['cursor'] as String))
        throw const FormatException();
      if (cp['identity'] != null &&
          !RegExp(r'^\d+:\d+$').hasMatch(cp['identity'] as String))
        throw const FormatException();
      if (cp['fragment'] != null &&
          base64Decode(cp['fragment'] as String).length > 16384)
        throw const FormatException();
      if (cp['fragment'] is String &&
          (cp['fragment'] as String).isNotEmpty &&
          cp['fragmentAt'] is! int)
        throw const FormatException();
      for (final key in ['offset', 'sequence', 'fragmentAt']) {
        final v = cp[key];
        if (v != null && (v is! int || v < 0 || v > 9007199254740991))
          throw const FormatException();
      }
      if (cp['discard'] != null && cp['discard'] is! bool)
        throw const FormatException();
      final entries = (raw['entries'] as List)
          .map(JournalEntry.fromJson)
          .toList();
      if (entries.map((e) => e.id).toSet().length != entries.length)
        throw const FormatException();
      return JournalPayload(
        checkpoint: cp,
        entries: entries,
        partial: raw['partial'] as bool,
      );
    } catch (_) {
      throw const FormatException('JOURNAL_STORAGE');
    }
  }
}
