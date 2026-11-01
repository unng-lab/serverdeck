import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:test/test.dart';

import '../remote/ssh_io_policy_test.dart' as bytes;

String bytesHash(String value) => const DartSha256()
    .hashSync(utf8.encode(value))
    .bytes
    .map((value) => value.toRadixString(16).padLeft(2, '0'))
    .join();
DirectSshOutput directOutput(Map<String, String> rows) => DirectSshOutput(
  ascii.encode(
    rows.entries
        .map(
          (entry) =>
              entry.key + '\t' + base64.encode(utf8.encode(entry.value)) + '\n',
        )
        .join(),
  ),
  exitCode: 0,
  truncated: false,
);

/// Raw RAM OS facts only. Real collectors, parsers, target/scope checks and
/// API run unchanged. No record/qualification/plan/result success is stubbed.
final class DirectSshBytePeer {
  DirectSshBytePeer({this.motd});
  final String Function()? motd;
  final files = <String, String?>{
    'system.motd': 'direct metadata\n',
    'postgresql.settings': "max_connections = 100\nshared_buffers = '128MB'\n",
    'clickhouse.settings':
        '<clickhouse>\n  <max_connections>4096</max_connections>\n'
        '  <max_server_memory_usage>1073741824</max_server_memory_usage>\n</clickhouse>\n',
  };
  final requests = <DirectSshCommand>[];
  final inspectRows = <String, String>{
    'machine': '123456789abcdef0123456789abcdef0',
    'boot': '12345678-1234-4234-9234-123456789abc',
    'uptime': '1000.00 0.00',
    'os': 'ID=ubuntu\nVERSION_ID="24.04"',
    'architecture': 'x86_64',
    'init': 'systemd',
    'uid': '0',
  };
  String? error;
  Future<void> Function(DirectSshCommand)? beforeOutput;
  Map<String, String> Function(DirectSshCommand, Map<String, String>)?
  alterRows;
  final missingExecutables = <String>{};
  String? afterAttributes;
  String packages =
      'base-files\tamd64\t13ubuntu10\tinstalled\nnetbird\tamd64\t0.35.0\tinstalled';
  DirectSshIdentity get identity => DirectSshIdentity.capture(inspectRows);
  String get hostId => identity.hostId;

  Map<String, String> fileRows(String resource) {
    final content = resource == 'system.motd'
        ? motd?.call() ?? files[resource]
        : files[resource];
    if (content == null)
      return {
        'exists': 'false',
        'attributes': 'absent',
        'afterAttributes': 'absent',
        'digest': 'absent',
        'file': '',
      };
    final path = switch (resource) {
      'system.motd' => '/etc/motd',
      'postgresql.settings' => '/etc/postgresql/16/main/conf.d/serverdeck.conf',
      'clickhouse.settings' => '/etc/clickhouse-server/config.d/serverdeck.xml',
      _ => throw StateError('UNDECLARED_RAM_FILE'),
    };
    final owner = resource == 'postgresql.settings' ? '0:115:640' : '0:0:644';
    final attributes =
        owner +
        ':1:' +
        utf8.encode(content).length.toString() +
        ':11:123:'
            '2026-11-01 00:00:00.000000000 +0000:2026-11-01 00:00:00.000000000 +0000';
    return {
      'exists': 'true',
      'attributes': attributes,
      'afterAttributes': afterAttributes ?? attributes,
      'digest': bytesHash(content) + '  ' + path,
      'file': content + '\nSDSSH_FILE_COMPLETE_V1\n',
    };
  }

  Map<String, String> rows(DirectSshCommand command) {
    if (command.kind == 'inspect') return {...inspectRows};
    if (command.kind == 'packages') return {'packages': packages};
    if (command.kind != 'observation')
      throw StateError('UNDECLARED_RAM_COMMAND');
    final resource = command.resourceId!;
    if (!resource.endsWith('.service')) return fileRows(resource);
    final unit = resource == 'postgresql.service'
        ? 'postgresql@16-main.service'
        : 'clickhouse-server.service';
    return {
      'unit':
          'LoadState=loaded\nActiveState=active\nUnitFileState=enabled\n'
          'MainPID=1234\nControlPID=0\nExecMainStartTimestampMonotonic=1000000\n'
          'ControlGroup=/system.slice/$unit\nFragmentPath=/usr/lib/systemd/system/$unit',
    };
  }

  void attach(bytes.Session session, DirectSshCommand command) {
    expect(command.mutates, isFalse);
    requests.add(command);
    session.onInput = (input) async {
      expect(utf8.decode(input), command.script);
      if (beforeOutput case final before?) await before(command);
      if (session.output.isClosed) return;
      // RAM executable facts at the byte boundary; inspect actual emitted guards
      // rather than substituting an observation or collector result.
      final missing = missingExecutables.any(
        (path) => command.script.contains(
          '[ -x ' + path + ' ] || fail PREREQUISITE_UNAVAILABLE\n',
        ),
      );
      final failure = error ?? (missing ? 'PREREQUISITE_UNAVAILABLE' : null);
      if (failure case final code?) {
        session.exitCode = 1;
        session.output.add(
          Uint8List.fromList(ascii.encode('SDSSH_ERROR\t$code\n')),
        );
      } else {
        final facts = rows(command);
        session.output.add(
          directOutput(alterRows?.call(command, facts) ?? facts).bytes,
        );
      }
      session.finish().ignore();
    };
  }
}
