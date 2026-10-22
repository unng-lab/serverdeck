import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/api/operational_server.dart';
import 'package:serverdeck_locald/api/operational_channel.dart';
import 'package:serverdeck_locald/mcp/router.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'operational_auth_actor.dart' as n;
import 'operational_grant_actor.dart' as g;
import 'mcp_runtime_actor.dart' as runtime;

Map<String, Object?> data() => {
  'text': 'e\u0301😀',
  'counter': 9223372036854775807,
};

Map<String, Object?> depthData(String mode) {
  var value = <String, Object?>{'v': 0};
  for (var i = 0; i < (mode.contains('-over-') ? 12 : 11); i++) {
    value = {'v': value};
  }
  return value;
}

int wireDepth(Object? value) {
  final children = value is Map
      ? value.values
      : value is List
      ? value
      : const <Object?>[];
  var depth = 0;
  for (final child in children) {
    final candidate = wireDepth(child) + 1;
    if (candidate > depth) depth = candidate;
  }
  return depth;
}

bool ownerMode(String mode) => const {
  'owner',
  'backpressure',
  'rpc-timeout',
  'output-error',
}.contains(mode);
bool pendingMode(String mode) => const {
  'pending',
  'eof',
  'reentrant-close',
  'depth-pending',
  'depth-over-pending',
}.contains(mode);
Map<String, Object?> validationCall() => {
  'request': {
    'name': 'serverdeck_profiles_validate',
    'arguments': {
      'body': {
        'format': 1,
        'environment': 'ubuntu24.04-amd64-systemd',
        'parameters': <String, Object?>{},
        'steps': <Object?>[],
      },
    },
  },
};
Future<void> closed(Future<Object?> future) async {
  try {
    await future;
  } on StateError catch (error) {
    n.check(
      const {
        'EOF',
        'UNAUTHORIZED',
        'SERVICE_UNAVAILABLE',
      }.contains(error.message),
    );
    return;
  }
  throw StateError('EXPECTED_CLOSED');
}

final class Services implements McpToolServices {
  Services(this.mode);
  final String mode;
  final pending = Completer<McpToolResult>();
  int calls = 0;
  Future<void> Function()? onCancel;
  McpToolResult output() => McpToolResult.success(
    mode.startsWith('depth-')
        ? depthData(mode)
        : mode == 'writer-revoke'
        ? {'large': 'x' * (1024 * 1024)}
        : data(),
  );
  @override
  McpServiceOperation start(
    OperationalMcpContext context,
    McpToolDefinition definition,
    Map<String, Object?> arguments,
  ) {
    calls++;
    return McpServiceOperation(
      pendingMode(mode)
          ? pending.future.then(
              (value) => mode.startsWith('depth-') ? output() : value,
            )
          : Future.sync(output),
      () async {
        await onCancel?.call();
      },
    );
  }
}

final class Owner implements OperationalOwnerApi {
  Owner(this.mode);
  final String mode;
  final gate = Completer<void>();
  int calls = 0, settled = 0;
  @override
  bool supports(String method) => method == 'fixture.wait';
  @override
  OperationalOwnerInvocation prepare(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    return OperationalOwnerInvocation(request, () async {
      final number = ++calls;
      if (mode == 'output-error') return {'invalid': Object()};
      await gate.future;
      settled++;
      return {'number': number};
    });
  }
}

final class Client {
  Client(this.session);
  final OperationalClientSession session;
  int counter = 0;
  int? bufferedSize;
  bool holdReplyTail = false;
  Future<Uint8List> fill(int count) async {
    final buffer = Uint8List(count);
    var offset = 0;
    while (offset < count) {
      final bytes = await session.peer.read(
        count: (count - offset).clamp(1, 65536),
        deadline: const Duration(seconds: 8),
      );
      if (bytes.isEmpty) throw StateError('EOF');
      n.check(bytes.length <= count - offset);
      buffer.setRange(offset, offset + bytes.length, bytes);
      offset += bytes.length;
      if (holdReplyTail &&
          count > 65536 &&
          count - offset > 0 &&
          count - offset <= 65536) {
        holdReplyTail = false;
        // Let the server's write complete with its final kernel-buffered tail
        // unread. Disconnect must not discard this already-issued frame tail.
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    return buffer;
  }

  Future<void> header() async {
    bufferedSize = ByteData.sublistView(await fill(4))
        .getUint32(0, Endian.little);
  }

  Future<Map<String, Object?>> read() async {
    final size =
        bufferedSize ??
        ByteData.sublistView(await fill(4)).getUint32(0, Endian.little);
    bufferedSize = null;
    n.check(size > 0 && size <= 8 * 1024 * 1024);
    final value = StrictCodec().decode(
      await fill(size),
      maxBytes: 8 * 1024 * 1024,
    );
    validateResponseEnvelope(value);
    n.check(value['generation'] == session.hello.generation);
    return value;
  }

  Future<String> send(
    String method,
    Map<String, Object?> params, {
    String? sessionId,
  }) async {
    final id =
        '52345678-1234-4234-8234-${(++counter).toString().padLeft(12, '0')}';
    await session.peer.write(
      frameBytes(
        encodeMcpMessage({
          'v': 1,
          'id': id,
          'sessionId': sessionId ?? session.id,
          'method': method,
          'params': params,
        }),
      ),
    );
    return id;
  }

  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params, {
    String? sessionId,
  }) async {
    final id = await send(method, params, sessionId: sessionId);
    final response = await read();
    n.check(response['id'] == id);
    return response;
  }
}

Future<void> client(List<String> args) async {
  final root = args[2], mode = args[3];
  runtime.ownRoot(root);
  final pipe = await PipeWorker.openOperationalClient(
    args[1],
    currentUserSid(),
    root,
  );
  if (mode == 'bootstrap-timeout') {
    final io = OperationalHandshakeIo(await pipe.verifyOperationalPeer());
    await io.read(() => const Duration(seconds: 8));
    final watch = Stopwatch()..start();
    await closed(io.read(() => const Duration(seconds: 8)));
    n.check(watch.elapsed >= const Duration(seconds: 4));
    await pipe.close();
    stdout.writeln('CLIENT_PASS');
    return;
  }
  final bootstrap = OperationalBootstrapClient(
    pipe: pipe,
    generation: n.generation,
    token: n.token,
  );
  try {
    final session = await bootstrap.authenticate();
    final rpc = Client(session);
    Future<void> done() async {
      await session.close();
      stdout.writeln('CLIENT_PASS');
    }

    final readiness = await rpc.call('readiness.get', {});
    final view = OperationalReadiness.fromJson(readiness['result']);
    n.check(view.generation == session.hello.generation && !view.features.any);
    n.check(
      view.state ==
          (mode == 'store-blocked'
              ? ReadinessState.storageBlocked
              : ReadinessState.ready),
    );
    final denied = await rpc.call(
      ownerMode(mode) ? 'mcp.invoke' : 'grants.list',
      {},
    );
    n.check((denied['error'] as Map)['code'] == 'FORBIDDEN');
    final invalidReadiness = await rpc.call('readiness.get', {'extra': true});
    n.check((invalidReadiness['error'] as Map)['code'] == 'VALIDATION');
    if (const {
      'malformed',
      'duplicate',
      'oversize',
      'partial',
      'wrong-session',
    }.contains(mode)) {
      if (mode == 'wrong-session') {
        await closed(
          rpc.call(
            'session.ping',
            {},
            sessionId: base64Url.encode(List.filled(32, 7)).replaceAll('=', ''),
          ),
        );
      } else {
        final watch = Stopwatch()..start();
        if (mode == 'partial') {
          await session.peer.write([1, 2]);
        } else if (mode == 'oversize') {
          final header = ByteData(4)
            ..setUint32(0, 256 * 1024 + 1, Endian.little);
          await session.peer.write(header.buffer.asUint8List());
        } else if (mode == 'duplicate') {
          await session.peer.write(
            frameBytes(
              utf8.encode(
                '{"v":1,"id":"${g.requestId}","sessionId":"${session.id}","method":"session.ping","method":"session.close","params":{}}',
              ),
            ),
          );
        } else {
          await session.peer.write(frameBytes([255]));
        }
        await closed(rpc.read());
        if (mode == 'partial')
          n.check(watch.elapsed >= const Duration(seconds: 4));
      }
      await done();
      return;
    }
    if (!ownerMode(mode)) {
      final unopened = await rpc.call('mcp.invoke', {
        'catalog': <String, Object?>{},
      });
      n.check((unopened['error'] as Map)['code'] == 'FORBIDDEN');
      final invalidOpen = <String, Object?>{
        'grantId': g.grantId,
        'clientNonce': base64Url.encode(List.filled(32, 8)).replaceAll('=', ''),
        'proof': base64Url.encode(List.filled(32, 0)).replaceAll('=', ''),
      };
      if (mode == 'badproof') {
        final failed = await rpc.call('mcp.open', invalidOpen);
        n.check((failed['error'] as Map)['code'] == 'UNAUTHORIZED');
        await closed(rpc.call('session.ping', {}));
        await done();
        return;
      }
      if (mode == 'store-blocked') {
        await n.fails(
          session.openGrant(g.files(root), g.grantId),
          'STORAGE_BLOCKED',
        );
        await done();
        return;
      }
      if (mode == 'client-disconnect') {
        await n.fails(session.peer.disconnect(), 'UNSAFE_ENDPOINT');
      }
      await session.openGrant(g.files(root), g.grantId);
      if (mode == 'second-open') {
        await closed(rpc.call('mcp.open', invalidOpen));
        await done();
        return;
      }
      if (mode.startsWith('policy-') ||
          mode == 'native-failure' ||
          mode == 'worker-loss') {
        stdout.writeln('FAULT');
        await stdin.first;
        await closed(rpc.call('mcp.invoke', {'catalog': <String, Object?>{}}));
        await done();
        return;
      }
      final catalog = await rpc.call('mcp.invoke', {
        'catalog': <String, Object?>{},
      });
      n.check(
        ((catalog['result'] as Map)['tools'] as List).length ==
            (mode == 'all' ? 24 : 7),
      );
      final unknown = await rpc.call('mcp.invoke', {
        'request': {'name': 'NEVER_ECHO', 'arguments': <String, Object?>{}},
      });
      n.check(
        ((unknown['result'] as Map)['protocolError'] as Map)['code'] == -32602,
      );
      n.check(!jsonEncode(unknown).contains('NEVER_ECHO'));
      final union = await rpc.call('mcp.invoke', {
        'catalog': <String, Object?>{},
        'extra': true,
      });
      n.check((union['error'] as Map)['code'] == 'VALIDATION');
      if (mode == 'writer-revoke') {
        final first = await rpc.send('mcp.invoke', validationCall());
        await rpc.send('mcp.invoke', validationCall());
        await rpc.header();
        stdout.writeln('FAULT');
        await stdin.first;
        rpc.holdReplyTail = true;
        final published = await rpc.read();
        n.check(published['id'] == first);
        n.check(
          (((published['result'] as Map)['result'] as Map)['structuredContent']
                  as Map)['ok'] ==
              true,
        );
        await closed(rpc.read());
        await done();
        return;
      }
      var reply = await rpc.call('mcp.invoke', validationCall());
      if (mode == 'eof' || mode == 'reentrant-close') {
        n.check((reply['result'] as Map)['done'] == false);
        await done();
        return;
      }
      if (mode == 'pending' || mode.endsWith('-pending')) {
        final handle = (reply['result'] as Map)['operationId'];
        n.check(handle is String);
        stdout.writeln('PENDING');
        await stdin.first;
        reply = await rpc.call('mcp.invoke', {
          'poll': {'operationId': handle},
        });
        if (mode.startsWith('depth-')) {
          final repeated = await rpc.call('mcp.invoke', {
            'poll': {'operationId': handle},
          });
          n.check(
            jsonEncode(repeated['result']) == jsonEncode(reply['result']),
          );
        }
        final cancelled = await rpc.call('mcp.invoke', {
          'cancel': {'operationId': handle},
        });
        n.check((cancelled['result'] as Map)['cancelled'] == true);
      }
      final tool =
          ((reply['result'] as Map)['result'] as Map)['structuredContent']
              as Map;
      if (mode.startsWith('depth-')) {
        if (mode.contains('-over-')) {
          n.check(
            jsonEncode(tool) ==
                jsonEncode(
                  McpToolResult.failure('INTERNAL')
                      .toJson()['structuredContent'],
                ),
          );
        } else {
          n.check(jsonEncode(tool['data']) == jsonEncode(depthData(mode)));
          n.check(wireDepth(reply) == 16);
        }
      } else {
        n.check(jsonEncode(tool['data']) == jsonEncode(data()));
      }
    } else {
      final unknown = await rpc.call('grants.list', {});
      n.check((unknown['error'] as Map)['code'] == 'UNSUPPORTED');
      if (mode == 'backpressure') {
        final ids = <String>{};
        final watch = Stopwatch()..start();
        var received = 0;
        try {
          for (var i = 0; i < 17; i++) {
            ids.add(await rpc.send('fixture.wait', {}));
          }
          stdout.writeln('SENT17');
          for (var i = 0; i < 17; i++) {
            n.check(ids.remove((await rpc.read())['id']));
            received++;
          }
          n.check(ids.isEmpty);
        } catch (_) {
          stderr.writeln(
            'BACKPRESSURE_RECEIVED:$received;ELAPSED_MS:${watch.elapsedMilliseconds}',
          );
          rethrow;
        }
      } else if (mode == 'rpc-timeout') {
        await rpc.send('fixture.wait', {});
        stdout.writeln('WAIT');
        final watch = Stopwatch()..start();
        await closed(rpc.read());
        n.check(watch.elapsed >= const Duration(seconds: 4));
        await done();
        return;
      } else if (mode == 'output-error') {
        final invalid = await rpc.call('fixture.wait', {});
        n.check((invalid['error'] as Map)['code'] == 'INTERNAL');
      }
    }
    final closeAck = await rpc.call(
      ownerMode(mode) ? 'session.close' : 'mcp.close',
      {},
    );
    n.check((closeAck['result'] as Map)['closed'] == true);
    await done();
  } finally {
    await bootstrap.close();
  }
}

Future<void> main(List<String> args) async {
  try {
    containCurrentFixtureTree();
    if (args.first == 'wire-client') {
      await client(args);
      return;
    }
    final mode = args[1];
    await g.scenario(
      args[0],
      'channel-$mode',
      readyRun: (root, store, authority, registry, write, advance) async {
        final services = Services(mode);
        final owner = Owner(mode);
        final router = McpRouter(
          sessions: registry,
          authority: authority,
          services: services,
        );
        if (mode == 'store-blocked') await store.close();
        final server = OperationalApiServer(
          sessions: registry,
          authority: authority,
          router: router,
          owner: ownerMode(mode) && mode != 'owner' ? owner : null,
          readiness: () => OperationalReadiness(
            state: store.isAutomationReady
                ? ReadinessState.ready
                : ReadinessState.storageBlocked,
            generation: n.generation,
            workspaceId: g.workspaceId,
          ),
        );
        final name = n.pipeName();
        final worker = await PipeWorker.createOperationalServer(
          name,
          currentUserSid(),
          root,
        );
        Process? child;
        OperationalServerChannel? channel;
        StreamIterator<String>? lines;
        try {
          final accepting = worker.accept();
          child = await Process.start(
            p.join(root, ownerMode(mode) ? 'serverdeck.exe' : 'mcp.exe'),
            ['wire-client', name, root, mode],
          );
          final errors = child.stderr.transform(utf8.decoder).join();
          lines = StreamIterator(
            child.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter()),
          );
          await accepting;
          final handshake = OperationalServerHandshake(
            peer: await worker.verifyOperationalPeer(),
            token: n.token,
            channel: name,
            sessions: registry,
          );
          channel = OperationalServerChannel(
            handshake: handshake,
            server: server,
          );
          if (mode == 'reentrant-close') {
            services.onCancel = () async {
              final first = channel!.close();
              n.check(identical(first, channel.close()));
              await first;
            };
          }
          final running = channel.run();
          running.ignore();
          n.check(await lines.moveNext().timeout(const Duration(seconds: 12)));
          if (mode == 'pending' || mode.endsWith('-pending')) {
            n.check(lines.current == 'PENDING');
            services.pending.complete(McpToolResult.success(data()));
            child.stdin.writeln('release');
            n.check(await lines.moveNext());
          }
          if (mode.startsWith('policy-') ||
              mode == 'native-failure' ||
              mode == 'worker-loss' ||
              mode == 'writer-revoke') {
            n.check(lines.current == 'FAULT');
            if (mode == 'writer-revoke') {
              final watch = Stopwatch()..start();
              while (channel.pendingPublications < 2) {
                n.check(watch.elapsed < const Duration(seconds: 3));
                await Future<void>.delayed(const Duration(milliseconds: 5));
              }
              n.check(services.calls == 2);
            }
            if (mode == 'worker-loss') {
              await worker.close();
            } else if (mode == 'policy-expiry') {
              advance(const Duration(seconds: 300));
            } else if (mode == 'native-failure') {
              runtime.manifest(
                root,
                (m) => (m['sha256'] as Map)['mcp.exe'] = '0' * 64,
              );
            } else {
              await write(
                mode == 'policy-replace' ? 'grant.replace' : 'grant.revoke',
              );
            }
            child.stdin.writeln('release');
            final continued = await lines.moveNext().timeout(
              const Duration(seconds: 12),
            );
            // This child is an owned synthetic fixture emitting fixed codes
            // and bounded stack frames only. Preserve its failure evidence.
            if (!continued) stderr.write(await errors);
            n.check(continued);
          }
          if (mode == 'backpressure') {
            n.check(lines.current == 'SENT17');
            final watch = Stopwatch()..start();
            while (owner.calls < 16) {
              n.check(watch.elapsed < const Duration(seconds: 3));
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            n.check(owner.calls == 16 && channel.activeRequests == 16);
            await Future<void>.delayed(const Duration(milliseconds: 30));
            n.check(owner.calls == 16);
            owner.gate.complete();
            final continued = await lines.moveNext().timeout(
              const Duration(seconds: 12),
            );
            if (!continued) stderr.write(await errors);
            n.check(continued);
          } else if (mode == 'rpc-timeout') {
            n.check(lines.current == 'WAIT');
            n.check(
              await lines.moveNext().timeout(const Duration(seconds: 12)),
            );
          }
          n.check(lines.current == 'CLIENT_PASS');
          await n.finishClient(child);
          n.check(await child.exitCode == 0 && (await errors).isEmpty);
          if (mode == 'worker-loss') {
            await n.fails(
              running.timeout(const Duration(seconds: 10)),
              'SERVICE_UNAVAILABLE',
            );
            final first = channel.close();
            n.check(identical(first, channel.close()));
            await n.fails(first, 'SERVICE_UNAVAILABLE');
          } else {
            await running.timeout(const Duration(seconds: 10));
          }
          n.check(registry.count == 0 && router.retainedOperations == 0);
          if (mode == 'eof' || mode == 'reentrant-close') {
            n.check(router.chargedOperations == 1);
            services.pending.complete(McpToolResult.success(data()));
            await Future<void>.delayed(const Duration(milliseconds: 20));
            n.check(router.chargedOperations == 0);
          }
          if (mode == 'backpressure')
            n.check(owner.calls == 17 && owner.settled == 17);
          if (mode == 'rpc-timeout') {
            n.check(owner.calls == 1 && owner.settled == 0);
            owner.gate.complete();
            await Future<void>.delayed(const Duration(milliseconds: 20));
            n.check(owner.settled == 1 && registry.count == 0);
          }
        } finally {
          if (!owner.gate.isCompleted) owner.gate.complete();
          if (!services.pending.isCompleted)
            services.pending.complete(McpToolResult.success(data()));
          if (mode == 'worker-loss' && channel != null) {
            await n.fails(channel.close(), 'SERVICE_UNAVAILABLE');
          } else {
            await channel?.close();
          }
          router.close();
          child?.kill();
          if (child != null) await child.exitCode;
          await lines?.cancel();
          await worker.close();
        }
      },
    );
    stdout.writeln('PASS:$mode');
  } catch (error, stack) {
    stderr.writeln('CHANNEL_FIXTURE_FAILED');
    if (error is StateError &&
        const {
          'TIMEOUT',
          'EOF',
          'UNAUTHORIZED',
          'SERVICE_UNAVAILABLE',
          'FIXTURE_ASSERTION',
          'RESOURCE_LIMIT',
        }.contains(error.message)) {
      stderr.writeln(error.message);
    } else if (error is FormatException) {
      stderr.writeln('INVALID_FRAME');
    }
    stderr.writeln(stack.toString().split('\n').take(8).join('\n'));
    exitCode = 1;
  }
}
