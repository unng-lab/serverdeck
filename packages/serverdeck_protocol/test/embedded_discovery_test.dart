import 'dart:convert';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/discovery.dart';
import 'package:test/test.dart';

const sid = 'S-1-5-21-1-2-3-1001';
const generation = '12345678-1234-4234-9234-123456789ad1';
const workspace = '12345678-1234-4234-9234-123456789ad2';
final build = '${'a' * 40}+Release+${'b' * 64}';
Matcher failure([String code = 'STORAGE_BLOCKED']) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));
Future<DiscoveryDescriptor> create() => DiscoveryDescriptor.create(
  ownerSid: sid,
  buildId: build,
  serverPid: 0xffffffff,
  generation: generation,
  workspaceId: workspace,
);
Future<DiscoveryDescriptor> decode(
  List<int> bytes, {
  String? owner,
  String? expected,
}) => DiscoveryDescriptor.decode(
  bytes,
  ownerSid: owner ?? sid,
  expectedBuildId: expected ?? build,
);

void main() {
  test(
    'embedded namespace changes pipes/file while retaining exclusive mutex',
    () async {
      final ns = await DiscoveryNamespace.forOwner(sid);
      expect(
        ns.hash,
        '8d49a4a22c391106ffe6dd7644b3f699ae3949b931711ad185dbdd7cea1b8e3c',
      );
      expect(ns.mutexName, 'Global\\ServerDeckNext.v1.${ns.hash}');
      expect(DiscoveryNamespace.fileName, 'embedded-v1.discovery');
      expect(
        ns.pipeNames,
        List.generate(
          8,
          (i) => '\\\\.\\pipe\\ServerDeckNext.embedded-v1.${ns.hash}.$i',
        ),
      );
      expect(() => ns.pipeNames.add('extra'), throwsUnsupportedError);
      for (final invalid in ['', 'S-0-1-2', '$sid\n', 'S-1-${'1' * 4097}-2']) {
        await expectLater(DiscoveryNamespace.forOwner(invalid), failure());
      }
    },
  );

  test('creation uses recovered Host workspace/generation and exact format2 fields', () async {
    final descriptor = await create();
    addTearDown(descriptor.close);
    final json = StrictCodec().decode(descriptor.encode());
    expect(json.keys.toSet(), {
      'format',
      'hostKind',
      'product',
      'apiMajor',
      'apiMinor',
      'workspaceSlot',
      'workspaceId',
      'generation',
      'bootstrapToken',
      'buildId',
      'serverPid',
      'pipeNames',
    });
    expect(json['format'], 2);
    expect(json['apiMinor'], 1);
    expect(json['hostKind'], 'application');
    expect(descriptor.workspaceId, workspace);
    expect(descriptor.generation, generation);
    expect(descriptor.serverPid, 0xffffffff);
    expect(descriptor.bootstrapToken, hasLength(32));
    final roundtrip = await decode(descriptor.encode());
    addTearDown(roundtrip.close);
    expect(roundtrip.encode(), descriptor.encode());
  });

  test('creation refuses invalid recovered bindings, build and PID before publication', () async {
    for (final id in [
      '',
      '12345678-1234-1234-9234-123456789ad2',
      '${workspace.toUpperCase()}',
    ]) {
      await expectLater(
        DiscoveryDescriptor.create(
          ownerSid: sid,
          buildId: build,
          serverPid: 1,
          generation: id,
          workspaceId: workspace,
        ),
        failure(),
      );
      await expectLater(
        DiscoveryDescriptor.create(
          ownerSid: sid,
          buildId: build,
          serverPid: 1,
          generation: generation,
          workspaceId: id,
        ),
        failure(),
      );
    }
    for (final pid in [0, -1, 0x100000000]) {
      await expectLater(
        DiscoveryDescriptor.create(
          ownerSid: sid,
          buildId: build,
          serverPid: pid,
          generation: generation,
          workspaceId: workspace,
        ),
        failure('INCOMPATIBLE'),
      );
    }
    await expectLater(
      DiscoveryDescriptor.create(
        ownerSid: sid,
        buildId: 'private invalid build',
        serverPid: 1,
        generation: generation,
        workspaceId: workspace,
      ),
      failure('INCOMPATIBLE'),
    );
  });

  test(
    'legacy/future/foreign transport versions fail without fallback',
    () async {
      final descriptor = await create();
      addTearDown(descriptor.close);
      final source = StrictCodec().decode(descriptor.encode());
      for (final patch in <Map<String, Object?>>[
        {'format': 1},
        {'format': 3},
        {'format': 2.0},
        {'apiMajor': 2},
        {'apiMinor': 0},
        {'apiMinor': 1.0},
        {'hostKind': 'locald'},
        {'hostKind': null},
        {'buildId': '${'c' * 40}+Release+${'d' * 64}', 'role': 'owner'},
      ]) {
        await expectLater(
          decode(utf8.encode(jsonEncode({...source, ...patch}))),
          failure('INCOMPATIBLE'),
        );
      }
      final legacy = {...source, 'format': 1, 'apiMinor': 0}
        ..remove('hostKind');
      await expectLater(
        decode(utf8.encode(jsonEncode(legacy))),
        failure('INCOMPATIBLE'),
      );
    },
  );

  test(
    'closed fields and ready-only workspace reject malformed data',
    () async {
      final descriptor = await create();
      addTearDown(descriptor.close);
      final source = StrictCodec().decode(descriptor.encode());
      for (final patch in <Map<String, Object?>>[
        {'role': 'owner'},
        {'workspaceId': null},
        {'workspaceId': 1},
        {'generation': 'not-a-uuid'},
        {'workspaceSlot': 'other'},
        {'product': 'foreign'},
        {'serverPid': 0},
        {'serverPid': 1.0},
        {'serverPid': 0x100000000},
      ]) {
        await expectLater(
          decode(utf8.encode(jsonEncode({...source, ...patch}))),
          failure(),
        );
      }
      for (final key in source.keys.where(
        (k) => !{
          'format',
          'hostKind',
          'apiMajor',
          'apiMinor',
          'buildId',
        }.contains(k),
      )) {
        final missing = {...source}..remove(key);
        await expectLater(decode(utf8.encode(jsonEncode(missing))), failure());
      }
    },
  );

  test('all eight ordered pipe slots bind to exact owner namespace', () async {
    final descriptor = await create();
    addTearDown(descriptor.close);
    final source = StrictCodec().decode(descriptor.encode());
    for (final pipes in [
      [],
      descriptor.pipeNames.reversed.toList(),
      List.filled(8, descriptor.pipeNames.first),
      [...descriptor.pipeNames, 'extra'],
      descriptor.pipeNames
          .map((s) => s.replaceFirst('embedded-v1', 'v1'))
          .toList(),
    ]) {
      await expectLater(
        decode(utf8.encode(jsonEncode({...source, 'pipeNames': pipes}))),
        failure(),
      );
    }
    await expectLater(
      decode(descriptor.encode(), owner: 'S-1-5-21-1-2-3-1002'),
      failure(),
    );
    await expectLater(
      decode(descriptor.encode(), expected: '${'c' * 40}+Release+${'d' * 64}'),
      failure('INCOMPATIBLE'),
    );
  });

  test('bootstrap token is canonical32bytes and every exported buffer is independent', () async {
    final descriptor = await create();
    addTearDown(descriptor.close);
    final original = descriptor.bootstrapToken;
    final copy = descriptor.bootstrapToken..fillRange(0, 32, 0);
    expect(descriptor.bootstrapToken, original);
    expect(copy, List.filled(32, 0));
    final source = StrictCodec().decode(descriptor.encode());
    for (final token in [
      '',
      'A' * 42,
      '${'A' * 42}B',
      '${source['bootstrapToken']}=',
      1,
    ]) {
      await expectLater(
        decode(utf8.encode(jsonEncode({...source, 'bootstrapToken': token}))),
        failure(),
      );
    }
    descriptor.close();
    descriptor.close();
    expect(() => descriptor.bootstrapToken, failure());
    expect(() => descriptor.encode(), failure());
    expect(original, hasLength(32));
  });

  test('8192byte parser limit includes whitespace and refuses overflow/private diagnostics', () async {
    final descriptor = await create();
    addTearDown(descriptor.close);
    final bytes = descriptor.encode();
    final exact = [...bytes, ...List.filled(8192 - bytes.length, 32)];
    final decoded = await decode(exact);
    decoded.close();
    await expectLater(decode([...exact, 32]), failure());
    for (final malformed in [
      <int>[],
      [255],
      utf8.encode('{"private-marker":'),
      utf8.encode('{"format":2,"format":2}'),
    ]) {
      await expectLater(decode(malformed), failure());
    }
  });
}
