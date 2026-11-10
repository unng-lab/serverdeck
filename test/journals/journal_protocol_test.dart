import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/journals/journal_models.dart';
import 'package:serverdeck/journals/journal_protocol.dart';

Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));
void main() {
  test(
    'journal reads latest 200 regardless of timestamp with bounded recovery',
    () {
      for (final cursor in [null, 'saved']) {
        final command = journalCommand(
          JournalRequest.journal('a.service', cursor: cursor),
        );
        expect(command, contains('--lines=200'));
        expect(command, isNot(contains('--since')));
        expect(command.contains('--after-cursor'), cursor != null);
      }
      final recovery = journalCommand(
        const JournalRequest.journal('a.service', metadataRecovery: true),
      );
      expect(recovery, contains('--lines=1'));
      expect(recovery, isNot(contains('--since')));
      String row(int i) => jsonEncode({
        '__CURSOR': 'c$i',
        '__REALTIME_TIMESTAMP': '1000000',
        'MESSAGE': 'old',
      });
      final reply = parseJournalReply(
        const JournalRequest.journal('a.service'),
        bytes(List.generate(200, row).join('\n')),
        bytes(''),
        0,
      );
      expect(reply.events, hasLength(200));
      expect(reply.partial, isTrue);
      expect(
        parseJournalReply(
          const JournalRequest.journal('a.service'),
          bytes(List.generate(201, row).join('\n')),
          bytes(''),
          0,
        ).failure,
        JournalStatus.invalidResponse,
      );
    },
  );

  test('malformed control cursor is rejected before persisting incompatible checkpoint', () {
    for (final cursor in ['\u0080bad', '\u202ebad', '\n']) {
      final data = jsonEncode({
        '__CURSOR': cursor,
        '__REALTIME_TIMESTAMP': '1700000000000000',
        'MESSAGE': 'valid text',
      });
      final reply = parseJournalReply(
        const JournalRequest.journal('a.service'),
        bytes('$data\n'),
        bytes(''),
        0,
      );
      expect(reply.failure, JournalStatus.invalidResponse);
      expect(reply.cursor, isNull);
      expect(
        () =>
            journalCommand(JournalRequest.journal('a.service', cursor: cursor)),
        throwsArgumentError,
      );
    }
  });
  test('paths are explicit absolute data and shell quoting cannot escape', () {
    validateJournalTarget(JournalKind.file, "/opt/a 'b/\$x.log");
    expect(shellQuote("a'b"), "'a'\"'\"'b'");
    for (final path in ['relative', '/', '/a/../b', '/a\n/b']) {
      expect(
        () => validateJournalTarget(JournalKind.file, path),
        throwsArgumentError,
      );
    }
    expect(
      () => validateJournalTarget(JournalKind.journal, '-a.service'),
      throwsArgumentError,
    );
    final command = journalCommand(JournalRequest.file("/opt/a 'b/\$x.log"));
    expect(command, contains(shellQuote("/opt/a 'b/\$x.log")));
    expect(command, isNot(contains('sudo')));
  });
  test('journal parses cursor identity, time and unknown message honestly', () {
    final request = JournalRequest.journal('a.service');
    final reply = parseJournalReply(
      request,
      bytes(
        '${jsonEncode({'__CURSOR': 'c1', '__REALTIME_TIMESTAMP': '1700000000123000', 'MESSAGE': null, 'PRIORITY': '3'})}\n',
      ),
      bytes(''),
      0,
    );
    expect(reply.failure, isNull);
    expect(reply.events.single.id, 'c1');
    expect(reply.events.single.sourceAt, 1700000000123);
    expect(reply.events.single.priority, 3);
    expect(reply.events.single.text, contains('недоступно'));
    expect(reply.cursor, 'c1');
    expect(
      parseJournalReply(request, bytes('{}\n'), bytes(''), 0).failure,
      JournalStatus.invalidResponse,
    );
    expect(
      parseJournalReply(
        request,
        bytes(''),
        bytes('Permission denied'),
        1,
      ).failure,
      JournalStatus.permissionDenied,
    );
    expect(
      parseJournalReply(request, bytes(''), bytes('partial'), 0).partial,
      isTrue,
    );
  });
  test('file header bounded bytes and source metadata are separate', () {
    final reply = parseJournalReply(
      JournalRequest.file('/a', identity: '1:2', offset: 5),
      bytes('1:2 100\nnew\n'),
      bytes(''),
      0,
    );
    expect(reply.identity, '1:2');
    expect(reply.size, 100);
    expect(utf8.decode(reply.body), 'new\n');
    expect(
      parseJournalReply(
        JournalRequest.file('/a'),
        bytes('bad\n'),
        bytes(''),
        0,
      ).failure,
      JournalStatus.invalidResponse,
    );
  });
  test(
    'payload is versioned and never silently substitutes damaged history',
    () {
      final payload = JournalPayload(
        entries: [JournalEntry(id: 'c', receivedAt: 100, text: 'hello')],
      );
      expect(
        JournalPayload.decode(payload.encode()).entries.single.text,
        'hello',
      );
      expect(
        () => JournalPayload.decode('{"version":0}'),
        throwsFormatException,
      );
      final text = boundedJournalText('\u001b[31m\u202e${'я' * 10000}');
      expect(utf8.encode(text.$1).length, lessThanOrEqualTo(16384));
      expect(text.$1, isNot(contains('\u001b')));
      expect(text.$1, isNot(contains('\u202e')));
      expect(text.$2, isTrue);
    },
  );
}
