import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/api/owner_grants.dart';
import 'package:serverdeck_locald/api/operational_channel.dart';
import 'package:serverdeck_locald/api/operational_server.dart';
import 'package:serverdeck_locald/mcp/router.dart';
import 'package:serverdeck_locald/mcp/grants.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'operational_auth_actor.dart' as a;
import 'operational_grant_actor.dart' as g;
import 'operational_channel_actor.dart' as wire;
import 'gateway_actor.dart' as gateway;

Map<String, Object?> grantWriteParams() => {
  'requestId': '52345678-1234-4234-8234-123456789abc',
  'grantId': g.grantId,
  'expectedRevision': 4,
  'label': 'owner adapter snapshot',
  'scopes': ['author'],
  'serverIds': <String>[],
  'lifetimeSeconds': 300,
};

final class CountingOwner implements OperationalOwnerApi {
  CountingOwner(this.delegate);
  final OperationalOwnerApi delegate;
  int calls = 0;
  @override
  bool supports(String method) => delegate.supports(method);
  @override
  Future<Map<String, Object?>> dispatch(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params,
  ) {
    calls++;
    return delegate.dispatch(request, method, params);
  }
}

Future<void> ownerClient(List<String> args) async {
  a.ownRoot(args[2]);
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
    await for (final command
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      final params = grantWriteParams();
      final method = switch (command) {
        'replace' => 'grants.replace',
        'create' => 'grants.create',
        'revoke' => 'grants.revoke',
        _ => throw StateError('UNKNOWN_OWNER_COMMAND'),
      };
      if (command == 'create') {
        params.remove('expectedRevision');
        params['requestId'] = '62345678-1234-4234-8234-123456789abc';
        params['grantId'] = '72345678-1234-4234-8234-123456789abc';
      }
      if (command == 'revoke') {
        params.clear();
        params.addAll({
          'requestId': '82345678-1234-4234-8234-123456789abc',
          'grantId': g.grantId,
          'expectedRevision': 5,
        });
      }
      try {
        stdout.writeln(jsonEncode(await client.call(method, params)));
      } on OperationalRpcException catch (error) {
        stdout.writeln('ERROR:${error.code.wireName}');
      }
    }
  } finally {
    await client?.close();
    await pipe.close();
  }
}

Future<void> until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    a.check(watch.elapsed < const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> deniedChange(
  Future<OperationalTargetChangeLease> work,
  String code,
) async {
  OperationalTargetChangeLease? lease;
  try {
    lease = await work;
  } on StateError catch (error) {
    a.check(error.message == code);
    return;
  } finally {
    await lease?.close();
  }
  throw StateError('EXPECTED_FENCE_DENIAL');
}

Future<void> main(List<String> args) async {
  containCurrentFixtureTree();
  if (args.first == 'owner-client') {
    await ownerClient(args);
    return;
  }
  if (args.first == 'client') {
    if (args[3] == 'factory-deny') {
      final pipe = await PipeWorker.openOperationalClient(
        args[1],
        currentUserSid(),
        args[2],
      );
      try {
        final session = await OperationalBootstrapClient(
          pipe: pipe,
          generation: a.generation,
          token: a.token,
        ).authenticate();
        OperationalSessions? unexpected;
        try {
          unexpected = await OperationalSessions.withNativePublicationGate(
            generation: a.generation,
            peer: session.peer,
          );
          throw StateError('EXPECTED_NATIVE_ROLE_DENIAL');
        } on StateError catch (error) {
          a.check(error.message == 'UNAUTHORIZED');
        } finally {
          await unexpected?.close();
        }
        await session.revalidate();
        stdout.writeln('AUTH:mcp');
        stdout.writeln('DENIED_WITH_LIVE_PEER');
        await stdin.drain<void>();
      } finally {
        await pipe.close();
      }
    } else if (args[3] == 'wire-blocked')
      await g.client(args);
    else
      await a.client(args);
    return;
  }
  try {
    final mode = args[1];
    late g.PausedProtection protection;
    await g.scenario(
      args[0],
      'target-fence-$mode',
      inspectProtection: (value) => protection = value,
      readyRun: (root, store, authority, legacy, write, advance) async {
        final pairs = <a.Pair>[];
        final changes = <OperationalTargetChangeLease>[];
        final requests = <OperationalSessionRequest>[];
        OperationalSessions? owned;
        OperationalPublicationGate? external;
        OperationalPublicationLease? blocked;
        Completer<void>? authorityRelease;
        Future<a.Pair> pair(
          String image,
          OperationalSessions sessions, {
          String mode = 'normal',
        }) async {
          final value = await a.Pair.start(root, image, sessions, mode: mode);
          pairs.add(value);
          await value.exchange();
          a.check(
            await value.next() ==
                (image == 'mcp.exe' ? 'AUTH:mcp' : 'AUTH:owner'),
          );
          return value;
        }

        Future<OperationalSessionRequest> request(
          a.Pair value,
          String method,
        ) async {
          final result = await value.registry.begin(
            value.channel,
            value.response!.sessionId,
            method,
          );
          requests.add(result);
          return result;
        }

        try {
          final seed = await pair('serverdeck.exe', legacy);
          final registry = owned =
              await OperationalSessions.withNativePublicationGate(
                generation: a.generation,
                peer: seed.peer!,
              );
          final owner = await pair('serverdeck.exe', registry);
          final mcp = await pair('mcp.exe', registry);
          final opening = await request(mcp, 'mcp.open');
          final signed = await g.signedParams(root, mcp);
          if (mode != 'in-flight') await opening.openGrant(authority, signed);
          if (mode == 'owner-write') {
            final adapter = OperationalGrantOwnerApi(
              store: store,
              sessions: registry,
            );
            final mcpRequest = await request(mcp, 'session.ping');
            await a.fails(
              adapter.dispatch(mcpRequest, 'grants.replace', {}),
              'FORBIDDEN',
            );
            final foreign = await request(seed, 'grants.replace');
            await a.fails(
              adapter.dispatch(foreign, 'grants.replace', {}),
              'FORBIDDEN',
            );
            external = await seed.peer!.publicationGate(a.generation);
            blocked = await external.acquire();
            final ownerRequest = await request(owner, 'grants.replace');
            final params = grantWriteParams();
            var finished = false;
            final work = adapter.dispatch(
              ownerRequest,
              'grants.replace',
              params,
            );
            work.then((_) {
              finished = true;
            }).ignore();
            params['label'] = 'must not be captured after await';
            await Future<void>.delayed(const Duration(milliseconds: 100));
            a.check(
              !finished &&
                  store.operational.automation.grants[g.grantId]!.revision == 4,
            );
            await blocked.close();
            blocked = null;
            final ack = await work;
            final saved = store.operational.automation.grants[g.grantId]!;
            a.check(
              ack.length == 2 &&
                  ack['grantId'] == g.grantId &&
                  ack['revision'] == 5 &&
                  saved.label == 'owner adapter snapshot',
            );
            final retry = await request(owner, 'grants.replace');
            final repeated = await adapter.dispatch(
              retry,
              'grants.replace',
              grantWriteParams(),
            );
            a.check(
              jsonEncode(repeated) == jsonEncode(ack) &&
                  store.operational.automation.grants[g.grantId]!.secretRef ==
                      saved.secretRef,
            );
            final conflict = await request(owner, 'grants.replace');
            await a.fails(
              adapter.dispatch(conflict, 'grants.replace', {
                ...grantWriteParams(),
                'label': 'conflicting retry',
              }),
              'IDEMPOTENCY_CONFLICT',
            );
            a.check(
              store.operational.automation.grants[g.grantId]!.revision == 5,
            );
          } else if (mode == 'authority-close') {
            external = await seed.peer!.publicationGate(a.generation);
            final entered = Completer<void>();
            authorityRelease = Completer<void>();
            final work = registry.runAuthorityMutation(() async {
              final ack = await OwnerGrantService(store)
                  .submitOwner('grant.replace', grantWriteParams());
              entered.complete();
              await authorityRelease!.future;
              return ack;
            });
            work.ignore();
            await entered.future.timeout(const Duration(seconds: 5));
            var closed = false;
            final closing = registry.close();
            closing.then((_) {
              closed = true;
            }).ignore();
            await gateway.publicationHeld(root);
            await Future<void>.delayed(const Duration(milliseconds: 100));
            a.check(
              !closed &&
                  store.operational.automation.grants[g.grantId]!.revision == 5,
            );
            authorityRelease.complete();
            a.check((await work)['revision'] == 5);
            await closing;
            final free = await external.acquire();
            await free.close();
          } else if (mode == 'owner-wire' || mode == 'owner-wire-mcp') {
            final denied = mode == 'owner-wire-mcp';
            final name = a.pipeName();
            final worker = await PipeWorker.createOperationalServer(
              name,
              currentUserSid(),
              root,
            );
            Process? child;
            StreamIterator<String>? lines;
            Future<String>? errors;
            OperationalServerChannel? channel;
            McpRouter? router;
            try {
              final accepting = worker.accept();
              child = await Process.start(
                p.join(root, denied ? 'mcp.exe' : 'serverdeck.exe'),
                ['owner-client', name, root],
              );
              errors = child.stderr.transform(utf8.decoder).join();
              lines = StreamIterator(
                child.stdout
                    .transform(utf8.decoder)
                    .transform(const LineSplitter()),
              );
              await accepting;
              final services = wire.Services('normal');
              router = McpRouter(
                sessions: registry,
                authority: authority,
                services: services,
              );
              final adapter = CountingOwner(
                OperationalGrantOwnerApi(store: store, sessions: registry),
              );
              channel = OperationalServerChannel(
                handshake: OperationalServerHandshake(
                  peer: await worker.verifyOperationalPeer(),
                  token: a.token,
                  channel: name,
                  sessions: registry,
                ),
                server: OperationalApiServer(
                  sessions: registry,
                  authority: authority,
                  router: router,
                  owner: adapter,
                  readiness: () => OperationalReadiness(
                    state: ReadinessState.ready,
                    generation: a.generation,
                    workspaceId: g.workspaceId,
                  ),
                ),
              );
              final serving = channel.run();
              serving.ignore();
              Future<String> next() async {
                final reader = lines!;
                a.check(
                  await reader.moveNext().timeout(const Duration(seconds: 10)),
                );
                a.check(reader.current.length < 512);
                return reader.current;
              }

              a.check(await next() == 'READY');
              external = await seed.peer!.publicationGate(a.generation);
              blocked = await external.acquire();
              child.stdin.writeln('replace');
              if (denied) {
                a.check(
                  await next() == 'ERROR:FORBIDDEN' &&
                      adapter.calls == 0 &&
                      store
                              .operational
                              .automation
                              .grants[g.grantId]!
                              .revision ==
                          4,
                );
                await blocked.close();
                blocked = null;
              } else {
                var replied = false;
                final response = next();
                response.then((_) {
                  replied = true;
                }).ignore();
                await until(() => adapter.calls == 1);
                await Future<void>.delayed(const Duration(milliseconds: 100));
                a.check(
                  !replied &&
                      store
                              .operational
                              .automation
                              .grants[g.grantId]!
                              .revision ==
                          4,
                );
                await blocked.close();
                blocked = null;
                final ack = jsonDecode(await response) as Map;
                a.check(
                  ack.length == 2 &&
                      ack['grantId'] == g.grantId &&
                      ack['revision'] == 5,
                );
                final secret =
                    store.operational.automation.grants[g.grantId]!.secretRef;
                child.stdin.writeln('replace');
                a.check(
                  jsonEncode(jsonDecode(await next())) == jsonEncode(ack) &&
                      store
                              .operational
                              .automation
                              .grants[g.grantId]!
                              .secretRef ==
                          secret,
                );
                child.stdin.writeln('create');
                final created = jsonDecode(await next()) as Map;
                a.check(
                  created['grantId'] ==
                          '72345678-1234-4234-8234-123456789abc' &&
                      created['revision'] == 1,
                );
                child.stdin.writeln('revoke');
                final revoked = jsonDecode(await next()) as Map;
                a.check(
                  revoked['grantId'] == g.grantId &&
                      revoked['revision'] == 6 &&
                      store
                              .operational
                              .automation
                              .grants[g.grantId]!
                              .revokedAt !=
                          null,
                );
                a.check(adapter.calls == 4);
              }
              await a.finishClient(child);
              await serving.timeout(const Duration(seconds: 10));
              a.check(
                await child.exitCode == 0 &&
                    (await errors).isEmpty &&
                    services.calls == 0,
              );
            } finally {
              try {
                await channel?.close();
              } finally {
                router?.close();
                child?.kill();
                if (child != null) await child.exitCode;
                await lines?.cancel();
                await worker.close();
              }
            }
          } else if (mode == 'factory-role') {
            final negative = await pair(
              'mcp.exe',
              registry,
              mode: 'factory-deny',
            );
            a.check(await negative.next() == 'DENIED_WITH_LIVE_PEER');
          } else if (mode == 'wire-blocked') {
            final lease = await registry.beginTargetChange();
            changes.add(lease);
            final name = a.pipeName();
            final worker = await PipeWorker.createOperationalServer(
              name,
              currentUserSid(),
              root,
            );
            Process? child;
            StreamIterator<String>? lines;
            Future<String>? errors;
            OperationalServerChannel? channel;
            McpRouter? router;
            try {
              final accepting = worker.accept();
              child = await Process.start(p.join(root, 'mcp.exe'), [
                'client',
                name,
                root,
                'wire-blocked',
              ]);
              errors = child.stderr.transform(utf8.decoder).join();
              lines = StreamIterator(
                child.stdout
                    .transform(utf8.decoder)
                    .transform(const LineSplitter()),
              );
              await accepting;
              final services = wire.Services('normal');
              router = McpRouter(
                sessions: registry,
                authority: authority,
                services: services,
              );
              channel = OperationalServerChannel(
                handshake: OperationalServerHandshake(
                  peer: await worker.verifyOperationalPeer(),
                  token: a.token,
                  channel: name,
                  sessions: registry,
                ),
                server: OperationalApiServer(
                  sessions: registry,
                  authority: authority,
                  router: router,
                  readiness: () => OperationalReadiness(
                    state: ReadinessState.ready,
                    generation: a.generation,
                    workspaceId: g.workspaceId,
                  ),
                ),
              );
              final serving = channel.run();
              serving.ignore();
              a.check(await lines.moveNext() && lines.current == 'AUTH:mcp');
              final reads = protection.cleartexts.length;
              child.stdin.writeln('open');
              a.check(
                await lines.moveNext().timeout(const Duration(seconds: 10)) &&
                    lines.current == 'ERROR:UNAUTHORIZED',
              );
              await serving.timeout(const Duration(seconds: 10));
              a.check(
                registry.mcpCount == 0 &&
                    protection.cleartexts.length == reads &&
                    services.calls == 0,
              );
              await a.finishClient(child);
              a.check(await child.exitCode == 0 && (await errors).isEmpty);
            } finally {
              try {
                await channel?.close();
              } finally {
                router?.close();
                child?.kill();
                if (child != null) await child.exitCode;
                await lines?.cancel();
                await worker.close();
              }
            }
            await lease.close();
          } else if (mode == 'basic') {
            await deniedChange(
              registry.beginTargetChange(deadline: Duration.zero),
              'TIMEOUT',
            );
            a.check(
              !registry.targetChangesBlocked &&
                  registry.targetChangeInterests == 0,
            );
            final before = await request(mcp, 'session.ping');
            final changing = registry.beginTargetChange();
            a.check(
              registry.targetChangesBlocked &&
                  registry.targetChangeInterests == 1,
            );
            final lease = await changing;
            changes.add(lease);
            a.check(registry.mcpCount == 0 && registry.count == 1);
            await a.fails(before.revalidate(), 'UNAUTHORIZED');
            final ownerRequest = await request(owner, 'session.ping');
            await ownerRequest.revalidate();
            final fresh = await pair('mcp.exe', registry);
            final params = await g.signedParams(root, fresh);
            final denied = await request(fresh, 'mcp.open');
            final reads = protection.cleartexts.length;
            await a.fails(denied.openGrant(authority, params), 'UNAUTHORIZED');
            a.check(
              denied.openFailure != null &&
                  protection.cleartexts.length == reads,
            );
            final close = lease.close();
            a.check(identical(close, lease.close()));
            await close;
            a.check(
              !registry.targetChangesBlocked &&
                  registry.targetChangeInterests == 0,
            );
            final after = await pair('mcp.exe', registry);
            final next = await request(after, 'mcp.open');
            await next.openGrant(authority, await g.signedParams(root, after));
            a.check(registry.mcpCount == 1);
          } else if (mode == 'rollback') {
            final revision =
                store.operational.automation.grants[g.grantId]!.revision;
            final lease = await registry.beginTargetChange();
            changes.add(lease);
            try {
              await a.fails(
                OwnerGrantService(store).submitOwner('grant.replace', {
                  'requestId': '42345678-1234-4234-8234-123456789abc',
                  'grantId': g.grantId,
                  'expectedRevision': revision + 1,
                  'label': 'owned failed mutation',
                  'scopes': ['author'],
                  'serverIds': <String>[],
                  'lifetimeSeconds': 300,
                }),
                'REVISION_CONFLICT',
              );
              a.check(registry.targetChangesBlocked && registry.mcpCount == 0);
            } finally {
              await lease.close();
            }
            a.check(
              !registry.targetChangesBlocked &&
                  store.operational.automation.grants[g.grantId]!.revision ==
                      revision,
            );
          } else if (mode == 'overlap') {
            final first = await registry.beginTargetChange();
            changes.add(first);
            var ready = false;
            final second = registry.beginTargetChange().then((value) {
              ready = true;
              changes.add(value);
              return value;
            });
            second.ignore();
            await Future<void>.delayed(const Duration(milliseconds: 100));
            a.check(!ready && registry.targetChangeInterests == 2);
            await first.close();
            final lease = await second;
            a.check(
              registry.targetChangesBlocked &&
                  registry.targetChangeInterests == 1,
            );
            await lease.close();
            a.check(!registry.targetChangesBlocked);
            await a.fails(
              registry.begin(
                mcp.channel,
                mcp.response!.sessionId,
                'session.ping',
              ),
              'UNAUTHORIZED',
            );
          } else if (mode == 'timeout') {
            external = await seed.peer!.publicationGate(a.generation);
            blocked = await external.acquire();
            final watch = Stopwatch()..start();
            await deniedChange(registry.beginTargetChange(), 'TIMEOUT');
            a.check(
              watch.elapsed >= const Duration(milliseconds: 4800) &&
                  watch.elapsed < const Duration(seconds: 8),
            );
            await until(() => registry.targetChangeInterests == 0);
            a.check(registry.mcpCount == 0);
            await blocked.close();
            blocked = null;
            final next = await registry.beginTargetChange();
            changes.add(next);
            await next.close();
          } else if (mode == 'stop') {
            final lease = await registry.beginTargetChange();
            changes.add(lease);
            final waiting = registry.beginTargetChange();
            waiting.ignore();
            var closed = false;
            final closing = registry.close();
            closing.then((_) {
              closed = true;
            }).ignore();
            a.check(identical(closing, registry.close()));
            await deniedChange(waiting, 'SERVICE_UNAVAILABLE');
            await Future<void>.delayed(const Duration(milliseconds: 100));
            a.check(!closed && registry.targetChangesBlocked);
            await lease.close();
            await closing;
            await deniedChange(
              registry.beginTargetChange(),
              'SERVICE_UNAVAILABLE',
            );
          } else if (mode == 'quota') {
            final first = await registry.beginTargetChange();
            changes.add(first);
            final waiting = [
              for (var i = 0; i < 15; i++)
                registry.beginTargetChange().then((lease) async {
                  changes.add(lease);
                  await lease.close();
                }),
            ];
            for (final value in waiting) {
              value.ignore();
            }
            a.check(registry.targetChangeInterests == 16);
            await deniedChange(registry.beginTargetChange(), 'RESOURCE_LIMIT');
            await first.close();
            await Future.wait(waiting);
            a.check(registry.targetChangeInterests == 0);
          } else if (mode == 'in-flight') {
            protection.pauseNext = 1;
            final work = opening.openGrant(authority, signed);
            work.ignore();
            await protection.reached(1);
            final lease = await registry.beginTargetChange();
            changes.add(lease);
            await a.fails(work, 'UNAUTHORIZED');
            await lease.close();
            protection.release();
            await until(() => authority.pendingOpens == 0);
            a.check(
              registry.mcpCount == 0 &&
                  protection.cleartexts.last.every((value) => value == 0),
            );
          } else {
            throw StateError('UNKNOWN_MODE');
          }
        } finally {
          protection.release();
          if (authorityRelease != null && !authorityRelease.isCompleted)
            authorityRelease.complete();
          await blocked?.close();
          for (final lease in changes) {
            await lease.close();
          }
          for (final value in requests) {
            value.complete();
          }
          await owned?.close();
          for (final value in pairs.reversed) {
            await value.close();
          }
          await external?.close();
        }
      },
    );
    stdout.writeln('PASS:$mode');
  } catch (_, stack) {
    stderr.writeln('TARGET_FENCE_FIXTURE_FAILED');
    stderr.writeln(stack.toString().split('\n').take(8).join('\n'));
    exitCode = 1;
  }
}
