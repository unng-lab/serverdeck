import 'dart:convert';
import 'dart:typed_data';

import 'journal_models.dart';

enum JournalRequestKind { discover, journal, file }

final class JournalRequest {
  const JournalRequest.discover()
    : kind = JournalRequestKind.discover,
      target = '',
      cursor = null,
      metadataRecovery = false,
      identity = null,
      offset = 0;
  const JournalRequest.journal(
    this.target, {
    this.cursor,
    this.metadataRecovery = false,
  }) : kind = JournalRequestKind.journal,
       identity = null,
       offset = 0;
  const JournalRequest.file(this.target, {this.identity, this.offset = 0})
    : kind = JournalRequestKind.file,
      cursor = null,
      metadataRecovery = false;
  final JournalRequestKind kind;
  final String target;
  final String? cursor, identity;
  final bool metadataRecovery;
  final int offset;
}

final class JournalReply {
  JournalReply({
    this.failure,
    this.units = const [],
    this.events = const [],
    this.cursor,
    this.identity,
    this.size = 0,
    Uint8List? body,
    this.partial = false,
    this.cursorRejected = false,
  }) : body = body ?? Uint8List(0);
  final JournalStatus? failure;
  final List<String> units;
  final List<JournalEntry> events;
  final String? cursor, identity;
  final int size;
  final Uint8List body;
  final bool partial, cursorRejected;
}

String shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
String journalCommand(JournalRequest request) {
  if (request.kind == JournalRequestKind.discover)
    return 'LC_ALL=C SYSTEMD_COLORS=0 systemctl --no-pager --no-legend --plain --full list-units --all --type=service';
  validateJournalTarget(
    request.kind == JournalRequestKind.file
        ? JournalKind.file
        : JournalKind.journal,
    request.target,
  );
  if (request.kind == JournalRequestKind.journal) {
    final cursor = request.cursor;
    if (cursor != null && !isJournalCursor(cursor))
      throw ArgumentError('Invalid cursor');
    final fields = request.metadataRecovery
        ? '__CURSOR,__REALTIME_TIMESTAMP'
        : '__CURSOR,__REALTIME_TIMESTAMP,MESSAGE,PRIORITY,_SYSTEMD_UNIT';
    return 'LC_ALL=C SYSTEMD_COLORS=0 journalctl --no-pager --output=json --output-fields=$fields --unit=${shellQuote(request.target)} --lines=${request.metadataRecovery ? 1 : journalTailLines}${cursor == null || request.metadataRecovery ? '' : ' --after-cursor=${shellQuote(cursor)}'}';
  }
  if (request.offset < 0 ||
      request.offset > 9007199254740991 ||
      (request.identity != null &&
          !RegExp(r'^\d+:\d+$').hasMatch(request.identity!)))
    throw ArgumentError('Invalid file checkpoint');
  return 'LC_ALL=C; export LC_ALL; p=${shellQuote(request.target)}; '
      r'stat -L -- "$p" >/dev/null || exit 44; [ -f "$p" ] || exit 44; [ -r "$p" ] || exit 43; exec 3<"$p" || exit 43; '
      r'''[ -f /proc/self/fd/3 ] || exit 44; m=$(stat -Lc '%d:%i %s' /proc/self/fd/3) || exit 45; '''
      r'''printf '%s\n' "$m"; set -- $m; '''
      '[ "\$1" = ${shellQuote(request.identity ?? '')} ] && [ "\$2" -ge ${request.offset} ] || exit 0; '
      'dd bs=1 skip=${request.offset} count=16384 <&3 2>/dev/null';
}

JournalReply parseJournalReply(
  JournalRequest request,
  Uint8List output,
  Uint8List errors,
  int? status,
) {
  try {
    if (output.length + errors.length > 65536)
      return JournalReply(failure: JournalStatus.outputLimit);
    final err = utf8.decode(errors, allowMalformed: true).toLowerCase();
    if (status != 0) {
      final denied =
          status == 43 ||
          err.contains('permission denied') ||
          err.contains('access denied');
      return JournalReply(
        failure: denied
            ? JournalStatus.permissionDenied
            : JournalStatus.unavailable,
        cursorRejected:
            !denied &&
            status != 127 &&
            request.kind == JournalRequestKind.journal &&
            request.cursor != null,
      );
    }
    final partial = errors.isNotEmpty;
    if (request.kind == JournalRequestKind.file) {
      final split = output.indexOf(10);
      if (split < 0 || split > 180) throw const FormatException();
      final header = utf8.decode(output.sublist(0, split)).split(' ');
      if (header.length != 2 ||
          !RegExp(r'^\d+:\d+$').hasMatch(header[0]) ||
          header[0].length > 128)
        throw const FormatException();
      final size = int.tryParse(header[1]);
      if (size == null ||
          size < 0 ||
          size > 9007199254740991 ||
          output.length - split - 1 > 16384)
        throw const FormatException();
      return JournalReply(
        identity: header[0],
        size: size,
        body: Uint8List.fromList(output.sublist(split + 1)),
        partial: partial,
      );
    }
    final lines = const LineSplitter().convert(utf8.decode(output));
    if (request.kind == JournalRequestKind.discover) {
      final units = <String>[];
      for (final line in lines) {
        final unit = line.trim().split(RegExp(r'\s+')).first;
        try {
          validateJournalTarget(JournalKind.journal, unit);
        } on ArgumentError {
          continue;
        }
        if (!units.contains(unit)) units.add(unit);
      }
      return JournalReply(
        units: units.take(500).toList(),
        partial: partial || units.length >= 500,
      );
    }
    if (lines.length > (request.metadataRecovery ? 1 : journalTailLines))
      throw const FormatException();
    final events = <JournalEntry>[];
    String? cursor;
    for (final line in lines) {
      final value = jsonDecode(line);
      if (value is! Map<String, dynamic>) throw const FormatException();
      final id = value['__CURSOR'],
          time = int.tryParse('${value['__REALTIME_TIMESTAMP']}');
      if (id is! String ||
          !isJournalCursor(id) ||
          time == null ||
          time < 0 ||
          time ~/ 1000 > 8640000000000000)
        throw const FormatException();
      cursor = id;
      if (request.metadataRecovery) continue;
      final message = value['MESSAGE'],
          priority = int.tryParse('${value['PRIORITY']}');
      final text = boundedJournalText(
        message is String ? message : '[сообщение недоступно]',
      );
      events.add(
        JournalEntry(
          id: id,
          receivedAt: 0,
          sourceAt: time ~/ 1000,
          priority: priority != null && priority >= 0 && priority <= 7
              ? priority
              : null,
          text: text.$1,
          truncated: text.$2,
        ),
      );
    }
    return JournalReply(
      events: events,
      cursor: cursor,
      partial:
          partial ||
          lines.length >= journalTailLines ||
          request.metadataRecovery,
    );
  } catch (_) {
    return JournalReply(failure: JournalStatus.invalidResponse);
  }
}

/// Advance bounded file bytes only; emits completed lines, never fragment chunks.
void applyFileReply(
  JournalPayload payload,
  JournalReply reply,
  String sourceId,
  int now,
) {
  final cp = payload.checkpoint;
  if (cp['identity'] != reply.identity ||
      reply.size < (cp['offset'] as int? ?? 0)) {
    final sequence = cp['sequence'] as int? ?? 0;
    cp
      ..clear()
      ..addAll({
        'identity': reply.identity,
        'offset': reply.size,
        'sequence': sequence,
      });
    payload.partial = true;
    return;
  }
  final fragment = cp['fragment'] as String?;
  var pending = fragment == null ? <int>[] : base64Decode(fragment).toList();
  int? fragmentAt = cp['fragmentAt'] as int?;
  var discard = cp['discard'] as bool? ?? false,
      seq = cp['sequence'] as int? ?? 0;
  for (final byte in reply.body) {
    if (byte == 10) {
      if (pending.isNotEmpty && pending.last == 13) pending.removeLast();
      String raw;
      try {
        raw = utf8.decode(pending);
      } catch (_) {
        raw = utf8.decode(pending, allowMalformed: true);
        payload.partial = true;
      }
      final text = boundedJournalText(raw);
      payload.entries.add(
        JournalEntry(
          id: '$sourceId/${++seq}',
          receivedAt: now,
          text: text.$1,
          truncated: discard || text.$2,
        ),
      );
      pending = [];
      fragmentAt = null;
      discard = false;
    } else if (!discard) {
      if (pending.length < 16384) {
        fragmentAt ??= now;
        pending.add(byte);
      } else {
        discard = true;
        payload.partial = true;
      }
    }
  }
  cp
    ..['offset'] = (cp['offset'] as int? ?? 0) + reply.body.length
    ..['discard'] = discard
    ..['sequence'] = seq;
  if (pending.isEmpty) {
    cp.remove('fragment');
    cp.remove('fragmentAt');
  } else {
    cp['fragment'] = base64Encode(pending);
    cp['fragmentAt'] = fragmentAt;
  }
  payload.partial =
      true; // inode/size cannot establish continuous file coverage.
}
