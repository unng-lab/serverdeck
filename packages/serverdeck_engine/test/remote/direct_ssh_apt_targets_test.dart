import 'dart:convert';

import 'package:serverdeck_engine/remote/connections.dart';
import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_engine/remote/direct_ssh_apt_targets.dart';
import 'package:test/test.dart';

import '../support/direct_ssh_byte_peer.dart' show directOutput;
import '../support/schema3_fixture.dart' as fixture;
import 'connection_drain_test.dart' as connection;

const file =
    '/var/lib/apt/lists/ram.example_dists_noble_main_binary-amd64_Packages.lz4';
String target({
  String filename = file,
  String trusted = 'yes',
  String architecture = 'Architecture: amd64\n',
  String metakey = 'main/binary-amd64/Packages',
}) =>
    'MetaKey: $metakey\nFilename: $filename\nIdentifier: Packages\n'
    '${architecture}Trusted: $trusted\nRepo-URI: https://private:secret@ram.example/ubuntu/\n'
    'Base-URI: https://private:secret@ram.example/ubuntu/dists/noble/\n'
    'Sourcesentry: /etc/apt/sources.list.d/ram.sources:1\n'
    'Optional: no\nKeepCompressed: yes\n';

Matcher fails(String code) =>
    throwsA(isA<DirectSshFailure>().having((e) => e.code, 'safe code', code));

void main() {
  test(
    'fixed native discovery resets operational settings and builds only in RAM',
    () {
      final command = DirectSshCommand.aptIndexTargets();
      expect(command.mutates, isFalse);
      expect(command.requiresApply, isFalse);
      expect(command.outputLimit, 8 * 1024 * 1024);
      expect(command.maximumDuration, const Duration(seconds: 30));
      expect(
        command.script,
        contains('/usr/bin/bash --noprofile --norc -o pipefail -c'),
      );
      expect(
        command.script,
        contains(
          'printf %s "\$1" | /usr/bin/timeout 25 /usr/bin/apt-get -c /dev/stdin indextargets "Identifier: Packages"',
        ),
      );
      for (final scope in [
        'APT',
        'Acquire',
        'Binary',
        'Debug',
        'Dir',
        'DPkg',
        'DSelect',
        'OrderList',
        'pkgCacheGen',
        'pkgCacheFile',
        'pkgPolicy',
        'RootDir',
      ]) {
        expect(
          DirectAptTargetsCommand.configuration,
          contains('#clear $scope;'),
        );
      }
      expect(
        DirectAptTargetsCommand.configuration,
        contains('Dir::Cache::pkgcache "";'),
      );
      expect(
        DirectAptTargetsCommand.configuration,
        contains('Dir::Cache::srcpkgcache "";'),
      );
      expect(
        DirectAptTargetsCommand.configuration,
        contains('Debug::NoLocking "true";'),
      );
      expect(
        DirectAptTargetsCommand.configuration,
        contains('pkgCacheFile::Generate "true";'),
      );
      expect(
        DirectAptTargetsCommand.configuration,
        contains('Dir::Etc::preferences "/etc/apt/preferences";'),
      );
      expect(DirectAptTargetsCommand.configuration, isNot(contains("'")));
      for (final path in command.requiredExecutables) {
        expect(
          command.script,
          contains('[ -x $path ] || fail PREREQUISITE_UNAVAILABLE'),
        );
      }
      for (final forbidden in [
        'APT_CONFIG=',
        '<<',
        'mktemp',
        '/usr/bin/tee',
        'apt-get update',
        'apt-get install',
        'apt-get download',
        'serverdeck-executor',
        'python',
      ]) {
        expect(command.script, isNot(contains(forbidden)));
      }
    },
  );

  test('discovery preserves compressed native filenames and private source URI facts', () {
    final targets = DirectAptIndexTarget.capture(
      directOutput({'targets': target()}),
    );
    expect(targets, hasLength(1));
    final row = targets.single;
    expect(row.filename, file);
    expect(row.metaKey, 'main/binary-amd64/Packages');
    expect(row.architecture, 'amd64');
    expect(row.aptTrusted, isTrue);
    expect(row.repositoryUri, contains('private:secret@'));
    expect(row.baseUri, endsWith('/dists/noble/'));
    expect(row.toString(), isNot(contains('secret')));
    expect(() => targets.clear(), throwsUnsupportedError);
    expect(
      DirectAptIndexTarget.capture(directOutput({'targets': ''})),
      isEmpty,
    );
    final flat = DirectAptIndexTarget.capture(
      directOutput({
        'targets': target(
          filename: '/var/lib/apt/lists/ram.example_Packages.gz',
          architecture: '',
          metakey: 'Packages',
          trusted: 'no',
        ),
      }),
    ).single;
    expect(flat.architecture, isNull);
    expect(flat.aptTrusted, isFalse);
  });

  test('untrusted native trust field is represented without inventing qualification', () {
    final row = DirectAptIndexTarget.capture(
      directOutput({'targets': target(trusted: 'no')}),
    ).single;
    expect(row.aptTrusted, isFalse);
    // Trusted yes is permitted for discovery too: source Trusted overrides are
    // not cryptographic verification. This type has no qualified descriptor.
    expect(row.toString(), 'DirectAptIndexTarget');
  });

  test('malformed aliases, duplicate files, traversal, wrong type and URI lines fail closed', () {
    for (final value in [
      '${target()}Filename: $file\n',
      '${target()}\n${target()}',
      target(filename: '/etc/shadow'),
      target(filename: '/var/lib/apt/lists/../Packages'),
      target(filename: '/var/lib/apt/lists/private/Packages'),
      target(metakey: '../Packages'),
      target(metakey: 'main//Packages'),
      target(metakey: 'main/binary-amd64/Contents'),
      target(trusted: 'qualified'),
      target().replaceFirst('Identifier: Packages', 'Identifier: Sources'),
      target().replaceFirst(
        'https://private:secret@ram.example/ubuntu/',
        'not-a-uri/',
      ),
      target().replaceFirst('Repo-URI:', 'Missing-Repo-URI:'),
      target().replaceFirst('Base-URI:', 'Missing-Base-URI:'),
      target().replaceFirst(
        'ram.example/ubuntu/',
        'ram.example/ubuntu/#fragment/',
      ),
      target().replaceFirst('Repo-URI: https:', 'Repo-URI: \n https:'),
    ]) {
      expect(
        () => DirectAptIndexTarget.capture(directOutput({'targets': value})),
        fails('QUALIFICATION_REQUIRED'),
      );
    }
  });

  test('64 index limit is enforced and failed or truncated command is never an empty success', () {
    final rows = [
      for (var i = 0; i < 64; i++)
        target(filename: '/var/lib/apt/lists/ram${i}_Packages.lz4'),
    ].join('\n');
    expect(
      DirectAptIndexTarget.capture(directOutput({'targets': rows})),
      hasLength(64),
    );
    expect(
      () => DirectAptIndexTarget.capture(
        directOutput({'targets': '$rows\n${target()}'}),
      ),
      fails('RESOURCE_LIMIT'),
    );
    final good = directOutput({'targets': target()});
    for (final output in [
      DirectSshOutput(good.bytes, exitCode: null, truncated: false),
      DirectSshOutput(good.bytes, exitCode: 1, truncated: false),
      DirectSshOutput(good.bytes, exitCode: 0, truncated: true),
    ]) {
      expect(
        () => DirectAptIndexTarget.capture(output),
        fails('UNKNOWN_OUTCOME'),
      );
    }
  });

  test(
    'framed native failure cannot turn partial discovery into a success',
    () {
      final partial = directOutput({'targets': target()});
      final failed = DirectSshOutput(
        [
          ...partial.bytes,
          ...ascii.encode('SDSSH_ERROR\tQUALIFICATION_REQUIRED\n'),
        ],
        exitCode: 1,
        truncated: false,
      );
      expect(
        () => DirectAptIndexTarget.capture(failed),
        fails('QUALIFICATION_REQUIRED'),
      );
      expect(
        DirectSshCommand.aptIndexTargets().script,
        contains(r"|| { printf '\n'; fail QUALIFICATION_REQUIRED; }"),
      );
    },
  );

  test(
    'native index discovery traverses the actual existing SSH connection gate',
    () async {
      final s = await connection.Setup.create(), context = await s.context();
      final command = DirectSshCommand.aptIndexTargets();
      s.io.attempts.single.client.onExecute = (session, _) {
        session.onInput = (input) {
          expect(utf8.decode(input), command.script);
          session.output.add(directOutput({'targets': target()}).bytes);
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
      expect(DirectAptIndexTarget.capture(result.output).single.filename, file);
    },
  );
}
