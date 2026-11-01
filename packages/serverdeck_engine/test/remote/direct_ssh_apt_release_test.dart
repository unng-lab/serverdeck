import 'dart:convert';

import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_engine/remote/connections.dart';
import 'package:serverdeck_engine/remote/direct_ssh_apt_release.dart';
import 'package:test/test.dart';

import '../support/direct_ssh_byte_peer.dart' show directOutput;
import '../support/schema3_fixture.dart' as fixture;
import 'connection_drain_test.dart' as connection;
import 'direct_ssh_apt_metadata_test.dart' as metadata;

const releasePath = '/var/lib/apt/lists/ram.example_dists_noble_InRelease';
const keyring = '/usr/share/keyrings/ram-archive.gpg';
const parents = [
  '/',
  '/usr',
  '/usr/share',
  '/usr/share/keyrings',
  '/var',
  '/var/lib',
  '/var/lib/apt',
  '/var/lib/apt/lists',
];
const stamp = '2026-11-01 00:00:00.000000000 +0000';

DirectAptReleaseRequest request() =>
    DirectAptReleaseRequest(releasePath: releasePath, keyrings: [keyring]);

String manifest() => [
  for (final path in parents)
    'd\t$path\t0\t0\t755\t2\t4096\t11\t123\t$stamp\t$stamp',
  for (final path in [releasePath, keyring])
    'f\t$path\t0\t0\t644\t1\t1234\t11\t456\t$stamp\t$stamp\t${'a' * 64}',
].join('\n');

Map<String, String> facts() => {
  'manifest': manifest(),
  'afterManifest': manifest(),
  'status': metadata.signature(),
  'payload': metadata.release(),
};

Matcher rejected([String code = 'QUALIFICATION_REQUIRED']) => throwsA(
  isA<DirectSshFailure>().having((e) => e.code, 'safe failure', code),
);

void main() {
  test('read request accepts only finite existing APT release and binary key paths', () {
    final keys = [keyring];
    final captured = DirectAptReleaseRequest(
      releasePath: releasePath,
      keyrings: keys,
    );
    keys.clear();
    expect(captured.keyrings, [keyring]);
    expect(() => captured.keyrings.add('other'), throwsUnsupportedError);
    for (final path in [
      '/etc/shadow',
      '/var/lib/apt/lists/../ram_InRelease',
      '/var/lib/apt/lists/subdir/ram_InRelease',
      '/var/lib/apt/lists/ram_InRelease;echo',
      "/var/lib/apt/lists/ram'\$(echo)_InRelease",
      '/var/lib/apt/lists/ram_Release',
      '/var/lib/apt/lists/${'a' * 241}_InRelease',
    ]) {
      expect(
        () => DirectAptReleaseRequest(releasePath: path, keyrings: [keyring]),
        rejected(),
      );
    }
    for (final keys in [
      <String>[],
      [keyring, keyring],
      ['/etc/shadow'],
      ['/etc/apt/keyrings/ram.asc'],
      ['/etc/apt/keyrings/../ram.gpg'],
      [for (var i = 0; i < 17; i++) '/etc/apt/keyrings/key$i.gpg'],
    ]) {
      expect(
        () => DirectAptReleaseRequest(releasePath: releasePath, keyrings: keys),
        rejected(
          keys.length > 16 ? 'RESOURCE_LIMIT' : 'QUALIFICATION_REQUIRED',
        ),
      );
    }
    expect(
      DirectAptReleaseRequest(
        releasePath: releasePath,
        keyrings: ['/etc/apt/trusted.gpg'],
      ).keyrings,
      ['/etc/apt/trusted.gpg'],
    );
  });

  test('native verification streams with pipefail and clean environment, no helper or writes', () {
    final command = DirectSshCommand.aptRelease(request());
    expect(command.mutates, isFalse);
    expect(command.requiresApply, isFalse);
    expect(command.outputLimit, 8 * 1024 * 1024);
    expect(command.maximumDuration, const Duration(seconds: 30));
    expect(
      command.script,
      contains('/usr/bin/bash --noprofile --norc -o pipefail -c'),
    );
    expect(command.script, contains('/usr/bin/env -i PATH=/usr/bin:/bin'));
    expect(command.script, contains('--homedir / --weak-digest SHA1'));
    expect(
      command.script,
      contains(
        "--keyring '$keyring' --status-fd 1 '$releasePath' || { printf '\\n'; fail QUALIFICATION_REQUIRED; }",
      ),
    );
    expect(
      command.script,
      contains(
        "--keyring '$keyring' --output - '$releasePath' || { printf '\\n'; fail QUALIFICATION_REQUIRED; }",
      ),
    );
    expect(
      command.script,
      contains(r'[ "$before" = "$after" ] || fail PLAN_STALE'),
    );
    expect(command.script, contains(r'[ ! -L "$path" ]'));
    expect(command.script, contains(r'/usr/bin/stat -c %h -- "$path"'));
    expect(
      command.script.indexOf(r'before=$(snapshot)'),
      lessThan(command.script.indexOf("printf 'status\\t'")),
    );
    expect(
      command.script.indexOf(r'after=$(snapshot)'),
      greaterThan(command.script.indexOf("printf 'payload\\t'")),
    );
    for (final tool in command.requiredExecutables) {
      expect(
        command.script,
        contains('[ -x $tool ] || fail PREREQUISITE_UNAVAILABLE'),
      );
    }
    for (final forbidden in [
      'serverdeck-executor',
      'python',
      'apt-get',
      '--keyserver',
      '--import',
      '/usr/bin/mkdir',
      '/usr/bin/rm',
      '/usr/bin/tee',
      '--log-file',
    ]) {
      expect(command.script, isNot(contains(forbidden)));
    }
    expect(command.toString(), isNot(contains('ram.example')));
    expect(request().toString(), isNot(contains('ram.example')));
  });

  test('completed SSH read binds immutable raw file hashes, payload and signer selection', () {
    final read = request().capture(
      directOutput(facts()),
      now: metadata.at,
      allowedFingerprints: {metadata.primary},
    );
    expect(read.fileDigests, {releasePath: 'a' * 64, keyring: 'a' * 64});
    expect(() => read.fileDigests.clear(), throwsUnsupportedError);
    expect(
      read.release.matchesIndex(
        'main/binary-amd64/Packages',
        metadata.checksum,
        123,
      ),
      isTrue,
    );
    expect(read.release.payloadDigest, isNot(read.fileDigests[releasePath]));
    expect(read.toString(), isNot(contains('RAM')));
    expect(
      () => request().capture(
        directOutput(facts()),
        now: metadata.at,
        allowedFingerprints: {'3' * 40},
      ),
      rejected(),
    );
  });

  test(
    'manifest is complete, ordered, root controlled, single-link and unchanged',
    () {
      final original = manifest();
      for (final changed in [
        original.replaceFirst('d\t/\t0\t0\t755', 'd\t/\t1\t0\t755'),
        original.replaceFirst('\t755\t', '\t777\t'),
        original.replaceFirst('\t755\t', '\t754\t'),
        original.replaceFirst('\t644\t', '\t664\t'),
        original.replaceFirst('\t644\t', '\t640\t'),
        original.replaceFirst('\t644\t1\t', '\t644\t2\t'),
        original.replaceFirst('\t644\t1\t1234', '\t644\t1\t4194305'),
        original.replaceFirst(
          '\t644\t1\t1234',
          '\t644\t1\t9999999999999999999',
        ),
        original.replaceFirst('\t755\t2\t', '\t755\t9999999999999999999\t'),
        original.replaceFirst('\t0\t0\t755', '\t0\t-1\t755'),
        original.replaceFirst(stamp, 'untrusted timestamp'),
        original.replaceFirst('a' * 64, 'G' * 64),
        original.replaceFirst(
          releasePath,
          '/var/lib/apt/lists/other_InRelease',
        ),
        original.split('\n').reversed.join('\n'),
        original.substring(original.indexOf('\n') + 1),
        '$original\n${original.split('\n').last}',
      ]) {
        expect(
          () => request().capture(
            directOutput({
              ...facts(),
              'manifest': changed,
              'afterManifest': changed,
            }),
            now: metadata.at,
          ),
          rejected(),
        );
      }
      expect(
        () => request().capture(
          directOutput({
            ...facts(),
            'afterManifest': original.replaceFirst('a' * 64, 'b' * 64),
          }),
          now: metadata.at,
        ),
        rejected('PLAN_STALE'),
      );
    },
  );

  test(
    'framed native verifier failure preserves safe code after partial rows',
    () {
      final partial = directOutput({
        'manifest': manifest(),
        'status': metadata.signature(),
      });
      final failed = DirectSshOutput(
        [
          ...partial.bytes,
          ...ascii.encode('SDSSH_ERROR\tQUALIFICATION_REQUIRED\n'),
        ],
        exitCode: 1,
        truncated: false,
      );
      expect(() => request().capture(failed, now: metadata.at), rejected());
    },
  );

  test('ACK loss, nonzero native exit, omitted final proof and corrupted payload never qualify', () {
    final good = directOutput(facts());
    for (final output in [
      DirectSshOutput(good.bytes, exitCode: null, truncated: false),
      DirectSshOutput(good.bytes, exitCode: 1, truncated: false),
      DirectSshOutput(good.bytes, exitCode: 0, truncated: true),
      directOutput({...facts()}..remove('afterManifest')),
      directOutput({...facts(), 'untrustedQualified': 'true'}),
    ]) {
      expect(
        () => request().capture(output, now: metadata.at),
        rejected('UNKNOWN_OUTCOME'),
      );
    }
    for (final changed in [
      {
        ...facts(),
        'status': '${metadata.signature()}[GNUPG:] FAILURE verify 1\n',
      },
      {...facts(), 'status': ''},
      {...facts(), 'payload': '${metadata.release()}\u0000'},
      {
        ...facts(),
        'payload': metadata.release(expiry: 'Sun, 01 Nov 2026 00:01:00 UTC'),
      },
    ]) {
      expect(
        () => request().capture(directOutput(changed), now: metadata.at),
        rejected(),
      );
    }
  });

  test('read passes actual owned connection/native gate with no executor enrollment', () async {
    final s = await connection.Setup.create(), context = await s.context();
    final command = DirectSshCommand.aptRelease(request());
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
    final read = request().capture(result.output, now: metadata.at);
    expect(read.release.indexes.length, 1);
    expect(s.io.attempts.single.client.sessions, hasLength(1));
  });
}
