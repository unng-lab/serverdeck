import 'dart:convert';

import 'package:serverdeck_engine/remote/connections.dart';
import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_engine/remote/direct_ssh_apt_index.dart';
import 'package:serverdeck_engine/remote/direct_ssh_apt_release.dart';
import 'package:serverdeck_engine/remote/direct_ssh_apt_targets.dart';
import 'package:test/test.dart';

import '../support/direct_ssh_byte_peer.dart' show directOutput, bytesHash;
import '../support/schema3_fixture.dart' as fixture;
import 'connection_drain_test.dart' as connection;
import 'direct_ssh_apt_metadata_test.dart' as metadata;
import 'direct_ssh_apt_release_test.dart' as releaseFixture;
import 'direct_ssh_apt_targets_test.dart' as targetFixture;

const version = '16.15-0ubuntu0.24.04.1';
String paragraph({
  String name = 'postgresql-16',
  String architecture = 'amd64',
  String exactVersion = version,
  String? sha,
  String size = '123456',
  String filename = 'pool/main/p/postgresql-16/postgresql-16_16.15_amd64.deb',
}) =>
    'Package: $name\nVersion: $exactVersion\nArchitecture: $architecture\n'
    'SHA256: ${sha ?? 'e' * 64}\nSize: $size\nFilename: $filename\n'
    'Description: synthetic package\n folded description\n\n';

DirectAptPackageKey key([String name = 'postgresql-16']) =>
    DirectAptPackageKey(name, 'amd64', version);
DirectAptIndexTarget target() => DirectAptIndexTarget.capture(
  directOutput({'targets': targetFixture.target()}),
).single;
DirectAptIndexRequest request() => DirectAptIndexRequest(target(), [key()]);

String manifest() => [
  for (final path in [
    '/',
    '/var',
    '/var/lib',
    '/var/lib/apt',
    '/var/lib/apt/lists',
  ])
    'd\t$path\t0\t0\t755\t2\t4096\t11\t123\t${releaseFixture.stamp}\t${releaseFixture.stamp}',
  'f\t${targetFixture.file}\t0\t0\t644\t1\t1234\t11\t456\t${releaseFixture.stamp}\t${releaseFixture.stamp}\t${'c' * 64}',
].join('\n');

DirectAptReleaseRead release({
  String? hash,
  int? size,
  String? metaKey,
}) => releaseFixture.request().capture(
  directOutput({
    ...releaseFixture.facts(),
    'payload': metadata.release(
      hashes:
          '${hash ?? bytesHash(paragraph())} ${size ?? utf8.encode(paragraph()).length} ${metaKey ?? 'main/binary-amd64/Packages'}',
    ),
  }),
  now: metadata.at,
);

Map<String, String> facts({String? wholeIndex, String? selected}) => {
  'manifest': manifest(),
  'afterManifest': manifest(),
  'decodedHash': '${bytesHash(wholeIndex ?? paragraph())}  -\n',
  'decodedSize': '${utf8.encode(wholeIndex ?? paragraph()).length}\n',
  'packages': selected ?? paragraph(),
};

Matcher fails([String code = 'QUALIFICATION_REQUIRED']) =>
    throwsA(isA<DirectSshFailure>().having((e) => e.code, 'safe code', code));

void main() {
  test('selectors are exact immutable bounded keys with no shell/program arguments', () {
    final keys = [key()];
    final captured = DirectAptIndexRequest(target(), keys);
    keys.clear();
    expect(captured.packages, hasLength(1));
    expect(() => captured.packages.clear(), throwsUnsupportedError);
    expect(() => DirectAptIndexRequest(target(), []), fails());
    expect(() => DirectAptIndexRequest(target(), [key(), key()]), fails());
    expect(
      () => DirectAptIndexRequest(target(), [
        for (var i = 0; i < 257; i++) key('pkg$i'),
      ]),
      fails('RESOURCE_LIMIT'),
    );
    for (final tuple in [
      ('BadName', 'amd64', version),
      ('p;id', 'amd64', version),
      ('pkg', 'arm64', version),
      ('pkg', 'amd64', 'latest'),
      ('pkg', 'amd64', 'LATEST'),
      ('pkg', 'amd64', r'$(id)'),
      ('pkg', 'amd64', '1\n--other'),
      ('pkg', 'amd64', '1"bad'),
    ]) {
      expect(() => DirectAptPackageKey(tuple.$1, tuple.$2, tuple.$3), fails());
    }
  });

  test('native decoder streams complete digest/size separately from bounded selected paragraphs', () {
    final command = DirectSshCommand.aptIndex(request());
    expect(command.mutates, isFalse);
    expect(command.requiresApply, isFalse);
    expect(command.outputLimit, 8 * 1024 * 1024);
    expect(command.maximumDuration, const Duration(seconds: 30));
    expect(RegExp('cat-file').allMatches(command.script).length, 3);
    expect(
      command.script,
      contains('/usr/lib/apt/apt-helper -c /dev/stdin cat-file "\$2"'),
    );
    expect(command.script, contains('/usr/bin/head -c 536870913'));
    expect(
      command.script,
      contains('ulimit -v 131072 && exec /usr/bin/awk "\$3"'),
    );
    expect(
      command.script,
      contains('wanted["postgresql-16" SUBSEP "amd64" SUBSEP "$version"]=1'),
    );
    expect(command.script, contains('bytes > 131072'));
    expect(command.script, contains('count > 256'));
    expect(command.script, contains('total + bytes + 1 > 4194304'));
    expect(
      command.script,
      contains(r'[ "$before" = "$after" ] || fail PLAN_STALE'),
    );
    expect(command.script, contains('#clear Apt-Helper;'));
    for (final executable in command.requiredExecutables) {
      expect(
        command.script,
        contains('[ -x $executable ] || fail PREREQUISITE_UNAVAILABLE'),
      );
    }
    for (final forbidden in [
      'serverdeck-executor',
      'python',
      'mktemp',
      'download-file',
      'apt-get install',
      'apt-get update',
      '/usr/bin/tee',
    ]) {
      expect(command.script, isNot(contains(forbidden)));
    }
  });

  test('Release binds the full decoded index while raw compressed custody stays distinct', () {
    final read = request().capture(directOutput(facts()), release: release());
    expect(read.sha256, bytesHash(paragraph()));
    expect(read.size, utf8.encode(paragraph()).length);
    expect(read.files.digests[targetFixture.file], 'c' * 64);
    expect(read.sha256, isNot(read.files.digests[targetFixture.file]));
    expect(read.releasePayloadDigest, release().release.payloadDigest);
    final archive = read.archives[key().identity]!;
    expect(archive.toPin(), {
      'name': 'postgresql-16',
      'architecture': 'amd64',
      'version': version,
      'sha256': 'e' * 64,
    });
    expect(archive.size, 123456);
    expect(archive.multiArch, 'none');
    expect(() => archive.toPin().clear(), throwsUnsupportedError);
    expect(() => read.archives.clear(), throwsUnsupportedError);
    expect(() => read.files.digests.clear(), throwsUnsupportedError);
    expect(read.toString(), isNot(contains('ram.example')));
    expect(request().toString(), isNot(contains('ram.example')));
    final sameBytes = paragraph().replaceFirst(
      'Description:',
      'Multi-Arch: same\nDescription:',
    );
    final same = request().capture(
      directOutput(facts(wholeIndex: sameBytes, selected: sameBytes)),
      release: release(
        hash: bytesHash(sameBytes),
        size: utf8.encode(sameBytes).length,
      ),
    );
    expect(same.archives[key().identity]!.multiArch, 'same');
  });

  test('a compressed digest, wrong size, different MetaKey or changed decoded byte is refused', () {
    for (final signed in [
      release(hash: 'c' * 64),
      release(size: utf8.encode(paragraph()).length + 1),
      release(metaKey: 'universe/binary-amd64/Packages'),
    ]) {
      expect(
        () => request().capture(directOutput(facts()), release: signed),
        fails(),
      );
    }
    expect(
      () => request().capture(
        directOutput(
          facts(wholeIndex: paragraph().replaceFirst('synthetic', 'changed')),
        ),
        release: release(),
      ),
      fails(),
    );
    for (final changed in [
      {...facts(), 'decodedHash': '${'a' * 64}  other\n'},
      {...facts(), 'decodedSize': '01\n'},
      {...facts(), 'decodedSize': '999999999999999999999\n'},
    ]) {
      expect(
        () => request().capture(directOutput(changed), release: release()),
        fails(),
      );
    }
    expect(
      () => request().capture(
        directOutput({...facts(), 'decodedSize': '536870913\n'}),
        release: release(),
      ),
      fails('RESOURCE_LIMIT'),
    );
  });

  test('selected identities, hashes, archive sizes and paths cannot expand resolver selection', () {
    for (final selected in [
      paragraph(name: 'postgresql-client-16'),
      paragraph(architecture: 'all'),
      paragraph(exactVersion: '16.14'),
      '${paragraph()}${paragraph()}',
      paragraph(sha: 'missing'),
      paragraph(size: '0'),
      paragraph(size: '-1'),
      paragraph(filename: '../pkg.deb'),
      paragraph(filename: 'pool/../pkg.deb'),
      paragraph(filename: '/tmp/pkg.deb'),
      paragraph(filename: 'https://other/pkg.deb'),
      paragraph(filename: 'pool/pkg.rpm'),
      paragraph().replaceFirst('SHA256:', 'Missing-SHA256:'),
      paragraph().replaceFirst('Package:', 'package: other\nPackage:'),
      paragraph().replaceFirst(
        'Description:',
        'Multi-Arch: unknown\nDescription:',
      ),
    ]) {
      expect(
        () => request().capture(
          directOutput(facts(selected: selected)),
          release: release(),
        ),
        fails(),
      );
    }
    expect(
      () => request().capture(
        directOutput(facts(selected: paragraph(size: '8589934593'))),
        release: release(),
      ),
      fails('RESOURCE_LIMIT'),
    );
    final otherBytes = paragraph(name: 'postgresql-client-16');
    final noMatch = request().capture(
      directOutput(facts(wholeIndex: otherBytes, selected: '')),
      release: release(
        hash: bytesHash(otherBytes),
        size: utf8.encode(otherBytes).length,
      ),
    );
    expect(
      noMatch.archives,
      isEmpty,
    ); // Not every selected package exists in every source.
  });

  test('custody change, missing final proof and native failure never authorize a selected package', () {
    final good = directOutput(facts());
    for (final output in [
      DirectSshOutput(good.bytes, exitCode: null, truncated: false),
      DirectSshOutput(good.bytes, exitCode: 0, truncated: true),
      directOutput({...facts()}..remove('afterManifest')),
    ]) {
      expect(
        () => request().capture(output, release: release()),
        fails('UNKNOWN_OUTCOME'),
      );
    }
    expect(
      () => request().capture(
        directOutput({...facts(), 'afterManifest': '${manifest()}changed'}),
        release: release(),
      ),
      fails('PLAN_STALE'),
    );
    final partial = directOutput({
      'manifest': manifest(),
      'decodedHash': '${bytesHash(paragraph())}  -\n',
    });
    final failure = DirectSshOutput(
      [
        ...partial.bytes,
        ...ascii.encode('SDSSH_ERROR\tQUALIFICATION_REQUIRED\n'),
      ],
      exitCode: 1,
      truncated: false,
    );
    expect(() => request().capture(failure, release: release()), fails());
  });

  test('exact archive read crosses actual SSH/native owner gates with no remote helper', () async {
    final s = await connection.Setup.create(), context = await s.context();
    final command = DirectSshCommand.aptIndex(request());
    s.io.attempts.single.client.onExecute = (session, _) {
      session.onInput = (input) {
        expect(utf8.decode(input), command.script);
        session.output.add(directOutput(facts()).bytes);
        session.finish().ignore();
      };
    };
    final work = s.connections.executeDirectOwner(
      context,
      fixture.profile,
      command,
    );
    final result = await work.result;
    await work.done;
    expect(
      request()
          .capture(result.output, release: release())
          .archives[key().identity]!
          .sha256,
      'e' * 64,
    );
  });
}
