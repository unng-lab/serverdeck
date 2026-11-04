import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/journals/journal_models.dart';
import 'package:serverdeck/journals/journal_protocol.dart';

JournalReply file(String bytes, {String identity = '1:2', int size = 100000}) =>
    JournalReply(
      identity: identity,
      size: size,
      body: Uint8List.fromList(utf8.encode(bytes)),
    );
void main() {
  test(
    'first file read snapshots EOF, completed lines preserve byte fragments',
    () {
      final p = JournalPayload();
      applyFileReply(p, file('', size: 40), 's', 10);
      expect(p.checkpoint['offset'], 40);
      applyFileReply(p, file('part'), 's', 11);
      expect(p.entries, isEmpty);
      applyFileReply(p, file('ial\r\n\n'), 's', 12);
      expect(p.entries.map((e) => e.text), ['partial', '']);
      expect(p.entries.map((e) => e.id), ['s/1', 's/2']);
      expect(p.entries.first.sourceAt, isNull);
      applyFileReply(p, file('unread'), 's', 13);
      applyFileReply(p, file('', identity: '1:3', size: 2), 's', 14);
      expect(p.checkpoint['offset'], 2);
      expect(p.checkpoint['fragment'], isNull);
      expect(p.partial, isTrue);
    },
  );
  test(
    'UTF8 split and long line produce one bounded event per completed line',
    () {
      final p = JournalPayload(checkpoint: {'identity': '1:2', 'offset': 0});
      applyFileReply(
        p,
        JournalReply(
          identity: '1:2',
          size: 100,
          body: Uint8List.fromList([0xd1]),
        ),
        's',
        1,
      );
      applyFileReply(
        p,
        JournalReply(
          identity: '1:2',
          size: 100,
          body: Uint8List.fromList([0x8f, 10]),
        ),
        's',
        2,
      );
      expect(p.entries.single.text, 'я');
      for (var i = 0; i < 3; i++) {
        applyFileReply(p, file('x' * 16384), 's', 3);
      }
      expect(p.entries, hasLength(1));
      expect(base64Decode(p.checkpoint['fragment'] as String).length, 16384);
      applyFileReply(p, file('\nnext\n'), 's', 4);
      expect(p.entries, hasLength(3));
      expect(p.entries[1].truncated, isTrue);
      expect(p.entries[1].text.length, 16384);
      expect(p.entries.last.text, 'next');
    },
  );
  test('shrink discards fragment, binary UTF8 and controls remain inert', () {
    final p = JournalPayload(
      checkpoint: {
        'identity': '1:2',
        'offset': 20,
        'fragment': base64Encode([1, 2]),
      },
    );
    applyFileReply(p, file('', size: 1), 's', 1);
    expect(p.checkpoint['offset'], 1);
    applyFileReply(
      p,
      JournalReply(
        identity: '1:2',
        size: 100,
        body: Uint8List.fromList([255, 27, 10]),
      ),
      's',
      2,
    );
    expect(p.entries.single.text, isNot(contains('\u001b')));
    expect(p.partial, isTrue);
  });
}
