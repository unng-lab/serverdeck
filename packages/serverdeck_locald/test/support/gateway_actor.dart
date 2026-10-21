import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:cryptography/dart.dart';
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/api/operational_channel.dart';
import 'package:serverdeck_locald/api/operational_server.dart';
import 'package:serverdeck_locald/api/owner_grants.dart';
import 'package:serverdeck_locald/mcp/router.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:serverdeck_windows/mutex.dart';

import '../../../serverdeck_mcp/lib/src/local_gateway.dart';
import '../../../serverdeck_mcp/lib/src/server.dart';
import '../../../serverdeck_mcp/lib/src/stdio.dart';
import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'operational_auth_actor.dart' as n;
import 'operational_grant_actor.dart' as g;
import 'operational_channel_actor.dart' as wire;

bool pending(String mode) => const {
  'pending',
  'cancel-ack',
  'native-loss',
  'expiry',
  'quota',
  'eof',
}.contains(mode);
bool controlled(String mode) => const {
  'wrong-catalog',
  'wrong-poll',
  'wrong-cancel',
  'rpc-timeout',
  'rpc-remote',
  'overall',
  'cancel-timeout',
  'queued-cancel',
  'heartbeat-remote-limit',
}.contains(mode);

const handle = 'c2345678-1234-4234-8234-123456789abc';
const foreignHandle = 'd2345678-1234-4234-8234-123456789abc';

/// Fault responses only; actual bootstrap/DPAPI grant-open/native peer remain.
final class Control {
  Control(this.mode);
  final String mode;
  int starts = 0, polls = 0, cancels = 0, pings = 0;
  String? root;
  Future<void> serve(
    OperationalServerHandshake handshake,
    OperationalMcpAuthority authority,
  ) async {
    final io = OperationalHandshakeIo(handshake.peer);
    final boot = Stopwatch()..start();
    Duration bootLeft() => const Duration(seconds: 5) - boot.elapsed;
    try {
      await io.write((await handshake.hello()).toJson(), bootLeft);
      await io.write(
        (await handshake.authenticate(await io.read(bootLeft))).toJson(),
        bootLeft,
      );
      while (true) {
        final frame = StrictCodec().decode(
          await io.read(() => const Duration(seconds: 60)),
        );
        validateRequestEnvelope(frame);
        final method = frame['method'] as String;
        final request = await handshake.sessions.begin(
          handshake.channel,
          frame['sessionId'] as String,
          method,
        );
        try {
          Map<String, Object?>? result;
          LocalError? error;
          if (method == 'mcp.open') {
            result = (await request.openGrant(
              authority,
              frame['params'],
            )).toJson();
          } else if (method == 'session.ping') {
            request.authorizeMcp();
            pings++;
            if (mode == 'queued-cancel') {
              File(p.join(root!, 'heartbeat.waiting'))
                  .writeAsStringSync('waiting');
              await until(
                () => File(p.join(root!, 'heartbeat.release')).existsSync(),
              );
            }
            if (mode == 'heartbeat-remote-limit')
              error = const LocalError(ErrorCode.resourceLimit);
            else
              result = {'leaseSeconds': 60};
          } else {
            n.check(method == 'mcp.invoke');
            request.authorizeMcp();
            final input = McpInvokeInput.fromJson(frame['params']);
            switch (input.kind) {
              case McpInvokeKind.catalog:
                n.check(mode == 'wrong-catalog');
                result = McpInvokeReply.done(
                  McpToolResult.success({'private': 'NEVER_PUBLISH'}),
                ).toJson();
              case McpInvokeKind.request:
                starts++;
                n.check(input.arguments!['requestId'] == g.requestId);
                n.check(input.arguments!['name'] != 'NEVER_ADMIT');
                if (mode == 'rpc-timeout') {
                  await wire.closed(
                    handshake.peer.read(deadline: const Duration(seconds: 8)),
                  );
                  return;
                }
                if (mode == 'rpc-remote') {
                  if (starts == 1)
                    error = const LocalError(ErrorCode.timeout);
                  else
                    result = McpInvokeReply.done(
                      McpToolResult.success(wire.data()),
                    ).toJson();
                } else
                  result = McpInvokeReply.pending(handle).toJson();
              case McpInvokeKind.poll:
                polls++;
                n.check(input.operationId == handle);
                result = McpInvokeReply.pending(
                  mode == 'wrong-poll' ? foreignHandle : handle,
                ).toJson();
              case McpInvokeKind.cancel:
                cancels++;
                n.check(input.operationId == handle);
                if (mode == 'cancel-timeout') {
                  await wire.closed(
                    handshake.peer.read(deadline: const Duration(seconds: 8)),
                  );
                  return;
                }
                result = mode == 'wrong-cancel'
                    ? {'cancelled': false}
                    : McpInvokeReply.cancelled().toJson();
            }
          }
          await request.revalidate();
          final deadline = Stopwatch()..start();
          await io.write({
            'v': 1,
            'id': frame['id'],
            'generation': n.generation,
            if (error != null) 'error': error.toJson() else 'result': result!,
          }, () => const Duration(seconds: 5) - deadline.elapsed);
        } finally {
          request.complete();
        }
      }
    } on StateError catch (error) {
      n.check(
        const {'UNAUTHORIZED', 'SERVICE_UNAVAILABLE'}.contains(error.message),
      );
    } finally {
      handshake.close();
    }
  }
}

final class Services implements McpToolServices {
  Services(this.mode);
  final String mode;
  int calls = 0, cancels = 0;
  final results = <Completer<McpToolResult>>[];
  final inputs = <Map<String, Object?>>[];
  McpToolResult output(int ordinal) => McpToolResult.success({
    ...wire.data(),
    'ordinal': ordinal,
    if (mode.startsWith('stdout-')) 'large': 'x' * (1024 * 1024),
  });
  @override
  McpServiceOperation start(
    OperationalMcpContext context,
    McpToolDefinition tool,
    Map<String, Object?> arguments,
  ) {
    final ordinal = ++calls;
    inputs.add(arguments);
    final result = Completer<McpToolResult>();
    results.add(result);
    if (!pending(mode)) result.complete(output(ordinal));
    return McpServiceOperation(result.future, () async {
      cancels++;
    });
  }

  void finish(int i) {
    if (!results[i].isCompleted) results[i].complete(output(i + 1));
  }
}

Future<void> until(bool Function() check) async {
  final watch = Stopwatch()..start();
  while (!check()) {
    n.check(watch.elapsed < const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Observe the actual native wait result, not a deadline that also includes
/// worker startup. Every acquired probe is released before the next attempt.
Future<void> publicationHeld(String root) async {
  final sid = currentUserSid();
  final normalized = p.normalize(p.absolute(root)).toLowerCase();
  final digest = const DartSha256()
      .hashSync(
        utf8.encode(
          'serverdeck-next-publication-v1\n$sid\n$normalized\n${n.generation}',
        ),
      )
      .bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  final watch = Stopwatch()..start();
  while (true) {
    n.check(watch.elapsed < const Duration(seconds: 3));
    final probe = await MutexLease.acquire(
      'Global\\ServerDeckNext.v1.$digest',
      sid,
    );
    try {
      n.check(!probe.abandoned);
      if (!probe.acquired) return;
    } finally {
      await probe.close();
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// A failed expectation must still dispose any unexpectedly acquired ownership.
Future<void> gateDenied(
  Future<OperationalPublicationLease> action,
  String code,
) async {
  OperationalPublicationLease? lease;
  try {
    lease = await action;
  } on StateError catch (error) {
    n.check(error.message == code);
    return;
  } finally {
    await lease?.close();
  }
  throw StateError('EXPECTED_GATE_DENIAL');
}

/// Scheduling probe only: retain the actual native guard/lease, then pause its
/// delivery to the stdio writer. No fake grant, RPC or permission is supplied.
final class PublicationPause implements McpGateway {
  PublicationPause(this.delegate, this.root);
  final LocalMcpGateway delegate;
  final String root;
  @override
  McpInvocation start(String method, Map<String, Object?> params) {
    final call = delegate.start(method, params);
    return McpInvocation(
      call.result,
      call.cancelInterest,
      beforePublish: () async {
        await call.beforePublish!();
        File(p.join(root, 'publication.checked')).writeAsStringSync('checked');
        final watch = Stopwatch()..start();
        while (!File(p.join(root, 'publication.release')).existsSync()) {
          if (watch.elapsed > const Duration(seconds: 3))
            throw const McpGatewayFailure(ErrorCode.timeout);
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      },
      validatePublication: call.validatePublication,
      afterPublish: call.afterPublish,
    );
  }

  @override
  Future<void> close() => delegate.close();
}

/// Select the owner's mutation before the second actual guard competes for
/// the mutex. The first stdout write/flush and every real guard remain intact.
final class QueuedPublicationPause implements McpGateway {
  QueuedPublicationPause(this.delegate, this.root);
  final LocalMcpGateway delegate;
  final String root;
  int calls = 0;
  @override
  McpInvocation start(String method, Map<String, Object?> params) {
    final call = delegate.start(method, params), ordinal = ++calls;
    return McpInvocation(
      call.result,
      call.cancelInterest,
      beforePublish: () async {
        if (ordinal == 2) {
          File(p.join(root, 'publication.queued')).writeAsStringSync('queued');
          final watch = Stopwatch()..start();
          while (!File(p.join(root, 'publication.mutated')).existsSync()) {
            if (watch.elapsed > const Duration(seconds: 3))
              throw const McpGatewayFailure(ErrorCode.timeout);
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        }
        await call.beforePublish!();
      },
      validatePublication: call.validatePublication,
      afterPublish: call.afterPublish,
    );
  }

  @override
  Future<void> close() => delegate.close();
}

Future<void> bridge(List<String> args) async {
  final root = args[2], mode = args[3];
  n.ownRoot(root);
  final pipe = await PipeWorker.openOperationalClient(
    args[1],
    currentUserSid(),
    root,
  );
  try {
    final session = await OperationalBootstrapClient(
      pipe: pipe,
      generation: n.generation,
      token: n.token,
    ).authenticate();
    if (mode == 'owner-deny' || mode == 'missing-grant') {
      try {
        await LocalMcpGateway.connect(session);
        throw StateError('EXPECTED_DENIAL');
      } on McpGatewayFailure catch (e) {
        n.check(e.code == ErrorCode.forbidden);
      }
      if (mode == 'owner-deny') {
        final client = OperationalApiClient(session);
        n.check((await client.call('session.ping', {}))['leaseSeconds'] == 60);
        await client.close();
        stdout.writeln('FACTORY_DENIED_SAFE');
        return;
      }
    }
    await session.openGrant(g.files(root), g.grantId);
    final gateway = await LocalMcpGateway.connect(session);
    if (mode == 'queued-cancel') {
      await Future<void>.delayed(const Duration(seconds: 19));
      await until(() => File(p.join(root, 'heartbeat.waiting')).existsSync());
      Map<String, Object?> params(String name) => {
        'name': 'serverdeck_profiles_create',
        'arguments': {
          'requestId': g.requestId,
          'name': name,
          'body':
              ((wire.validationCall()['request'] as Map)['arguments']
                  as Map)['body'],
        },
      };
      final admitted = [
        for (var i = 0; i < 15; i++)
          gateway.start('tools/call', params('admitted')),
      ];
      for (final call in admitted) {
        call.result.ignore();
      }
      final queued = gateway.start('tools/call', params('NEVER_ADMIT'));
      queued.result.ignore();
      await queued.cancelInterest();
      stdout.writeln('QUEUED_CANCELLED');
      await stdin.drain<void>();
      await gateway.close();
      return;
    }
    if (mode == 'heartbeat' || mode == 'heartbeat-remote-limit') {
      stdout.writeln('CONNECTED');
      await Future<void>.delayed(const Duration(seconds: 22));
      if (mode == 'heartbeat-remote-limit') {
        try {
          final unexpected = gateway.start('tools/list', {});
          unexpected.result.ignore();
          throw StateError('EXPECTED_HEARTBEAT_RETIREMENT');
        } on McpGatewayFailure catch (error) {
          n.check(error.code == ErrorCode.serviceUnavailable);
        }
      }
      stdout.writeln('HEARTBEAT');
      await stdin.drain<void>();
      await gateway.close();
      return;
    }
    if (mode == 'quota') {
      final calls = [
        for (var i = 0; i < 16; i++)
          gateway.start('tools/call', {
            'name': 'serverdeck_profiles_validate',
            'arguments': (wire.validationCall()['request'] as Map)['arguments'],
          }),
      ];
      for (final call in calls) {
        call.result.ignore();
      }
      final denied = await gateway.start('tools/call', {
        'name': 'serverdeck_profiles_list',
      }).result;
      n.check(
        (((denied['structuredContent'] as Map)['error'] as Map)['code']) ==
            'RESOURCE_LIMIT',
      );
      try {
        gateway.start('tools/list', {});
        throw StateError('EXPECTED_LIMIT');
      } on McpGatewayFailure catch (error) {
        n.check(error.code == ErrorCode.resourceLimit);
      }
      stdout.writeln('ADMITTED16');
      // Let all original acknowledgements return before cancel requests compete
      // for native slots. No service result needs to complete.
      final commands = StreamIterator(stdin);
      try {
        n.check(await commands.moveNext());
        final cancels = [for (final call in calls) call.cancelInterest()];
        for (var i = 0; i < calls.length; i++)
          n.check(identical(cancels[i], calls[i].cancelInterest()));
        await Future.wait(cancels);
        stdout.writeln('CANCELLED16');
        while (await commands.moveNext()) {}
      } finally {
        await commands.cancel();
      }
      await gateway.close();
      return;
    }
    final output = stdout.nonBlocking;
    final code = !mode.startsWith('publish-') && mode != 'stdout-revoke'
        ? await serveMcpStdio(gateway)
        : await McpServer(
            input: stdin,
            write: (bytes) async {
              output.add(bytes);
              await output.flush();
            },
            gateway: mode == 'stdout-revoke'
                ? QueuedPublicationPause(gateway, root)
                : mode.startsWith('publish-')
                ? PublicationPause(gateway, root)
                : gateway,
            diagnostic: (value) => stderr.writeln('MCP:$value'),
          ).run();
    if (code != 0)
      exit(
        code,
      ); // Actual owned process teardown, never force-unlock a live flush.
    await gateway.close();
  } finally {
    await pipe.close();
  }
}

final class Wire {
  Wire(this.child)
    : lines = StreamIterator(
        child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
      errors = child.stderr.transform(utf8.decoder).join();
  final Process child;
  final StreamIterator<String> lines;
  final Future<String> errors;
  void send(
    String method,
    Object? id, [
    Map<String, Object?> params = const {},
  ]) {
    child.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        if (id != null) 'id': id,
        'method': method,
        'params': params,
      }),
    );
  }

  Future<Map<String, Object?>> next() async {
    final moved = await lines.moveNext().timeout(const Duration(seconds: 40));
    if (!moved) stderr.write(await errors);
    n.check(moved);
    return jsonDecode(lines.current) as Map<String, Object?>;
  }

  Future<void> initialize() async {
    send('initialize', 0, {
      'protocolVersion': '2025-11-25',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'independent-fixture', 'version': '1'},
    });
    final reply = await next();
    n.check(
      reply['id'] == 0 &&
          (reply['result'] as Map)['protocolVersion'] == '2025-11-25',
    );
    send('notifications/initialized', null);
  }

  void call(Object id) => send('tools/call', id, {
    'name': 'serverdeck_profiles_create',
    'arguments': {
      'requestId': g.requestId,
      'name': 'e\u0301😀',
      'body': (wire.validationCall()['request'] as Map)['arguments'] is Map
          ? (((wire.validationCall()['request'] as Map)['arguments']
                as Map)['body'])
          : null,
    },
    '_meta': {'ignored': 'NEVER_FORWARD'},
  });
}

Future<void> main(List<String> args) async {
  try {
    containCurrentFixtureTree();
    if (args.first == 'bridge') {
      await bridge(args);
      return;
    }
    if (args.first == 'client') {
      await n.client(args);
      return;
    }
    final mode = args[1];
    await g.scenario(
      args[0],
      'gateway-$mode',
      initialWallOffset: mode == 'publish-expiry'
          ? const Duration(seconds: -280)
          : Duration.zero,
      readyRun: (root, store, authority, registry, write, advance) async {
        DateTime? expires;
        if (mode == 'publish-expiry') {
          // Real UTC expiry in20s; server authority's fixture clock remains
          // earlier, so the bridge must perform its own final synchronous check.
          expires = store.operational.automation.grants[g.grantId]!.expiresAt;
        }
        final name = n.pipeName();
        final worker = await PipeWorker.createOperationalServer(
          name,
          currentUserSid(),
          root,
        );
        final services = Services(mode);
        final control = Control(mode)..root = root;
        late final McpRouter router;
        var routerReady = false;
        OperationalSessions? nativeRegistry;
        n.Pair? mutationOwner;
        var mutationEntered = false;
        Future<void> revokeThroughOwner() async {
          final owner = mutationOwner ??= await n.Pair.start(
            root,
            'serverdeck.exe',
            registry,
          );
          await owner.exchange();
          n.check(await owner.next() == 'AUTH:owner');
          final request = await registry.begin(
            owner.channel,
            owner.response!.sessionId,
            'grants.revoke',
          );
          try {
            final pending =
                OperationalGrantOwnerApi(
                  store: store,
                  sessions: registry,
                ).dispatch(request, 'grants.revoke', {
                  'requestId': '92345678-1234-4234-8234-123456789abc',
                  'grantId': g.grantId,
                  'expectedRevision':
                      store.operational.automation.grants[g.grantId]!.revision,
                });
            mutationEntered = true;
            await pending;
          } finally {
            request.complete();
          }
        }

        Process? child;
        OperationalServerChannel? channel;
        OperationalPublicationGate? ownerGate;
        OperationalPublicationLease? held;
        Wire? transport;
        try {
          final accepting = worker.accept();
          child = await Process.start(
            p.join(root, mode == 'owner-deny' ? 'serverdeck.exe' : 'mcp.exe'),
            ['bridge', name, root, mode],
          );
          final client = transport = Wire(child);
          await accepting;
          final peer = await worker.verifyOperationalPeer();
          registry = nativeRegistry =
              await OperationalSessions.withNativePublicationGate(
                generation: n.generation,
                peer: peer,
              );
          router = McpRouter(
            sessions: registry,
            authority: authority,
            services: services,
          );
          routerReady = true;
          ownerGate = await peer.publicationGate(n.generation);
          final handshake = OperationalServerHandshake(
            peer: peer,
            token: n.token,
            channel: name,
            sessions: registry,
          );
          Future<void> serving;
          if (controlled(mode)) {
            serving = control.serve(handshake, authority);
          } else {
            channel = OperationalServerChannel(
              handshake: handshake,
              server: OperationalApiServer(
                sessions: registry,
                authority: authority,
                router: router,
                readiness: () => OperationalReadiness(
                  state: ReadinessState.ready,
                  generation: n.generation,
                  workspaceId: g.workspaceId,
                ),
              ),
            );
            serving = channel.run();
          }
          serving.ignore();
          if (mode == 'queued-cancel') {
            n.check(
              await client.lines.moveNext() &&
                  client.lines.current == 'QUEUED_CANCELLED',
            );
            File(p.join(root, 'heartbeat.release'))
                .writeAsStringSync('release');
            await until(() => control.starts == 15);
            n.check(control.starts == 15 && control.cancels == 0);
          } else if (mode == 'heartbeat' || mode == 'heartbeat-remote-limit') {
            n.check(
              await client.lines.moveNext() &&
                  client.lines.current == 'CONNECTED',
            );
            final expiry = registry.nextExpiry!;
            n.check(
              await client.lines.moveNext().timeout(
                    const Duration(seconds: 27),
                  ) &&
                  client.lines.current == 'HEARTBEAT',
            );
            if (mode == 'heartbeat-remote-limit') {
              await until(() => registry.mcpCount == 0);
              n.check(control.pings == 1 && control.starts == 0);
            } else {
              n.check(
                registry.nextExpiry! >= expiry + const Duration(seconds: 19),
              );
            }
          } else if (mode == 'quota') {
            n.check(
              await client.lines.moveNext() &&
                  client.lines.current == 'ADMITTED16',
            );
            await until(() => services.calls == 16);
            n.check(router.chargedOperations == 16);
            child.stdin.writeln('cancel');
            n.check(
              await client.lines.moveNext() &&
                  client.lines.current == 'CANCELLED16',
            );
            n.check(
              services.calls == 16 &&
                  services.cancels == 16 &&
                  router.chargedOperations == 16,
            );
            for (var i = 0; i < 16; i++) services.finish(i);
          } else if (mode == 'owner-deny') {
            n.check(
              await client.lines.moveNext() &&
                  client.lines.current == 'FACTORY_DENIED_SAFE',
            );
          } else {
            await client.initialize();
            if (controlled(mode)) {
              if (mode == 'wrong-catalog') {
                client.send('tools/list', 'bad');
                final reply = await client.next();
                n.check(
                  ((reply['error'] as Map)['message']) == 'INTERNAL' &&
                      !jsonEncode(reply).contains('NEVER_PUBLISH'),
                );
              } else if (mode == 'wrong-cancel' || mode == 'cancel-timeout') {
                client.call('cancel');
                await until(() => control.starts == 1);
                final watch = Stopwatch()..start();
                client.send('notifications/cancelled', null, {
                  'requestId': 'cancel',
                });
                client.send('ping', 'alive');
                n.check(
                  (await client.next())['id'] == 'alive' &&
                      control.cancels == 1,
                );
                if (mode == 'cancel-timeout')
                  n.check(
                    watch.elapsed >= const Duration(milliseconds: 4500) &&
                        watch.elapsed < const Duration(seconds: 8),
                  );
                client.send('tools/list', 'closed');
                final denied = await client.next();
                n.check(
                  (denied['error'] as Map)['message'] == 'SERVICE_UNAVAILABLE',
                );
              } else {
                final watch = Stopwatch()..start();
                client.call('fault');
                final reply = await client.next();
                final error =
                    (((reply['result'] as Map)['structuredContent']
                            as Map)['error']
                        as Map);
                n.check(
                  error['code'] ==
                      (mode == 'wrong-poll' ? 'INTERNAL' : 'TIMEOUT'),
                );
                n.check(control.starts == 1);
                if (mode == 'rpc-timeout')
                  n.check(
                    watch.elapsed >= const Duration(milliseconds: 4500) &&
                        watch.elapsed < const Duration(seconds: 8),
                  );
                if (mode == 'overall') {
                  n.check(
                    watch.elapsed >= const Duration(milliseconds: 34500) &&
                        watch.elapsed < const Duration(seconds: 40),
                  );
                  await until(
                    () => control.cancels == 1 || registry.mcpCount == 0,
                  );
                  n.check(control.polls >= 20 && control.pings >= 1);
                  n.check(control.cancels <= 1);
                }
                if (mode == 'rpc-remote') {
                  n.check(error['retry'] == 'retry-same-request');
                  client.call('second');
                  final next = await client.next();
                  n.check(
                    (next['result'] as Map)['isError'] == false &&
                        control.starts == 2,
                  );
                }
              }
            } else if (mode == 'basic' || mode == 'missing-grant') {
              client.send('tools/list', 'catalog', {
                '_meta': {'progressToken': 'e\u0301😀'},
              });
              final catalog = await client.next();
              n.check(
                catalog['id'] == 'catalog' &&
                    ((catalog['result'] as Map)['tools'] as List).length == 7,
              );
              client.send('tools/call', 'defaults', {
                'name': 'serverdeck_profiles_list',
              });
              n.check(
                ((await client.next())['result'] as Map)['isError'] == false,
              );
              n.check(services.inputs.single.isEmpty);
              client.call('e\u0301😀');
              final value = await client.next();
              final observed =
                  ((value['result'] as Map)['structuredContent'] as Map)['data']
                      as Map;
              n.check(
                observed['text'] == 'e\u0301😀' &&
                    observed['counter'] == 9223372036854775807,
              );
              n.check(
                value['id'] == 'e\u0301😀' &&
                    ((value['result'] as Map)['structuredContent']
                            as Map)['ok'] ==
                        true,
              );
              n.check(
                services.inputs.last['requestId'] == g.requestId &&
                    services.inputs.last['name'] == 'e\u0301😀',
              );
              n.check(!services.inputs.last.containsKey('_meta'));
              client.send('tools/call', 'invalid', {
                'name': 'serverdeck_unknown',
                'arguments': <String, Object?>{},
              });
              n.check(
                ((await client.next())['error'] as Map)['code'] == -32602 &&
                    services.calls == 2,
              );
            } else if (mode == 'pending') {
              client.call('pending');
              await until(() => services.calls == 1);
              await Future<void>.delayed(const Duration(milliseconds: 600));
              n.check(services.calls == 1 && router.retainedOperations == 1);
              services.finish(0);
              final reply = await client.next();
              n.check(
                reply['id'] == 'pending' &&
                    (((reply['result'] as Map)['structuredContent']
                                as Map)['data']
                            as Map)['ordinal'] ==
                        1,
              );
            } else if (mode == 'cancel-ack') {
              client.call('same');
              client.send('notifications/cancelled', null, {
                'requestId': 'same',
              });
              await until(() => services.cancels == 1);
              n.check(services.calls == 1 && router.chargedOperations == 1);
              client.send('ping', 'alive');
              n.check((await client.next())['id'] == 'alive');
              services.finish(0);
              // Router retains the cancelled handle receipt for its bounded
              // retention window, even after actual service work settles.
              await Future<void>.delayed(const Duration(milliseconds: 30));
              n.check(router.retainedOperations == 1);
              client.call('same');
              await until(() => services.calls == 2);
              services.finish(1);
              final reply = await client.next();
              n.check(
                reply['id'] == 'same' &&
                    (((reply['result'] as Map)['structuredContent']
                                as Map)['data']
                            as Map)['ordinal'] ==
                        2 &&
                    services.cancels == 1,
              );
            } else if (mode == 'native-loss' || mode == 'expiry') {
              client.call('fault');
              await until(() => services.calls == 1);
              if (mode == 'native-loss') {
                await channel!.close();
              } else {
                advance(const Duration(seconds: 300));
              }
              final reply = await client.next();
              n.check(
                reply['id'] == 'fault' &&
                    (reply['result'] as Map)['isError'] == true &&
                    !jsonEncode(reply).contains('ordinal'),
              );
              services.finish(0);
              client.send('tools/list', 'closed');
              final denied = await client.next();
              n.check(
                denied.containsKey('error') && !denied.containsKey('result'),
              );
            } else if (mode == 'eof') {
              client.call('abandoned');
              await until(() => services.calls == 1);
            } else if (mode == 'writer-cancel') {
              held = await ownerGate.acquire();
              client.call('reuse');
              await until(() => services.calls == 1);
              await Future<void>.delayed(const Duration(milliseconds: 150));
              client.send('notifications/cancelled', null, {
                'requestId': 'reuse',
              });
              client.call('reuse');
              await until(() => services.calls == 2);
              await held.close();
              held = null;
              final reply = await client.next();
              n.check(
                reply['id'] == 'reuse' &&
                    (((reply['result'] as Map)['structuredContent']
                                as Map)['data']
                            as Map)['ordinal'] ==
                        2,
              );
              n.check(services.cancels == 0);
            } else if (mode.startsWith('publish-')) {
              if (expires != null) {
                final left = expires
                    .subtract(const Duration(seconds: 2))
                    .difference(DateTime.now().toUtc());
                n.check(left > Duration.zero);
                await Future<void>.delayed(left);
              }
              client.call('ordered');
              await until(
                () => File(p.join(root, 'publication.checked')).existsSync(),
              );
              if (mode == 'publish-expiry') {
                final left = expires!
                    .add(const Duration(milliseconds: 100))
                    .difference(DateTime.now().toUtc());
                if (left > Duration.zero) await Future<void>.delayed(left);
              } else {
                await gateDenied(
                  ownerGate.acquire(
                    deadline: const Duration(milliseconds: 150),
                  ),
                  'TIMEOUT',
                );
              }
              var changed = false;
              final mutation = Future<void>(() async {
                if (mode != 'publish-order') return;
                await revokeThroughOwner();
                changed = true;
              });
              mutation.ignore();
              if (mode == 'publish-order') {
                await until(() => mutationEntered);
                await Future<void>.delayed(const Duration(milliseconds: 50));
                n.check(!changed);
              }
              File(p.join(root, 'publication.release'))
                  .writeAsStringSync('release');
              final reply = await client.next();
              await mutation;
              if (mode == 'publish-expiry') {
                n.check(
                  (reply['result'] as Map)['isError'] == true &&
                      !jsonEncode(reply).contains('ordinal'),
                );
              } else {
                n.check(
                  changed && (reply['result'] as Map)['isError'] == false,
                );
                client.call('after');
                final denied = await client.next();
                n.check(
                  (denied['result'] as Map)['isError'] == true &&
                      services.calls == 1,
                );
              }
            } else if (mode == 'stdout-stop') {
              File(p.join(root, 'gateway-fixture-phase'))
                  .writeAsStringSync('call');
              client.call('blocked');
              await until(() => services.calls == 1);
              await publicationHeld(root);
              await gateDenied(
                ownerGate.acquire(deadline: const Duration(milliseconds: 150)),
                'TIMEOUT',
              );
              File(p.join(root, 'gateway-fixture-phase'))
                  .writeAsStringSync('child-exit');
              n.check(
                await child.exitCode.timeout(const Duration(seconds: 13)) == 2,
              );
              File(p.join(root, 'gateway-fixture-phase'))
                  .writeAsStringSync('abandon');
              await gateDenied(ownerGate.acquire(), 'SERVICE_UNAVAILABLE');
              await until(() => ownerGate!.activeAcquisitions == 0);
              File(p.join(root, 'gateway-fixture-phase'))
                  .writeAsStringSync('gate-close');
              await n.fails(ownerGate.close(), 'SERVICE_UNAVAILABLE');
            } else if (mode == 'stdout-revoke') {
              client.call('first');
              await until(() => services.calls == 1);
              await publicationHeld(root);
              client.call('stale');
              await until(() => services.calls == 2);
              var changed = false;
              final mutation = Future<void>(() async {
                await revokeThroughOwner();
                changed = true;
              });
              mutation.ignore();
              await until(() => mutationEntered);
              await Future<void>.delayed(const Duration(milliseconds: 80));
              n.check(!changed);
              final first = await client.next();
              n.check(
                first['id'] == 'first' &&
                    (((first['result'] as Map)['structuredContent']
                                    as Map)['data']
                                as Map)['large']
                            .toString()
                            .length ==
                        1024 * 1024,
              );
              await mutation;
              n.check(changed);
              await until(
                () => File(p.join(root, 'publication.queued')).existsSync(),
              );
              File(p.join(root, 'publication.mutated'))
                  .writeAsStringSync('mutated');
              final second = await client.next();
              n.check(
                second['id'] == 'stale' &&
                    (second['result'] as Map)['isError'] == true &&
                    !jsonEncode(second).contains('ordinal'),
              );
            } else if (mode == 'revoke') {
              held = await ownerGate.acquire();
              client.call('queued');
              await until(() => services.calls == 1);
              await Future<void>.delayed(const Duration(milliseconds: 300));
              await write('grant.revoke');
              await held.close();
              held = null;
              final reply = await client.next();
              n.check(
                reply['id'] == 'queued' &&
                    (reply['result'] as Map)['isError'] == true &&
                    !jsonEncode(reply).contains('ordinal'),
              );
            } else {
              throw StateError('UNKNOWN_MODE');
            }
          }
          if (mode == 'stdout-stop')
            File(p.join(root, 'gateway-fixture-phase'))
                .writeAsStringSync('finish-client');
          await n.finishClient(child);
          n.check(await child.exitCode == (mode == 'stdout-stop' ? 2 : 0));
          final diagnostics = await client.errors;
          n.check(
            diagnostics.isEmpty ||
                (mode == 'stdout-stop' &&
                    diagnostics.contains('MCP:WRITE_FAILED') &&
                    diagnostics.contains('MCP:CLOSE_FAILED') &&
                    diagnostics
                        .trim()
                        .split('\n')
                        .every(
                          (line) => const {
                            'MCP:WRITE_FAILED',
                            'MCP:CLOSE_FAILED',
                            'MCP:CANCEL_FAILED',
                          }.contains(line.trim()),
                        )) ||
                ((mode == 'wrong-cancel' ||
                        mode == 'cancel-timeout' ||
                        mode == 'overall') &&
                    diagnostics.trim() == 'MCP:CANCEL_FAILED'),
          );
          if (mode == 'stdout-stop')
            File(p.join(root, 'gateway-fixture-phase'))
                .writeAsStringSync('serving');
          await serving.timeout(const Duration(seconds: 12));
          if (mode == 'eof')
            n.check(services.cancels == 1 && services.calls == 1);
        } finally {
          await held?.close();
          for (var i = 0; i < services.results.length; i++) {
            services.finish(i);
          }
          try {
            if (mode == 'stdout-stop')
              File(p.join(root, 'gateway-fixture-phase'))
                  .writeAsStringSync('cleanup-channel');
            if (channel != null) await channel.close();
          } finally {
            if (routerReady) router.close();
            if (mode == 'stdout-stop')
              File(p.join(root, 'gateway-fixture-phase'))
                  .writeAsStringSync('cleanup-child');
            child?.kill();
            if (child != null) await child.exitCode;
            if (mode == 'stdout-stop')
              File(p.join(root, 'gateway-fixture-phase'))
                  .writeAsStringSync('cleanup-lines');
            await transport?.lines.cancel();
            await mutationOwner?.close();
            try {
              try {
                if (mode == 'stdout-stop')
                  File(p.join(root, 'gateway-fixture-phase'))
                      .writeAsStringSync('cleanup-gate');
                await ownerGate?.close();
              } on StateError catch (error) {
                if (mode != 'stdout-stop' ||
                    error.message != 'SERVICE_UNAVAILABLE')
                  rethrow;
              }
            } finally {
              if (mode == 'stdout-stop')
                File(p.join(root, 'gateway-fixture-phase'))
                    .writeAsStringSync('cleanup-worker');
              try {
                try {
                  await nativeRegistry?.close();
                } on StateError catch (error) {
                  if (mode != 'stdout-stop' ||
                      error.message != 'SERVICE_UNAVAILABLE')
                    rethrow;
                }
              } finally {
                await worker.close();
              }
            }
          }
        }
      },
    );
    stdout.writeln('PASS:$mode');
  } catch (error, stack) {
    stderr.writeln('GATEWAY_FIXTURE_FAILED');
    if (error is McpGatewayFailure) stderr.writeln(error.code.wireName);
    if (error is StateError &&
        const {
          'TIMEOUT',
          'UNAUTHORIZED',
          'SERVICE_UNAVAILABLE',
          'RESOURCE_LIMIT',
          'FORBIDDEN',
        }.contains(error.message))
      stderr.writeln(error.message);
    stderr.writeln(stack.toString().split('\n').take(8).join('\n'));
    exitCode = 1;
  }
}
