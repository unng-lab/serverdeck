import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/api/operational_channel.dart';
import 'package:serverdeck_locald/api/operational_server.dart';
import 'package:serverdeck_locald/api/owner_foundation.dart';
import 'package:serverdeck_locald/api/owner_grants.dart';
import 'package:serverdeck_locald/api/owner_service_probe.dart';
import 'package:serverdeck_locald/mcp/router.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'operational_auth_actor.dart' as a;
import 'operational_grant_actor.dart' as g;
import 'operational_channel_actor.dart' as wire;

String id(int value) =>
    '62345678-1234-4234-8234-${value.toString().padLeft(12, '0')}';
Map<String, Object?> settings(String revision) => {
  'expectedRevision': revision,
  'theme': 'dark',
  'reduceMotion': true,
  'selectedProfileId': null,
};
Map<String, Object?> profile() => {
  'profileId': id(500),
  'name': 'Synthetic owner target',
  'address': 'owner-fixture.invalid',
  'port': 22,
  'sshUser': 'fixture',
  'tags': <String>[],
  'credential': {'action': 'remove'},
};

final class CountedOwner implements OperationalOwnerApi {
  CountedOwner(this.delegate);
  final OperationalOwnerApi delegate;
  int calls = 0;
  @override
  bool supports(String method) => delegate.supports(method);
  @override
  OperationalOwnerInvocation prepare(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    calls++;
    return delegate.prepare(request, method, params, requestId: requestId);
  }
}

Future<void> rpcClient(List<String> args) async {
  final pipe = await PipeWorker.openOperationalClient(
    args[1],
    currentUserSid(),
    args[2],
  );
  OperationalApiClient? client;
  try {
    final session = await OperationalBootstrapClient(
      pipe: pipe,
      generation: a.generation,
      token: a.token,
    ).authenticate();
    if (session.role == OperationalRole.mcp)
      await session.openGrant(g.files(args[2]), g.grantId);
    client = OperationalApiClient(session);
    stdout.writeln('READY');
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      final input = jsonDecode(line) as Map;
      try {
        if (input['duplicate'] == true) {
          final params = Map<String, Object?>.from(input['params'] as Map);
          final pending = client.call(
            input['method'] as String,
            params,
            requestId: input['id'] as String,
          );
          pending.ignore();
          String? code, origin;
          try {
            await client.call(
              input['method'] as String,
              params,
              requestId: input['id'] as String,
            );
          } on OperationalRpcException catch (error) {
            code = error.code.wireName;
            origin = error.origin.name;
          }
          stdout.writeln(
            jsonEncode({
              'result': await pending,
              'duplicateError': code,
              'duplicateOrigin': origin,
            }),
          );
          continue;
        }
        stdout.writeln(
          jsonEncode({
            'result': await client.call(
              input['method'] as String,
              Map<String, Object?>.from(input['params'] as Map),
              requestId: input['id'] as String?,
            ),
          }),
        );
      } on OperationalRpcException catch (error) {
        stdout.writeln(
          jsonEncode({
            'error': error.code.wireName,
            'origin': error.origin.name,
          }),
        );
      }
    }
  } finally {
    await client?.close();
    await pipe.close();
  }
}

Future<void> main(List<String> args) async {
  containCurrentFixtureTree();
  if (args.first == 'client') {
    await a.client(args);
    return;
  }
  if (args.first == 'rpc-client') {
    await rpcClient(args);
    return;
  }
  final mode = args[1];
  try {
    if (mode == 'probe-disabled') {
      a.check(!ownerServiceProbesEnabled);
      var refused = false;
      try {
        OwnerServiceProbe.install((_, _) async {});
      } on StateError catch (e) {
        refused = e.message == 'OWNER_PROBE_UNAVAILABLE';
      }
      a.check(refused);
      stdout.writeln('PASS:$mode');
      return;
    }
    await g.scenario(
      args[0],
      'owner-foundation-$mode',
      readyRun: (root, store, authority, legacy, write, advance) async {
        final pairs = <a.Pair>[];
        OperationalSessions? registry;
        OperationalFoundationOwnerApi? foundation;
        McpRouter? router;
        OperationalPublicationGate? external;
        OperationalPublicationLease? held;
        Completer<void>? release;
        final requests = <OperationalSessionRequest>[];
        final local = p.join(root, 'private'), sid = currentUserSid();
        final custody = KeyCustody(DpapiProtection(), sid);
        final key = await custody.openReceiptKey(
          await readProtectedFile(
            local,
            p.join(g.files(root).directory, 'receipt-key.dpapi'),
            sid,
            maxBytes: 16384,
          ),
          g.workspaceId,
          g.keyId,
        );
        Future<a.Pair> pair(
          OperationalSessions sessions, [
          String image = 'serverdeck.exe',
        ]) async {
          final value = await a.Pair.start(root, image, sessions);
          pairs.add(value);
          await value.exchange();
          a.check(
            await value.next() ==
                (image == 'mcp.exe' ? 'AUTH:mcp' : 'AUTH:owner'),
          );
          return value;
        }

        try {
          final seed = await pair(legacy);
          final sessions = registry =
              await OperationalSessions.withNativePublicationGate(
                generation: a.generation,
                peer: seed.peer!,
              );
          final owner = await pair(sessions), second = await pair(sessions);
          final coordinator = MutationCoordinator.operational(
            store,
            custody,
            key,
          );
          final adapter = foundation = OperationalFoundationOwnerApi(
            store: store,
            coordinator: coordinator,
            sessions: sessions,
          );
          final services = wire.Services('normal');
          final routing = router = McpRouter(
            sessions: sessions,
            authority: authority,
            services: services,
          );
          final group = OperationalOwnerApiGroup([
            adapter,
            OperationalGrantOwnerApi(store: store, sessions: sessions),
          ]);
          final counted = CountedOwner(group);
          final server = OperationalApiServer(
            sessions: sessions,
            authority: authority,
            router: routing,
            owner: counted,
            readiness: () => OperationalReadiness(
              state: ReadinessState.ready,
              generation: a.generation,
              workspaceId: g.workspaceId,
            ),
          );
          var nextId = 1;
          Future<Map<String, Object?>> call(
            a.Pair peer,
            String method,
            Map<String, Object?> params, {
            String? requestId,
          }) async {
            final reply = await server.handle(
              peer.channel,
              StrictCodec().encode({
                'v': 1,
                'sessionId': peer.response!.sessionId,
                'id': requestId ?? id(nextId++),
                'method': method,
                'params': params,
              }),
            );
            try {
              return StrictCodec().decode(reply.bytes!);
            } finally {
              reply.release();
            }
          }

          Future<OperationalSessionRequest> request(
            a.Pair peer,
            String method, {
            bool prove = true,
          }) async {
            final value = sessions.reserve(
              peer.channel,
              peer.response!.sessionId,
              method,
            );
            requests.add(value);
            if (prove) await sessions.completeAdmission(value);
            return value;
          }

          if (mode == 'gate') {
            final mcp = await pair(sessions, 'mcp.exe');
            final opening = await request(mcp, 'mcp.open');
            await opening.openGrant(authority, await g.signedParams(root, mcp));
            external = await seed.peer!.publicationGate(a.generation);
            held = await external.acquire();
            final initial = settings(store.state.settings.revision);
            final first = call(
              owner,
              'settings.update',
              initial,
              requestId: id(1000),
            );
            first.ignore();
            a.check(coordinator.status(id(1000)).state == MutationState.queued);
            final status = await call(second, 'mutations.get', {
              'requestId': id(1000),
            });
            a.check((status['result'] as Map)['state'] == 'queued');
            final conflict = await call(second, 'settings.update', {
              ...initial,
              'theme': 'light',
            }, requestId: id(1000));
            a.check(
              (conflict['error'] as Map)['code'] == 'IDEMPOTENCY_CONFLICT',
            );
            final duplicate = call(
              second,
              'settings.update',
              initial,
              requestId: id(1000),
            );
            duplicate.ignore();
            sessions.disconnect(owner.channel);
            a.check(coordinator.status(id(1000)).state == MutationState.queued);
            await held.close();
            held = null;
            final result = await duplicate;
            a.check(
              result.containsKey('result') &&
                  store.state.settings.toJson()['theme'] == 'dark',
            );
            await a.fails(first, 'UNAUTHORIZED');
            a.check(sessions.mcpCount == 1 && store.state.receipts.length == 1);
            held = await external.acquire();
            final captured = settings(store.state.settings.revision);
            final direct = await request(second, 'settings.update');
            final invocation = adapter.prepare(
              direct,
              'settings.update',
              captured,
              requestId: id(1002),
            );
            final immutable = invocation.execute();
            immutable.ignore();
            captured['theme'] = 'light';
            try {
              await held.close();
              held = null;
              await immutable;
              a.check(store.state.settings.toJson()['theme'] == 'dark');
            } finally {
              invocation.close();
            }
            final created = await call(
              second,
              'profiles.create',
              profile(),
              requestId: id(1001),
            );
            a.check(
              created.containsKey('result') &&
                  sessions.mcpCount == 0 &&
                  store.state.profiles[id(500)]!.toJson()['address'] ==
                      'owner-fixture.invalid',
            );
            final fresh = await pair(sessions, 'mcp.exe');
            final freshOpen = await request(fresh, 'mcp.open');
            await freshOpen.openGrant(
              authority,
              await g.signedParams(root, fresh),
            );
            a.check(sessions.mcpCount == 1);
            final denied = await call(fresh, 'settings.get', {});
            a.check((denied['error'] as Map)['code'] == 'FORBIDDEN');
          } else if (mode == 'proof') {
            final reached = Completer<void>();
            release = Completer<void>();
            var paused = false;
            OwnerServiceProbe.install((boundary, method) async {
              if (boundary == OwnerServiceBoundary.beforeInitialProof &&
                  method == 'settings.update' &&
                  !paused) {
                paused = true;
                reached.complete();
                await release!.future;
              }
            });
            final initial = settings(store.state.settings.revision);
            final first = call(
              owner,
              'settings.update',
              initial,
              requestId: id(2000),
            );
            first.ignore();
            await reached.future;
            a.check(coordinator.status(id(2000)).state == MutationState.queued);
            final status = await call(second, 'mutations.get', {
              'requestId': id(2000),
            });
            a.check((status['result'] as Map)['state'] == 'queued');
            final changed = await call(second, 'settings.update', {
              ...initial,
              'theme': 'light',
            }, requestId: id(2000));
            a.check(
              (changed['error'] as Map)['code'] == 'IDEMPOTENCY_CONFLICT',
            );
            final duplicate = await call(
              second,
              'settings.update',
              initial,
              requestId: id(2000),
            );
            release.complete();
            a.check(
              jsonEncode((await first)['result']) ==
                      jsonEncode(duplicate['result']) &&
                  store.state.receipts.length == 1,
            );
            final unproved = await request(
              owner,
              'settings.update',
              prove: false,
            );
            final prepared = adapter.prepare(
              unproved,
              'settings.update',
              settings(store.state.settings.revision),
              requestId: id(2001),
            );
            try {
              await a.fails(prepared.execute(), 'FORBIDDEN');
            } finally {
              prepared.close();
            }
            a.check(
              coordinator.status(id(2001)).state == MutationState.notFound,
            );
            a.check(!unproved.initialAdmissionProved);
            final proof1 = sessions.completeAdmission(unproved),
                proof2 = sessions.completeAdmission(unproved);
            a.check(identical(proof1, proof2));
            await proof1;
            a.check(unproved.initialAdmissionProved);
            final read = await request(second, 'settings.get');
            var ambiguous = false;
            try {
              OperationalOwnerApiGroup([adapter, adapter])
                  .prepare(read, 'settings.get', {}, requestId: id(2002));
            } on StateError catch (e) {
              ambiguous = e.message == 'INTERNAL';
            }
            a.check(ambiguous);
            var foreign = false;
            final wrong = await legacy.begin(
              seed.channel,
              seed.response!.sessionId,
              'settings.get',
            );
            try {
              await a.fails(sessions.completeAdmission(wrong), 'FORBIDDEN');
              try {
                adapter.prepare(wrong, 'settings.get', {}, requestId: id(2003));
              } on StateError catch (e) {
                foreign = e.message == 'FORBIDDEN';
              }
            } finally {
              wrong.complete();
            }
            a.check(foreign);
          } else if (const {
            'cancel',
            'proof-peer-exit',
            'proof-close',
          }.contains(mode)) {
            final reached = Completer<void>();
            release = Completer<void>();
            OwnerServiceProbe.install((boundary, method) async {
              if (boundary == OwnerServiceBoundary.beforeInitialProof &&
                  method == 'settings.update') {
                reached.complete();
                await release!.future;
              }
            });
            final pending = call(
              owner,
              'settings.update',
              settings(store.state.settings.revision),
              requestId: id(3000),
            );
            pending.ignore();
            await reached.future;
            a.check(coordinator.status(id(3000)).state == MutationState.queued);
            if (mode == 'proof-close') {
              await adapter.close();
              release.complete();
              final result = await pending;
              a.check((result['error'] as Map)['code'] == 'NOT_READY');
            } else {
              if (mode == 'cancel') {
                sessions.disconnect(owner.channel);
                a.check(
                  coordinator.status(id(3000)).state == MutationState.notFound,
                );
              } else {
                owner.child.kill();
                await owner.child.exitCode.timeout(const Duration(seconds: 5));
              }
              release.complete();
              await a.fails(pending, 'UNAUTHORIZED');
              a.check(
                coordinator.status(id(3000)).state == MutationState.notFound,
              );
            }
            a.check(
              !store.state.receipts.containsKey(id(3000)) &&
                  store.isAutomationReady,
            );
          } else if (mode == 'close') {
            final reached = Completer<void>();
            release = Completer<void>();
            OwnerServiceProbe.install((boundary, method) async {
              if (boundary == OwnerServiceBoundary.afterFoundationCommit) {
                reached.complete();
                await release!.future;
              }
            });
            final pending = call(
              owner,
              'settings.update',
              settings(store.state.settings.revision),
              requestId: id(4000),
            );
            pending.ignore();
            await reached.future;
            a.check(store.state.receipts.containsKey(id(4000)));
            var done = false;
            final closing = sessions.close();
            closing.then((_) => done = true).ignore();
            await Future<void>.delayed(const Duration(milliseconds: 100));
            a.check(!done);
            release.complete();
            final reply = await pending;
            a.check(reply.containsKey('result'));
            await closing;
            a.check(done);
          } else if (mode == 'wire' || mode == 'wire-mcp') {
            await exerciseWire(
              root,
              sessions,
              server,
              store.state.settings.revision,
              mode == 'wire-mcp',
              counted,
            );
          } else {
            throw StateError('UNKNOWN_FOUNDATION_MODE');
          }
          a.check(services.calls == 0);
        } finally {
          if (release != null && !release.isCompleted) release.complete();
          await held?.close();
          await foundation?.close();
          router?.close();
          for (final request in requests) {
            request.complete();
          }
          await registry?.close();
          for (final value in pairs.reversed) {
            await value.close();
          }
          await external?.close();
          key.close();
        }
      },
    );
    stdout.writeln('PASS:$mode');
  } catch (_, stack) {
    stderr.writeln('OWNER_FOUNDATION_FIXTURE_FAILED');
    stderr.writeln(stack.toString().split('\n').take(9).join('\n'));
    exitCode = 1;
  }
}

Future<void> exerciseWire(
  String root,
  OperationalSessions sessions,
  OperationalApiServer server,
  String revision,
  bool mcp,
  CountedOwner counted,
) async {
  final name = a.pipeName();
  final worker = await PipeWorker.createOperationalServer(
    name,
    currentUserSid(),
    root,
  );
  Process? child;
  StreamIterator<String>? lines;
  OperationalServerChannel? channel;
  Future<String>? errors;
  try {
    final accepting = worker.accept();
    child = await Process.start(
      p.join(root, mcp ? 'mcp.exe' : 'serverdeck.exe'),
      ['rpc-client', name, root],
    );
    errors = child.stderr.transform(utf8.decoder).join();
    lines = StreamIterator(
      child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    await accepting;
    channel = OperationalServerChannel(
      handshake: OperationalServerHandshake(
        peer: await worker.verifyOperationalPeer(),
        token: a.token,
        channel: name,
        sessions: sessions,
      ),
      server: server,
    );
    final serving = channel.run();
    serving.ignore();
    Future<String> next() async {
      final reader = lines!;
      a.check(await reader.moveNext().timeout(const Duration(seconds: 10)));
      a.check(reader.current.length < 4096);
      return reader.current;
    }

    a.check(await next() == 'READY');
    Future<Map> call(
      String method,
      Map<String, Object?> params, [
      String? requestId,
      bool duplicate = false,
    ]) async {
      child!.stdin.writeln(
        jsonEncode({
          'method': method,
          'params': params,
          if (requestId != null) 'id': requestId,
          if (duplicate) 'duplicate': true,
        }),
      );
      return jsonDecode(await next()) as Map;
    }

    if (mcp) {
      a.check((await call('settings.get', {}))['error'] == 'FORBIDDEN');
      a.check(
        (await call('profiles.create', profile(), id(5000)))['error'] ==
            'FORBIDDEN',
      );
      a.check(counted.calls == 0);
    } else {
      final initial = settings(revision), mutationId = id(5000);
      final previous = counted.calls;
      final saved = await call('settings.update', initial, mutationId, true);
      a.check(saved.containsKey('result'));
      a.check(
        saved['duplicateError'] == 'IDEMPOTENCY_CONFLICT' &&
            saved['duplicateOrigin'] == 'local' &&
            counted.calls == previous + 1,
      );
      a.check(
        jsonEncode(await call('settings.update', initial, mutationId)) ==
            jsonEncode({'result': saved['result']}),
      );
      a.check(
        (await call('settings.update', {
              ...initial,
              'theme': 'light',
            }, mutationId))['error'] ==
            'IDEMPOTENCY_CONFLICT',
      );
      a.check(
        ((await call('mutations.get', {'requestId': mutationId}))['result']
                as Map)['state'] ==
            'committed',
      );
      a.check(
        (((await call('mutations.recent', {}))['result'] as Map)['receipts']
                    as List)
                .length ==
            1,
      );
      final invalid = await call('settings.get', {}, 'invalid');
      a.check(invalid['error'] == 'VALIDATION' && invalid['origin'] == 'local');
      a.check(
        (await call(
          'profiles.create',
          profile(),
          id(5001),
        )).containsKey('result'),
      );
      a.check(
        (((await call('profiles.list', {}))['result'] as Map)['profiles']
                    as List)
                .length ==
            1,
      );
      a.check(
        (await call('profiles.get', {
          'profileId': id(500),
        })).containsKey('result'),
      );
      a.check(
        (await call('profiles.update', {
          ...profile(),
          'expectedRevision': '1',
          'name': 'Changed through actual client',
        }, id(5002))).containsKey('result'),
      );
      a.check(
        (await call('profiles.update', {
              ...profile(),
              'expectedRevision': '1',
            }, id(5005)))['error'] ==
            'REVISION_CONFLICT',
      );
      a.check(
        (await call('profiles.delete', {
          'profileId': id(500),
          'expectedRevision': '2',
        }, id(5003))).containsKey('result'),
      );
      a.check(
        (await call('profiles.get', {'profileId': id(500)}))['error'] ==
            'NOT_FOUND',
      );
      a.check(
        (await call('grants.replace', {
          'requestId': id(5004),
          'grantId': g.grantId,
          'expectedRevision': 4,
          'label': 'composed owner services',
          'scopes': ['author'],
          'serverIds': <String>[],
          'lifetimeSeconds': 300,
        })).containsKey('result'),
      );
    }
    await a.finishClient(child);
    await serving.timeout(const Duration(seconds: 10));
    a.check(await child.exitCode == 0 && (await errors).isEmpty);
  } finally {
    await channel?.close();
    child?.kill();
    if (child != null) await child.exitCode;
    await lines?.cancel();
    await worker.close();
  }
}
