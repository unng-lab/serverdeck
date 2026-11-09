import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/software/software_models.dart';
import 'package:serverdeck/storage/records.dart';

void main() {
  const id = '00000001-0000-4000-8000-000000000000';
  SoftwareCardRecord record() => SoftwareCardRecord()
    ..softwareId = id
    ..profileId = id
    ..name = 'Redis'
    ..dataPaths = ['/var/lib/redis'];
  SoftwareCardInput card({
    String name = 'Redis',
    List<String> paths = const [],
  }) => SoftwareCardInput(
    name: name,
    version: null,
    service: null,
    dataPaths: paths,
    configPaths: const [],
  );
  test('unknown values stay empty; names and paths remain data', () {
    final input = card(name: ' Redis ', paths: ['/var/lib/redis', '/a/../b']);
    expect(input.name, 'Redis');
    expect(input.version, isNull);
    expect(input.toJson()['configPaths'], isEmpty);
    expect(input.dataPaths, ['/var/lib/redis', '/a/../b']);
    expect(() => input.dataPaths.add('/other'), throwsUnsupportedError);
  });
  test('validation rejects invalid names, unicode, paths and path counts', () {
    for (final name in ['', ' ', 'x' * 101, 'x\u0000', '\ud800']) {
      expect(() => card(name: name), throwsA(isA<OperationFailure>()));
    }
    for (final paths in <List<String>>[
      ['relative'],
      ['/a\n'],
      ['/a\r'],
      ['/a', '/a'],
      ['/' + 'я' * 512],
      List.generate(17, (i) => '/$i'),
    ]) {
      expect(() => card(paths: paths), throwsA(isA<OperationFailure>()));
    }
    expect(card(name: '😀' * 100).name.runes.length, 100);
  });
  test('note bounds use bytes and fixed action/outcome domains', () {
    expect(
      SoftwareNoteInput(
        action: 'configure',
        summary: 'изменено',
        outcome: 'unknown',
      ).summary,
      'изменено',
    );
    for (final summary in ['', 'я' * 1025, '\ud800', 'x\u0000']) {
      expect(
        () => SoftwareNoteInput(
          action: 'other',
          summary: summary,
          outcome: 'unknown',
        ),
        throwsA(isA<OperationFailure>()),
      );
    }
    expect(
      () => SoftwareNoteInput(
        action: 'execute',
        summary: 'x',
        outcome: 'success',
      ),
      throwsA(isA<OperationFailure>()),
    );
  });
  test('card projections detach paths, expose only metadata and enforce full budget', () {
    final r = record();
    final view = SoftwareCardView(r, currentTarget: false);
    r.dataPaths.add('/later');
    expect(view.card.dataPaths, ['/var/lib/redis']);
    expect(view.toJson().keys.toSet(), {
      'softwareId',
      'profileId',
      'target',
      'currentTarget',
      'name',
      'version',
      'service',
      'dataPaths',
      'configPaths',
      'revision',
      'createdAt',
      'updatedAt',
    });
    expect(view.toJson()['currentTarget'], false);
    final large = record()
      ..dataPaths = List.generate(16, (i) => '/$i${'x' * 1020}')
      ..configPaths = List.generate(16, (i) => '/$i${'x' * 1020}');
    expect(
      () => SoftwareCardView(large, currentTarget: true),
      throwsA(isA<OperationFailure>()),
    );
    expect(
      () => SoftwareCardView(record()..revision = 0, currentTarget: true),
      throwsA(isA<OperationFailure>()),
    );
  });
  test(
    'timestamps enforce both safe JSON boundaries including int64 minimum',
    () {
      for (final n in [-9007199254740991, 9007199254740991]) {
        expect(
          SoftwareCardView(
            record()..createdAt = n,
            currentTarget: true,
          ).createdAt,
          n,
        );
        final event = SoftwareEventRecord()
          ..eventId = id
          ..profileId = id
          ..kind = 'created'
          ..summary = 'created'
          ..createdAt = n;
        expect(SoftwareEventView(event).createdAt, n);
      }
      for (final n in [
        -9223372036854775808,
        -9007199254740992,
        9007199254740992,
      ]) {
        expect(
          () => SoftwareCardView(record()..createdAt = n, currentTarget: true),
          throwsA(isA<OperationFailure>()),
        );
        expect(
          () => SoftwareCardView(record()..updatedAt = n, currentTarget: true),
          throwsA(isA<OperationFailure>()),
        );
        final event = SoftwareEventRecord()
          ..eventId = id
          ..profileId = id
          ..kind = 'created'
          ..summary = 'created'
          ..createdAt = n;
        expect(
          () => SoftwareEventView(event),
          throwsA(isA<OperationFailure>()),
        );
      }
    },
  );
  test('all public target, author and snapshot strings reject NUL and malformed Unicode', () {
    for (final invalid in ['bad\u0000', '\ud800']) {
      for (final mutate in <void Function(SoftwareCardRecord)>[
        (r) => r.endpointId = invalid,
        (r) => r.host = invalid,
        (r) => r.username = invalid,
      ]) {
        final r = record();
        mutate(r);
        expect(
          () => SoftwareCardView(r, currentTarget: true),
          throwsA(isA<OperationFailure>()),
        );
      }
      for (final mutate in <void Function(SoftwareEventRecord)>[
        (r) => r.endpointId = invalid,
        (r) => r.host = invalid,
        (r) => r.username = invalid,
        (r) => r.softwareName = invalid,
        (r) => r.summary = invalid,
        (r) {
          r.actorKind = 'mcp';
          r.clientId = invalid;
        },
      ]) {
        final r = SoftwareEventRecord()
          ..eventId = id
          ..profileId = id
          ..kind = 'deleted'
          ..summary = 'deleted';
        mutate(r);
        expect(() => SoftwareEventView(r), throwsA(isA<OperationFailure>()));
      }
    }
  });
  test('event projection retains deletion snapshot and distinguishes reported notes', () {
    final r = SoftwareEventRecord()
      ..eventId = id
      ..profileId = id
      ..softwareId = id
      ..softwareName = 'Redis'
      ..kind = 'deleted'
      ..summary = 'Deleted';
    final view = SoftwareEventView(r);
    r.softwareName = 'changed later';
    expect(view.toJson()['softwareName'], 'Redis');
    expect(view.toJson().containsKey('id'), false);
    expect(view.toJson()['outcome'], isNull);
    expect(
      () => SoftwareEventView(r..outcome = 'success'),
      throwsA(isA<OperationFailure>()),
    );
    final note = SoftwareEventRecord()
      ..eventId = id
      ..profileId = id
      ..actorKind = 'mcp'
      ..clientId = id
      ..kind = 'note'
      ..action = 'configure'
      ..summary = 'Reported by AI'
      ..outcome = 'unknown';
    expect(SoftwareEventView(note).toJson()['outcome'], 'unknown');
    expect(
      () => SoftwareEventView(note..host = 'x' * 8192),
      throwsA(isA<OperationFailure>()),
    );
  });
}
