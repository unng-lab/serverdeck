import 'dart:convert';

import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_engine/remote/direct_ssh_packages.dart';
import 'package:test/test.dart';

import '../support/direct_ssh_byte_peer.dart';

void main() {
  test(
    'package snapshot sorts actual rows and binds protected package versions',
    () {
      DirectPackageSnapshot capture(String source) =>
          DirectPackageSnapshot.capture(directOutput({'packages': source}));
      final first = capture(
        'zlib1g:amd64\tamd64\t1:1.3.dfsg-3.1ubuntu2\tinstalled\nnetbird\tamd64\t0.35.0\tinstalled',
      );
      final reordered = capture(
        'netbird\tamd64\t0.35.0\tinstalled\nzlib1g:amd64\tamd64\t1:1.3.dfsg-3.1ubuntu2\tinstalled',
      );
      expect(first.digest, reordered.digest);
      expect(first.netbirdDigest, reordered.netbirdDigest);
      final changed = capture(
        'netbird\tamd64\t0.36.0\tinstalled\nzlib1g:amd64\tamd64\t1:1.3.dfsg-3.1ubuntu2\tinstalled',
      );
      expect(changed.digest, isNot(first.digest));
      expect(changed.netbirdDigest, isNot(first.netbirdDigest));
      expect(first.toString(), isNot(contains('netbird')));
      expect(
        capture('removed-package\t\t\tnot-installed').digest,
        hasLength(64),
      );
    },
  );
  test('empty partial malformed duplicate or unsettled packages never prove preflight', () {
    for (final source in [
      '',
      'base-files\tamd64\t1\thalf-configured',
      'base-files\tamd64\t1\tinstalled\n',
      'base-files\tamd64\t1',
      'base-files\tamd64\t1\tinstalled\nbase-files\tamd64\t2\tinstalled',
      'base-files\tamd64\t1\tinstalled\nbase-files:amd64\tamd64\t1\tinstalled',
      'base-files:arm64\tamd64\t1\tinstalled',
      '../unsafe\tamd64\t1\tinstalled',
      'base-files\tamd64\tbad value\tinstalled',
    ]) {
      expect(
        () => DirectPackageSnapshot.capture(directOutput({'packages': source})),
        throwsA(isA<DirectSshFailure>()),
      );
    }
    expect(
      () => DirectPackageSnapshot.capture(
        DirectSshOutput(
          ascii.encode('packages\t!!!!\n'),
          exitCode: 0,
          truncated: false,
        ),
      ),
      throwsA(isA<DirectSshFailure>()),
    );
    expect(
      () => DirectPackageSnapshot.capture(
        DirectSshOutput([], exitCode: 0, truncated: true),
      ),
      throwsA(isA<DirectSshFailure>()),
    );
    final many = List.generate(
      16385,
      (i) => 'package-' + i.toString() + '\tamd64\t1\tinstalled',
    ).join('\n');
    expect(
      () => DirectPackageSnapshot.capture(directOutput({'packages': many})),
      throwsA(
        isA<DirectSshFailure>().having((e) => e.code, 'code', 'RESOURCE_LIMIT'),
      ),
    );
  });
  test('closed package command requires only factual dpkg read tools', () {
    final command = DirectSshCommand.packages();
    expect(command.mutates, isFalse);
    expect(command.outputLimit, 8 * 1024 * 1024);
    expect(command.requiredExecutables.toSet(), {
      '/usr/bin/base64',
      '/usr/bin/dpkg-query',
    });
    expect(command.script, contains(r'-f=${binary:Package}'));
    expect(command.script, isNot(contains('apt-get')));
    expect(command.script, isNot(contains('systemd-run')));
  });
}
