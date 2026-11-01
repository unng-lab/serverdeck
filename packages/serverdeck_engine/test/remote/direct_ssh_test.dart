import 'dart:convert';
import 'dart:typed_data';

import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:test/test.dart';

Map<String, String> probe({
  String boot = '12345678-1234-1234-1234-123456789abc',
}) => {
  'machine': '0123456789abcdef0123456789abcdef',
  'boot': boot,
  'uptime': '1234.56 2468.00',
  'os': 'ID=ubuntu\nVERSION_ID="24.04"\n',
  'architecture': 'x86_64',
  'init': 'systemd',
  'uid': '0',
};

Uint8List rows(Map<String, String> fields) => Uint8List.fromList(
  utf8.encode(
    fields.entries
        .map(
          (entry) =>
              '${entry.key}\t${base64.encode(utf8.encode(entry.value))}\n',
        )
        .join(),
  ),
);

Matcher fails(String code) => throwsA(
  isA<DirectSshFailure>().having((error) => error.code, 'safe code', code),
);

void main() {
  test('identity requires only tools actually used to collect identity', () {
    final command = DirectSshCommand.inspect();
    expect(command.requiredExecutables.toSet(), {
      '/usr/bin/base64',
      '/usr/bin/id',
      '/usr/bin/cat',
      '/usr/bin/uname',
    });
    for (final path in command.requiredExecutables) {
      expect(
        command.script,
        contains('[ -x ' + path + ' ] || fail PREREQUISITE_UNAVAILABLE\n'),
      );
    }
  });

  test(
    'every observation guards framing and native tools before any data row',
    () {
      for (final resource in [
        'system.motd',
        'postgresql.settings',
        'clickhouse.settings',
        'postgresql.service',
        'clickhouse.service',
      ]) {
        final command = DirectSshCommand.observation(resource);
        final expected = resource.endsWith('.service')
            ? {'/usr/bin/base64', '/usr/bin/systemctl'}
            : {
                '/usr/bin/base64',
                '/usr/bin/stat',
                '/usr/bin/sha256sum',
                '/usr/bin/dd',
                '/usr/bin/timeout',
              };
        expect(command.requiredExecutables.toSet(), expected);
        final body = command.script.indexOf(
          resource.endsWith('.service') ? '\nemit unit ' : '\nfile=',
        );
        expect(body, greaterThan(0));
        for (final executable in expected) {
          final guard = command.script.indexOf(
            '[ -x ' + executable + ' ] || fail PREREQUISITE_UNAVAILABLE\n',
          );
          expect(guard, greaterThanOrEqualTo(0));
          expect(guard, lessThan(body));
        }
        expect(
          () => command.requiredExecutables.add('/untrusted/tool'),
          throwsUnsupportedError,
        );
        expect(command.script, isNot(contains('/usr/bin/printf')));
      }
    },
  );

  test(
    'identity rejects oversized decimal evidence before numeric conversion',
    () {
      expect(
        () => DirectSshIdentity.capture({
          ...probe(),
          'uptime': '9' * (1024 * 1024) + '.00 0.00',
        }),
        fails('RESOURCE_LIMIT'),
      );
      expect(
        () => DirectSshIdentity.capture({
          ...probe(),
          'uptime': '0' * 100 + '.00 0.00',
        }),
        fails('PREREQUISITE_UNAVAILABLE'),
      );
      final edge = DirectSshIdentity.capture({
        ...probe(),
        'uptime': '9223372036854775.807 0.00',
      });
      expect(edge.uptimeMs, 9223372036854775807);
      expect(
        () => DirectSshIdentity.capture({
          ...probe(),
          'uptime': '9223372036854775.808 0.00',
        }),
        fails('RESOURCE_LIMIT'),
      );
      expect(
        () => DirectSshIdentity.capture({...probe(), 'os': 'x' * 16385}),
        fails('RESOURCE_LIMIT'),
      );
    },
  );

  test(
    'partial prerequisite failures remain safe failures, never partial success',
    () {
      final all = probe().entries.toList();
      for (var count = 0; count < all.length; count++) {
        final partial = rows(Map.fromEntries(all.take(count)));
        final bytes = Uint8List.fromList([
          ...partial,
          ...ascii.encode('SDSSH_ERROR\tPREREQUISITE_UNAVAILABLE\n'),
        ]);
        final output = DirectSshOutput(bytes, exitCode: 1, truncated: false);
        expect(
          () => output.textRows(DirectSshIdentity.fields),
          fails('PREREQUISITE_UNAVAILABLE'),
        );
        expect(
          () => DirectSshOutput(
            bytes,
            exitCode: 0,
            truncated: false,
          ).textRows(DirectSshIdentity.fields),
          fails('UNKNOWN_OUTCOME'),
        );
      }
      for (final source in [
        'machine\t!!!!\nSDSSH_ERROR\tFORBIDDEN\n',
        'SDSSH_ERROR\tFORBIDDEN\nmachine\tdmFsdWU=\n',
        'SDSSH_ERROR\tFORBIDDEN\nSDSSH_ERROR\tFORBIDDEN\n',
        'machine\tdmFsdWU=\nmachine\tdmFsdWU=\nSDSSH_ERROR\tFORBIDDEN\n',
      ]) {
        expect(
          () => DirectSshOutput(
            ascii.encode(source),
            exitCode: 1,
            truncated: false,
          ).textRows(DirectSshIdentity.fields),
          fails('UNKNOWN_OUTCOME'),
        );
      }
    },
  );

  test(
    'identity binds a private application-specific host and current boot',
    () {
      final first = DirectSshIdentity.capture(probe());
      final again = DirectSshIdentity.capture(probe());
      final reboot = DirectSshIdentity.capture(
        probe(boot: '22345678-1234-1234-1234-123456789abc'),
      );
      expect(first.hostId, again.hostId);
      expect(
        first.hostId,
        matches(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ),
      );
      expect(reboot.hostId, first.hostId);
      expect(reboot.bootIdHash, isNot(first.bootIdHash));
      expect(first.uptimeMs, 1234560);
      expect(first.toString(), isNot(contains(probe()['machine']!)));
      expect(first.toString(), isNot(contains(probe()['boot']!)));
    },
  );

  test(
    'identity refuses unknown, missing and malformed prerequisite evidence',
    () {
      for (final mutation in <Map<String, String>>[
        {...probe()}..remove('boot'),
        {...probe(), 'machine': 'uninitialized'},
        {...probe(), 'machine': '00000000000000000000000000000000'},
        {...probe(), 'boot': '../unexpected'},
        {...probe(), 'uptime': '-1.0 0.0'},
        {...probe(), 'uptime': 'NaN 0.0'},
        {...probe(), 'uid': '1000'},
        {...probe(), 'architecture': 'aarch64'},
        {...probe(), 'init': 'other'},
        {...probe(), 'os': 'ID=ubuntu\nVERSION_ID="22.04"'},
        {...probe(), 'os': 'ID=ubuntu\nID=other\nVERSION_ID="24.04"'},
        {...probe(), 'unexpected': 'value'},
      ]) {
        expect(
          () => DirectSshIdentity.capture(mutation),
          throwsA(isA<DirectSshFailure>()),
        );
      }
    },
  );

  test('closed command factories reject paths and shell as resource input', () {
    for (final resource in [
      'system.motd; touch /tmp/forbidden',
      '/etc/motd',
      'postgresql.service\nreboot',
      'arbitrary.resource',
    ]) {
      expect(() => DirectSshCommand.observation(resource), fails('VALIDATION'));
    }
    final inspection = DirectSshCommand.inspect();
    final motd = DirectSshCommand.observation('system.motd');
    expect(inspection.mutates, isFalse);
    expect(motd.mutates, isFalse);
    expect(inspection.privileged, isTrue);
    for (final command in [inspection, motd]) {
      expect(command.script, contains('LC_ALL=C'));
      expect(command.script, isNot(contains('serverdeck-executor')));
      expect(command.script, isNot(contains('ansible')));
      expect(command.script, isNot(contains('python')));
      expect(command.script, isNot(contains('mkdir')));
      expect(command.script, isNot(contains('eval ')));
      expect(command.toString(), isNot(contains(command.script)));
    }
  });

  test(
    'framed UTF8 preserves byte order marks as literal file/payload bytes',
    () {
      for (final value in [
        '',
        'text',
        '\ufefftext',
        '\ufeff\ufefftext',
        '\ufeff',
        'inner\ufefftext',
        'текст',
      ]) {
        final captured = DirectSshOutput(
          rows({'text': value}),
          exitCode: 0,
          truncated: false,
        ).textRows({'text'})['text']!;
        expect(utf8.encode(captured), utf8.encode(value));
      }
    },
  );

  test('output is copied and exact bounded rows preserve literal data', () {
    final input = rows({'text': 'literal \u0000\u001b ${r'$(never)'}\n'});
    final output = DirectSshOutput(input, exitCode: 0, truncated: false);
    input.fillRange(0, input.length, 0);
    expect(
      output.textRows({'text'})['text'],
      'literal \u0000\u001b ${r'$(never)'}\n',
    );
    expect(() => output.bytes[0] = 0, throwsUnsupportedError);
    expect(output.toString(), isNot(contains('never')));
  });

  test(
    'malformed or incomplete output never becomes successful empty data',
    () {
      for (final input in <Uint8List>[
        Uint8List.fromList(utf8.encode('text\tdGV4dA==')),
        Uint8List.fromList(utf8.encode('text\t!!!!\n')),
        Uint8List.fromList(utf8.encode('text\tdGV4dA==\ntext\tdGV4dA==\n')),
        rows({'other': 'wrong source'}),
        Uint8List.fromList([0xff, 0x0a]),
        Uint8List(0),
      ]) {
        expect(
          () => DirectSshOutput(
            input,
            exitCode: 0,
            truncated: false,
          ).textRows({'text'}),
          fails('UNKNOWN_OUTCOME'),
        );
      }
      expect(
        () => DirectSshOutput(
          rows({'text': 'partial'}),
          exitCode: 0,
          truncated: true,
        ).textRows({'text'}),
        fails('UNKNOWN_OUTCOME'),
      );
      expect(
        () => DirectSshOutput(
          rows({'text': 'lost exit'}),
          exitCode: null,
          truncated: false,
        ).textRows({'text'}),
        fails('UNKNOWN_OUTCOME'),
      );
    },
  );

  test('remote diagnostics are restricted to fixed safe categories', () {
    final denied = DirectSshOutput(
      Uint8List.fromList(utf8.encode('SDSSH_ERROR\tFORBIDDEN\n')),
      exitCode: 1,
      truncated: false,
    );
    expect(() => denied.textRows({'text'}), fails('FORBIDDEN'));
    final untrusted = DirectSshOutput(
      Uint8List.fromList(utf8.encode('SDSSH_ERROR\tsecret-private-value\n')),
      exitCode: 1,
      truncated: false,
    );
    expect(() => untrusted.textRows({'text'}), fails('UNKNOWN_OUTCOME'));
  });
}
