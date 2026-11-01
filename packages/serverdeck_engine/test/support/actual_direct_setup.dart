import 'package:serverdeck_engine/platform/ports.dart';
import 'package:test/test.dart';

import '../automation/portable_program_test.dart' show motdBody;
import '../storage/actual_state_store_test.dart' as repository;
import 'actual_mcp_setup.dart';
import 'direct_host_byte_peer.dart';
import 'schema3_fixture.dart' as fixture;
import '../remote/ssh_io_policy_test.dart' as bytes;
import '../mcp/actual_router_executor_test.dart' as positive;

/// Actual application composition with RAM SSH bytes, without an executor
/// release, enrollment or framed helper. Domain methods are not substituted.
Future<(Setup, DirectHostBytePeer, Client, String)> directReady({
  EngineClock? readClock,
  int profileRequest = 3300,
  int lifetimeSeconds = 300,
}) async {
  final peer = DirectHostBytePeer();
  final s = await Setup.create(direct: peer.attach, readClock: readClock);
  // Owner automation owns its own connection attachment; an MCP attachment
  // never grants the owner a borrowed connection identity.
  var owner = await s.ownerCall('servers.connect', {
    'profileId': fixture.profile,
  });
  final operation = owner['operationId'];
  for (var i = 0; owner['state'] == 'running' && i < 100; i++) {
    await Future<void>.delayed(Duration.zero);
    owner = await s.ownerCall('servers.connectStatus', {
      'operationId': operation,
    });
  }
  expect(owner['state'], 'succeeded');
  final client = await s.client(
    await s.grant(lifetimeSeconds: lifetimeSeconds),
  );
  success(
    await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
  );
  final profile =
      success(
            await s.tool(client, 'profiles_create', {
              'requestId': repository.id(profileRequest),
              'name': 'direct authority profile',
              'body': motdBody(),
            }),
          )['profileId']
          as String;
  expect(await s.store.readExecutorEnrollments(), isEmpty);
  return (s, peer, client, profile);
}

void noDirectEffect(DirectHostBytePeer peer) {
  expect((peer.launches, peer.effects), (0, 0));
  expect(peer.requests.where((command) => command.kind == 'launch'), isEmpty);
  expect(peer.records['intent'], isNull);
  expect(peer.reads.files['system.motd'], 'direct metadata\n');
}

/// A lost launch ACK separates logical failure from native channel settlement.
/// Only the raw SSH channel's completion is held; actual job/control code runs.
final class DirectHeld {
  DirectHeld(
    this.s,
    this.peer,
    this.client,
    this.profile,
    this.job,
    this.session,
  );
  final Setup s;
  final DirectHostBytePeer peer;
  final Client client;
  final String profile, job;
  final bytes.Session session;
  static Future<DirectHeld> create({EngineClock? clock}) async {
    final (s, peer, client, profile) = await directReady(readClock: clock);
    bytes.Session? held;
    addTearDown(() async {
      if (held != null && !held!.finishing) await held!.finish();
    });
    peer.stopBeforeStart = true;
    peer.dropLaunchAck = true;
    peer.beforeReply = (command, session) async {
      if (command.kind == 'launch') {
        session.autoClose = false;
        held = session;
      }
    };
    final plan = await positive.plan(s, client, profile, 3600);
    await positive.approve(s, client, plan, 3601);
    final admitted = success(
      await s.tool(client, 'apply', {
        'requestId': repository.id(3602),
        'planId': plan['planId'],
      }),
    );
    final job = admitted['jobId'] as String;
    await positive.waitJob(s, client, job, 'unknown');
    expect(held, isNotNull);
    expect(held!.closes, greaterThan(0));
    expect((peer.launches, peer.effects), (1, 0));
    return DirectHeld(s, peer, client, profile, job, held!);
  }
}
