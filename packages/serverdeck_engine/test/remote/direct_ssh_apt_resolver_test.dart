import 'dart:convert';

import 'package:serverdeck_engine/remote/connections.dart';
import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_engine/remote/direct_ssh_apt_index.dart';
import 'package:serverdeck_engine/remote/direct_ssh_apt_resolver.dart';
import 'package:serverdeck_engine/remote/direct_ssh_packages.dart';
import 'package:test/test.dart';

import '../support/direct_ssh_byte_peer.dart' show directOutput;
import '../support/schema3_fixture.dart' as fixture;
import 'connection_drain_test.dart' as connection;

const version = '16.15-0ubuntu0.24.04.1';
const packages =
    'base-files\tamd64\t13ubuntu10\tinstalled\nnetbird\tamd64\t0.35.0\tinstalled';
const selections = 'base-files\tinstall\nnetbird\tinstall';
DirectPackageSnapshot baseline([String raw = packages]) =>
    DirectPackageSnapshot.captureText(raw);
DirectAptPolicy policy([String raw = 'noble-updates\n']) =>
    DirectAptPolicy.capture(directOutput({'policy': raw}));
List<DirectAptPackageKey> roots() => [
  DirectAptPackageKey('postgresql-16', 'amd64', version),
  DirectAptPackageKey('postgresql-client-16', 'amd64', version),
];
List<DirectAptPackageKey> closure() => [
  ...roots(),
  DirectAptPackageKey('postgresql-common', 'all', '249'),
];
String operation(String kind, DirectAptPackageKey p) =>
    '$kind ${p.name} (${p.version} RAM:24.04/noble-updates [${p.architecture}])\n';
String transcript([List<DirectAptPackageKey>? keys]) => [
  for (final p in keys ?? closure()) operation('Inst', p),
  for (final p in keys ?? closure()) operation('Conf', p),
].join();
DirectAptResolveRequest request() => DirectAptResolveRequest(roots(), policy());
Map<String, String> facts() => {
  'beforePackages': packages,
  'afterPackages': packages,
  'beforeSelections': selections,
  'afterSelections': selections,
  'beforePolicy': 'noble-updates\n',
  'afterPolicy': 'noble-updates\n',
  'simulation': transcript(),
};
Matcher fails([String code = 'QUALIFICATION_REQUIRED']) =>
    throwsA(isA<DirectSshFailure>().having((e) => e.code, 'safe code', code));

void main() {
  test('effective policy remains literal bounded data including regex metacharacters', () {
    expect(policy('').defaultRelease, isNull);
    expect(policy('\n').defaultRelease, isNull);
    expect(policy('').digest, isNot(policy('\n').digest));
    const value = r'''noble';$(never)"/^.*$/''';
    final captured = policy('$value\n');
    expect(captured.defaultRelease, value);
    expect(captured.toString(), isNot(contains('never')));
    final script = DirectSshCommand.aptResolve(
      DirectAptResolveRequest(roots(), captured),
    ).script;
    expect(script, isNot(contains(value)));
    expect(script, contains(base64.encode(utf8.encode(value))));
    expect(script, isNot(contains('eval ')));
    for (final raw in [
      'missing-newline',
      'one\ntwo\n',
      'bad\u0000\n',
      'bad\u007f\n',
    ]) {
      expect(() => policy(raw), fails());
    }
    expect(() => policy('x' * 1025), fails('RESOURCE_LIMIT'));
  });

  test('native policy and simulation are finite read-only calls with fixed operational reset', () {
    final probe = DirectSshCommand.aptPolicy(),
        solve = DirectSshCommand.aptResolve(request());
    expect(probe.script, contains('exec -a apt-get /usr/bin/apt-config'));
    expect(probe.script, contains('--format %v%n dump APT::Default-Release'));
    expect(probe.script, isNot(contains('#clear APT;')));
    for (final command in [probe, solve]) {
      expect(command.mutates, isFalse);
      expect(command.requiresApply, isFalse);
      expect(
        command.script,
        contains('/usr/bin/bash --noprofile --norc -o pipefail -c'),
      );
      for (final executable in command.requiredExecutables) {
        expect(
          command.script,
          contains('[ -x $executable ] || fail PREREQUISITE_UNAVAILABLE'),
        );
      }
      for (final forbidden in [
        'serverdeck-executor',
        'python',
        'eval ',
        'mktemp',
        'apt-get update',
        'apt-get download',
        '/usr/bin/tee',
      ]) {
        expect(command.script, isNot(contains(forbidden)));
      }
    }
    expect(solve.outputLimit, 8 * 1024 * 1024);
    expect(
      solve.script,
      contains(
        '--simulate --quiet=2 --assume-yes --no-remove --no-upgrade --no-install-recommends --no-install-suggests',
      ),
    );
    expect(solve.script, contains('#clear AptCli;'));
    expect(solve.script, contains("'postgresql-16:amd64=$version'"));
    expect(solve.script, contains(r'--get-selections'));
    expect(
      solve.script,
      contains(r'[ "$beforePolicy" = "$expectedPolicy" ] || fail PLAN_STALE'),
    );
    expect(
      solve.script,
      contains(r'[ "$beforePolicy" = "$afterPolicy" ] || fail PLAN_STALE'),
    );
  });

  test('request roots are captured once and cannot select NetBird or duplicate packages', () {
    final values = roots(),
        captured = DirectAptResolveRequest(roots(), policy());
    final fromValues = DirectAptResolveRequest(values, policy());
    values.clear();
    expect(fromValues.roots, hasLength(2));
    expect(() => captured.roots.clear(), throwsUnsupportedError);
    for (final values in [
      <DirectAptPackageKey>[],
      [roots().first, roots().first],
      [DirectAptPackageKey('netbird', 'amd64', '1')],
      [DirectAptPackageKey('netbird-client', 'amd64', '1')],
    ]) {
      expect(() => DirectAptResolveRequest(values, policy()), fails());
    }
    expect(
      () => DirectAptResolveRequest([
        for (var i = 0; i < 257; i++)
          DirectAptPackageKey('pkg$i', 'amd64', '1'),
      ], policy()),
      fails('RESOURCE_LIMIT'),
    );
  });

  test('complete install/configure closure binds unchanged packages, selections and policy', () {
    final resolved = request().capture(
      directOutput(facts()),
      baseline: baseline(),
    );
    expect(
      resolved.additions.map((p) => p.identity).toSet(),
      closure().map((p) => p.identity).toSet(),
    );
    expect(resolved.packagesDigest, baseline().digest);
    expect(resolved.policyDigest, policy().digest);
    expect(resolved.selectionsDigest, hasLength(64));
    expect(() => resolved.additions.clear(), throwsUnsupportedError);
    expect(resolved.toString(), isNot(contains('RAM')));
    final reordered = request().capture(
      directOutput({
        ...facts(),
        'afterPackages': packages.split('\n').reversed.join('\n'),
        'afterSelections': 'netbird  install\nbase-files\tinstall',
      }),
      baseline: baseline(),
    );
    expect(reordered.selectionsDigest, resolved.selectionsDigest);
  });

  test('upgrades removals configure-only partial and unsolicited versions are refused', () {
    for (final raw in [
      transcript().replaceFirst(
        'Inst postgresql-16 (',
        'Inst postgresql-16 [16.14] (',
      ),
      'Remv netbird [0.35.0]\n${transcript()}',
      'Purg old-package [1]\n${transcript()}',
      operation('Conf', roots().first) + transcript(),
      transcript().replaceFirst(operation('Conf', roots().first), ''),
      transcript() + operation('Conf', roots().first),
      transcript() + operation('Inst', roots().first),
      transcript().replaceAll('postgresql-client-16', 'unrequested-root'),
      transcript().replaceAll(version, '16.14'),
      transcript().replaceAll('[amd64]', '[arm64]'),
      transcript().replaceFirst(
        'Inst postgresql-16 (',
        'Inst postgresql-16:all (',
      ),
      transcript().replaceFirst('RAM:24.04', 'RAM\u0000:24.04'),
      'Reading package lists...\n${transcript()}',
      transcript().substring(0, transcript().length - 1),
      '',
    ]) {
      expect(
        () => request().capture(
          directOutput({...facts(), 'simulation': raw}),
          baseline: baseline(),
        ),
        fails(),
      );
    }
  });

  test('held packages, installed/configuration neighbors and NetBird additions cannot enter closure', () {
    final held = '$selections\npostgresql-common\thold';
    expect(
      () => request().capture(
        directOutput({
          ...facts(),
          'beforeSelections': held,
          'afterSelections': held,
        }),
        baseline: baseline(),
      ),
      fails(),
    );
    for (final name in ['base-files', 'netbird', 'netbird-new-client']) {
      final added = DirectAptPackageKey(name, 'amd64', '1');
      expect(
        () => request().capture(
          directOutput({
            ...facts(),
            'simulation': transcript([...closure(), added]),
          }),
          baseline: baseline(),
        ),
        fails(),
      );
    }
    for (final state in ['installed', 'config-files']) {
      final current = '$packages\npostgresql-common\tall\t249\t$state';
      final selected = '$selections\npostgresql-common\tinstall';
      expect(
        () => request().capture(
          directOutput({
            ...facts(),
            'beforePackages': current,
            'afterPackages': current,
            'beforeSelections': selected,
            'afterSelections': selected,
          }),
          baseline: baseline(current),
        ),
        fails(),
      );
    }
  });

  test('before/after changes invalidate resolution and incomplete selection data fails closed', () {
    for (final changed in [
      {
        ...facts(),
        'beforePackages': packages.replaceFirst('13ubuntu10', '13ubuntu11'),
      },
      {
        ...facts(),
        'afterPackages': packages.replaceFirst('13ubuntu10', '13ubuntu11'),
      },
      {...facts(), 'afterPolicy': 'noble\n'},
      {...facts(), 'beforePolicy': 'noble\n'},
      {...facts(), 'afterSelections': '$selections\nfuture-pkg\thold'},
    ]) {
      expect(
        () => request().capture(directOutput(changed), baseline: baseline()),
        fails('PLAN_STALE'),
      );
    }
    for (final raw in [
      '',
      'base-files\tinstall',
      '$selections\nbase-files:amd64\thold',
      '$selections\nunknown-pkg\tunknown',
      '$selections\nmalformed',
    ]) {
      expect(
        () => request().capture(
          directOutput({
            ...facts(),
            'beforeSelections': raw,
            'afterSelections': raw,
          }),
          baseline: baseline(),
        ),
        fails(),
      );
    }
  });

  test(
    '256 additions fit, next addition fails before any descriptor is published',
    () {
      final maximum = [
        ...roots(),
        for (var i = 0; i < 254; i++)
          DirectAptPackageKey('pkg$i', 'amd64', '1'),
      ];
      expect(
        request()
            .capture(
              directOutput({...facts(), 'simulation': transcript(maximum)}),
              baseline: baseline(),
            )
            .additions,
        hasLength(256),
      );
      expect(
        () => request().capture(
          directOutput({
            ...facts(),
            'simulation': transcript([
              ...maximum,
              DirectAptPackageKey('overflow', 'amd64', '1'),
            ]),
          }),
          baseline: baseline(),
        ),
        fails('RESOURCE_LIMIT'),
      );
    },
  );

  test('native failure, ACK loss and omitted final proof never become a resolved transaction', () {
    final good = directOutput(facts());
    for (final output in [
      DirectSshOutput(good.bytes, exitCode: null, truncated: false),
      DirectSshOutput(good.bytes, exitCode: 0, truncated: true),
      directOutput({...facts()}..remove('afterPolicy')),
    ]) {
      expect(
        () => request().capture(output, baseline: baseline()),
        fails('UNKNOWN_OUTCOME'),
      );
    }
    final failed = DirectSshOutput(
      [
        ...directOutput({'simulation': transcript()}).bytes,
        ...ascii.encode('SDSSH_ERROR\tQUALIFICATION_REQUIRED\n'),
      ],
      exitCode: 1,
      truncated: false,
    );
    expect(() => request().capture(failed, baseline: baseline()), fails());
  });

  test(
    'policy and resolver run through the actual owned SSH/native gate',
    () async {
      final s = await connection.Setup.create(), context = await s.context();
      for (final command in [
        DirectSshCommand.aptPolicy(),
        DirectSshCommand.aptResolve(request()),
      ]) {
        s.io.attempts.single.client.onExecute = (session, _) {
          session.onInput = (input) {
            expect(utf8.decode(input), command.script);
            session.output.add(
              directOutput(
                command.kind == 'apt-policy'
                    ? {'policy': 'noble-updates\n'}
                    : facts(),
              ).bytes,
            );
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
        if (command.kind == 'apt-policy') {
          expect(
            DirectAptPolicy.capture(result.output).defaultRelease,
            'noble-updates',
          );
        } else {
          expect(
            request().capture(result.output, baseline: baseline()).additions,
            hasLength(3),
          );
        }
      }
    },
  );
}
