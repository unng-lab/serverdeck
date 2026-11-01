import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_engine/remote/direct_ssh_observations.dart';
import 'package:serverdeck_engine/remote/reads.dart';
import 'package:test/test.dart';

import '../support/direct_ssh_byte_peer.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'connection_drain_test.dart' as connection;
import 'read_clock_test.dart' show Clock;

void main() {
  test('bounded literal file capture preserves controls and rejects overlarge representations', () {
    final target = DirectObservationTarget.capture(
      fixture.parse(fixture.document()),
      fixture.profile,
    );
    final peer = DirectSshBytePeer();
    for (final content in [
      'literal {{ value }}\n\u0000',
      '\ufeffliteral\n',
      '\ufeff\ufeffliteral\n',
      'x' * 65536,
    ]) {
      peer.files['system.motd'] = content;
      final observation = target.parse(
        'system.motd',
        peer.identity,
        directOutput(peer.fileRows('system.motd')),
        DateTime.utc(2026, 11, 1),
      );
      expect(observation.status, 'known');
      expect(
        ((observation.toJson()['value'] as Map)['values'] as Map)['text'],
        content,
      );
    }
    for (final content in ['x' * 65537, '\u0000' * 65536]) {
      peer.files['system.motd'] = content;
      final observation = target.parse(
        'system.motd',
        peer.identity,
        directOutput(peer.fileRows('system.motd')),
        DateTime.utc(2026, 11, 1),
      );
      expect(observation.status, 'incomplete');
      expect(observation.toJson()['value'], isNull);
    }
    for (final text in [
      "max_connections = 0100\nshared_buffers = '128MB'\n",
      "max_connections = 100\nshared_buffers = '0MB'\n",
      "max_connections = 100\nshared_buffers = '128MB'\n\n",
    ]) {
      peer.files['postgresql.settings'] = text;
      expect(
        target
            .parse(
              'postgresql.settings',
              peer.identity,
              directOutput(peer.fileRows('postgresql.settings')),
              DateTime.utc(2026, 11, 1),
            )
            .status,
        'unsupported',
      );
    }
  });

  test('malformed unit properties never become known service evidence', () {
    final target = DirectObservationTarget.capture(
      fixture.parse(fixture.document()),
      fixture.profile,
    );
    final peer = DirectSshBytePeer();
    final original = peer.rows(
      DirectSshCommand.observation('postgresql.service'),
    )['unit']!;
    for (final value in [
      original.replaceFirst('MainPID=1234', 'MainPID=2147483648'),
      original.replaceFirst('MainPID=1234', 'MainPID=01234'),
      original.replaceFirst('ControlPID=0', 'ControlPID=-1'),
      original.replaceFirst(
        'ExecMainStartTimestampMonotonic=1000000',
        'ExecMainStartTimestampMonotonic=9223372036854775808',
      ),
      original + '\nLoadState=loaded',
      original.replaceFirst('UnitFileState=enabled', 'UnitFileState=foreign'),
      original.replaceFirst('LoadState=loaded', 'LoadState=not-found'),
    ]) {
      final observed = target.parse(
        'postgresql.service',
        peer.identity,
        directOutput({'unit': value}),
        DateTime.utc(2026, 11, 1),
      );
      expect(observed.status, isNot('known'));
      expect(observed.toJson()['value'], isNull);
    }
  });
  test(
    'public configuration freshness is recomputed after final native proof',
    () async {
      final s = await connection.Setup.create(),
          context = await s.context(),
          clock = Clock();
      final reads = RemoteReadService(s.connections, clock: clock),
          peer = DirectSshBytePeer();
      addTearDown(reads.close);
      var resourceReplied = false, proofsAfterResource = 0;
      s.io.attempts.single.client.onExecute = (session, command) {
        peer.attach(session, command.operation!);
        final input = session.onInput!;
        session.onInput = (bytes) {
          if (command.operation!.kind == 'observation') resourceReplied = true;
          input(bytes);
        };
      };
      s.runtime.beforeProof = () {
        if (resourceReplied && ++proofsAfterResource == 2)
          clock.elapsed = const Duration(seconds: 20);
      };
      final work = reads.startOwner(context, 'serverdeck_configuration_get', {
        'serverId': fixture.profile,
        'resourceId': 'system.motd',
        'refresh': true,
      });
      final view = await work.result;
      await work.done;
      expect(proofsAfterResource, 2);
      expect((view['observation'] as Map)['status'], 'stale');
    },
  );
  final at = DateTime.parse('2026-11-01T00:00:00.000Z');
  test(
    'all five public observations retain literal data and native target tuple',
    () async {
      final target = DirectObservationTarget.capture(
        fixture.parse(fixture.document()),
        fixture.profile,
      );
      final peer = DirectSshBytePeer();
      for (final resource in [
        'system.motd',
        'postgresql.settings',
        'clickhouse.settings',
        'postgresql.service',
        'clickhouse.service',
      ]) {
        final observed = target.parse(
          resource,
          peer.identity,
          directOutput(peer.rows(DirectSshCommand.observation(resource))),
          at,
        );
        expect(observed.status, 'known');
        expect(observed.serverId, fixture.profile);
        expect(observed.targetRevision, '2');
        expect(observed.connectionRevision, '1');
        expect(observed.trustRevision, '2');
        expect(observed.hostId, peer.hostId);
        expect(observed.isFreshAt(at), isTrue);
        expect(await observed.fingerprint(), hasLength(64));
      }
      final motd = target.parse(
        'system.motd',
        peer.identity,
        directOutput(peer.fileRows('system.motd')),
        at,
      );
      expect((motd.toJson()['value'] as Map)['values'], {
        'text': 'direct metadata\n',
      });
    },
  );

  test(
    'partial, foreign and noncanonical files cannot become a known baseline',
    () {
      final target = DirectObservationTarget.capture(
        fixture.parse(fixture.document()),
        fixture.profile,
      );
      final peer = DirectSshBytePeer(), original = peer.fileRows('system.motd');
      for (final patch in [
        {'digest': ('a' * 64) + '  /etc/motd'},
        {'file': 'truncated'},
        {'afterAttributes': 'different'},
        {'exists': 'false'},
        {
          'attributes': original['attributes']!.replaceFirst(
            '0:0:644',
            '1000:0:644',
          ),
        },
      ]) {
        expect(
          target
              .parse(
                'system.motd',
                peer.identity,
                directOutput({...original, ...patch}),
                at,
              )
              .status,
          isNot('known'),
        );
      }
      peer.files['postgresql.settings'] =
          "max_connections = 100\ninclude 'foreign.conf'\n";
      expect(
        target
            .parse(
              'postgresql.settings',
              peer.identity,
              directOutput(peer.fileRows('postgresql.settings')),
              at,
            )
            .status,
        'unsupported',
      );
      peer.files['system.motd'] = null;
      final absent = target.parse(
        'system.motd',
        peer.identity,
        directOutput(peer.fileRows('system.motd')),
        at,
      );
      expect(absent.status, 'known');
      expect((absent.toJson()['value'] as Map)['exists'], isFalse);
    },
  );
}
