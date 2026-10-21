import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/api/operational_channel.dart';
import 'package:serverdeck_locald/api/operational_server.dart';
import 'package:serverdeck_locald/mcp/router.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'operational_auth_actor.dart' as n;
import 'operational_grant_actor.dart' as g;
import 'operational_channel_actor.dart' as wire;
import 'mcp_runtime_actor.dart' as runtime;

const foreign = '82345678-1234-4234-8234-123456789abc';
bool mcpMode(String mode) => mode == 'mcp' || mode == 'open-overlap';
bool actual(String mode) => const {
  'mcp',
  'open-overlap',
  'owner',
  'snapshot',
  'remote-error',
  'remote-timeout',
}.contains(mode);

Future<void> failure(
  Future<Object?> work,
  ErrorCode code,
  OperationalRpcFailureOrigin origin,
) async {
  try {
    await work;
  } on OperationalRpcException catch (error) {
    n.check(error.code == code && error.origin == origin);
    n.check(
      error.terminal == (origin == OperationalRpcFailureOrigin.transport),
    );
    return;
  }
  throw StateError('EXPECTED_RPC_FAILURE');
}

final class Owner implements OperationalOwnerApi {
  @override
  bool supports(String method) => const {
    'fixture.echo',
    'fixture.error',
    'fixture.timeout',
  }.contains(method);
  @override
  Future<Map<String, Object?>> dispatch(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params,
  ) async {
    if (method == 'fixture.error') throw StateError('SERVICE_UNAVAILABLE');
    if (method == 'fixture.timeout') throw StateError('TIMEOUT');
    return params;
  }
}

Future<void> client(List<String> args) async {
  final name = args[1], root = args[2], mode = args[3];
  runtime.ownRoot(root);
  final pipe = await PipeWorker.openOperationalClient(
    name,
    currentUserSid(),
    root,
  );
  final bootstrap = OperationalBootstrapClient(
    pipe: pipe,
    generation: n.generation,
    token: n.token,
  );
  try {
    final session = await bootstrap.authenticate();
    if (mcpMode(mode)) {
      final opening = session.openGrant(g.files(root), g.grantId);
      opening.ignore();
      if (mode == 'open-overlap') {
        try {
          OperationalApiClient(session);
          throw StateError('EXPECTED_PENDING_OPEN_REFUSAL');
        } on OperationalRpcException catch (error) {
          n.check(
            error.code == ErrorCode.serviceUnavailable &&
                error.origin == OperationalRpcFailureOrigin.local,
          );
        }
      }
      await opening;
    }
    final rpc = OperationalApiClient(session);
    try {
      try {
        OperationalApiClient(session);
        throw StateError('EXPECTED_EXCLUSIVE_CLAIM');
      } on OperationalRpcException catch (error) {
        n.check(error.code == ErrorCode.serviceUnavailable && !error.terminal);
      }
      await n.fails(
        session.openGrant(g.files(root), g.grantId),
        'SERVICE_UNAVAILABLE',
      );
      if (actual(mode)) {
        final view = OperationalReadiness.fromJson(
          await rpc.call('readiness.get', {}),
        );
        n.check(!view.features.any && view.generation == n.generation);
        await failure(
          rpc.call(mcpMode(mode) ? 'grants.list' : 'mcp.invoke', {}),
          ErrorCode.forbidden,
          OperationalRpcFailureOrigin.remote,
        );
        await failure(
          rpc.call('readiness.get', {'extra': true}),
          ErrorCode.validation,
          OperationalRpcFailureOrigin.remote,
        );
        await failure(
          rpc.call('', {}),
          ErrorCode.validation,
          OperationalRpcFailureOrigin.local,
        );
        if (mcpMode(mode)) {
          final catalog = await rpc.call('mcp.invoke', {
            'catalog': <String, Object?>{},
          });
          n.check((catalog['tools'] as List).length == 7);
          final result = await rpc.call('mcp.invoke', wire.validationCall());
          n.check(
            jsonEncode(
                  ((result['result'] as Map)['structuredContent']
                      as Map)['data'],
                ) ==
                jsonEncode(wire.data()),
          );
        } else if (mode == 'snapshot') {
          final value = <String, Object?>{
            'text': 'e\u0301😀',
            'items': <Object?>[1],
            'counter': 9223372036854775807,
          };
          final result = rpc.call('fixture.echo', value);
          value['text'] = 'changed';
          (value['items'] as List).add(2);
          final saved = await result;
          n.check(
            saved['text'] == 'e\u0301😀' &&
                saved['counter'] == 9223372036854775807,
          );
          n.check((saved['items'] as List).length == 1);
          try {
            (saved['items'] as List).clear();
            throw StateError('EXPECTED_IMMUTABLE');
          } on UnsupportedError {
            /* Expected immutable response. */
          }
        } else if (mode == 'remote-error' || mode == 'remote-timeout') {
          await failure(
            rpc.call(
              mode == 'remote-error' ? 'fixture.error' : 'fixture.timeout',
              {},
            ),
            mode == 'remote-error'
                ? ErrorCode.serviceUnavailable
                : ErrorCode.timeout,
            OperationalRpcFailureOrigin.remote,
          );
          n.check(!rpc.isClosed);
        }
        n.check((await rpc.call('session.ping', {}))['leaseSeconds'] == 60);
        n.check(
          (await rpc.call(
                mcpMode(mode) ? 'mcp.close' : 'session.close',
                {},
              ))['closed'] ==
              true,
        );
      } else if (mode == 'quota' || mode == 'out-of-order') {
        final count = mode == 'quota' ? 16 : 3;
        final order = <int>[];
        final calls = <Future<Map<String, Object?>>>[];
        for (var i = 0; i < count; i++) {
          final index = i;
          final call = rpc.call('fixture.echo', {'slot': i}).then((value) {
            order.add(index);
            return value;
          });
          call.ignore();
          calls.add(call);
        }
        n.check(rpc.pendingRequests == count);
        if (mode == 'quota') {
          await failure(
            rpc.call('fixture.echo', {}),
            ErrorCode.resourceLimit,
            OperationalRpcFailureOrigin.local,
          );
          n.check(rpc.pendingRequests == 16 && !rpc.isClosed);
        }
        final results = await Future.wait(calls);
        n.check(
          jsonEncode(order) ==
              jsonEncode(List.generate(count, (i) => count - i - 1)),
        );
        for (var i = 0; i < count; i++) n.check(results[i]['slot'] == i);
      } else if (mode == 'duplicate') {
        n.check((await rpc.call('fixture.echo', {}))['ok'] == true);
        await rpc.done;
        n.check(rpc.isClosed);
      } else if (mode == 'partial') {
        final watch = Stopwatch()..start();
        await rpc.done;
        n.check(watch.elapsed >= const Duration(seconds: 4) && rpc.isClosed);
      } else {
        final watch = Stopwatch()..start();
        final code = mode == 'timeout'
            ? ErrorCode.timeout
            : mode == 'eof'
            ? ErrorCode.serviceUnavailable
            : ErrorCode.unauthorized;
        final first = failure(
          rpc.call('fixture.echo', {}),
          code,
          OperationalRpcFailureOrigin.transport,
        );
        final second = failure(
          rpc.call('fixture.echo', {}),
          code,
          OperationalRpcFailureOrigin.transport,
        );
        await Future.wait([first, second]);
        if (mode == 'timeout')
          n.check(watch.elapsed >= const Duration(seconds: 4));
        n.check(rpc.isClosed && rpc.pendingRequests == 0);
        await failure(
          rpc.call('session.ping', {}),
          ErrorCode.serviceUnavailable,
          OperationalRpcFailureOrigin.transport,
        );
      }
      final close = rpc.close();
      n.check(identical(close, rpc.close()) && identical(close, rpc.done));
      await close;
      n.check(rpc.isClosed && rpc.pendingRequests == 0);
    } finally {
      await rpc.close();
    }
  } finally {
    await bootstrap.close();
  }
  stdout.writeln('CLIENT_PASS');
}

Future<Uint8List> fill(OperationalPipePeer peer, int count) async {
  final value = Uint8List(count);
  var offset = 0;
  while (offset < count) {
    final part = await peer.read(count: (count - offset).clamp(1, 65536));
    if (part.isEmpty) throw StateError('EOF');
    value.setRange(offset, offset + part.length, part);
    offset += part.length;
  }
  return value;
}

Future<void> controlled(
  OperationalServerHandshake handshake,
  PipeWorker worker,
  String mode,
) async {
  final peer = handshake.peer;
  final io = OperationalHandshakeIo(peer);
  final watch = Stopwatch()..start();
  Duration remaining() {
    final value = const Duration(seconds: 5) - watch.elapsed;
    if (value <= Duration.zero) throw StateError('TIMEOUT');
    return value;
  }

  await io.write((await handshake.hello()).toJson(), remaining);
  await io.write(
    (await handshake.authenticate(await io.read(remaining))).toJson(),
    remaining,
  );
  final requests = <Map<String, Object?>>[];
  final count = mode == 'partial'
      ? 0
      : mode == 'quota'
      ? 16
      : mode == 'out-of-order'
      ? 3
      : mode == 'duplicate'
      ? 1
      : 2;
  for (var i = 0; i < count; i++) {
    final size = ByteData.sublistView(await fill(peer, 4))
        .getUint32(0, Endian.little);
    n.check(size > 0 && size <= 256 * 1024);
    requests.add(StrictCodec().decode(await fill(peer, size)));
  }
  Future<void> send(
    Map<String, Object?> request,
    Map<String, Object?> result, {
    String? generation,
    String? id,
  }) => peer.write(
    frameBytes(
      encodeMcpMessage({
        'v': 1,
        'id': id ?? request['id'],
        'generation': generation ?? n.generation,
        'result': result,
      }),
    ),
  );
  if (mode == 'out-of-order' || mode == 'quota') {
    for (final request in requests.reversed)
      await send(request, request['params'] as Map<String, Object?>);
  } else if (mode == 'wrong-generation') {
    await send(requests.first, {}, generation: foreign);
  } else if (mode == 'wrong-id') {
    await send(requests.first, {}, id: foreign);
  } else if (mode == 'duplicate') {
    await send(requests.single, {'ok': true});
    await send(requests.single, {'ok': true});
  } else if (mode == 'malformed') {
    await peer.write(frameBytes([255]));
  } else if (mode == 'oversize') {
    final header = ByteData(4)
      ..setUint32(0, 8 * 1024 * 1024 + 1, Endian.little);
    await peer.write(header.buffer.asUint8List());
  } else if (mode == 'partial') {
    await peer.write([1, 0]);
  } else if (mode == 'eof') {
    await worker.disconnect();
    return;
  }
  try {
    await peer.read(deadline: const Duration(seconds: 8));
    throw StateError('EXPECTED_CLIENT_EOF');
  } on StateError catch (error) {
    n.check(
      const {'UNAUTHORIZED', 'SERVICE_UNAVAILABLE'}.contains(error.message),
    );
  }
}

Future<void> main(List<String> args) async {
  try {
    containCurrentFixtureTree();
    if (args.first == 'rpc-client') {
      await client(args);
      return;
    }
    final mode = args[1];
    await g.scenario(
      args[0],
      'rpc-$mode',
      readyRun: (root, store, authority, registry, write, advance) async {
        final name = n.pipeName();
        final endpoint = await PipeWorker.createOperationalServer(
          name,
          currentUserSid(),
          root,
        );
        final router = McpRouter(
          sessions: registry,
          authority: authority,
          services: wire.Services('basic'),
        );
        Process? child;
        OperationalServerHandshake? handshake;
        OperationalServerChannel? channel;
        StreamIterator<String>? lines;
        try {
          final accepting = endpoint.accept();
          child = await Process.start(
            p.join(root, mcpMode(mode) ? 'mcp.exe' : 'serverdeck.exe'),
            ['rpc-client', name, root, mode],
          );
          final errors = child.stderr.transform(utf8.decoder).join();
          lines = StreamIterator(
            child.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter()),
          );
          await accepting;
          handshake = OperationalServerHandshake(
            peer: await endpoint.verifyOperationalPeer(),
            token: n.token,
            channel: name,
            sessions: registry,
          );
          Future<void> serving;
          if (actual(mode)) {
            channel = OperationalServerChannel(
              handshake: handshake,
              server: OperationalApiServer(
                sessions: registry,
                authority: authority,
                router: router,
                owner: Owner(),
                readiness: () => OperationalReadiness(
                  state: ReadinessState.ready,
                  generation: n.generation,
                  workspaceId: g.workspaceId,
                ),
              ),
            );
            serving = channel.run();
          } else {
            serving = controlled(handshake, endpoint, mode);
          }
          serving.ignore();
          final next = await lines.moveNext().timeout(
            const Duration(seconds: 20),
          );
          if (!next) stderr.write(await errors);
          n.check(next && lines.current == 'CLIENT_PASS');
          await n.finishClient(child);
          n.check(await child.exitCode == 0 && (await errors).isEmpty);
          await serving.timeout(const Duration(seconds: 12));
        } finally {
          if (channel != null) await channel.close();
          handshake?.close();
          router.close();
          child?.kill();
          if (child != null) await child.exitCode;
          await lines?.cancel();
          await endpoint.close();
        }
      },
    );
    stdout.writeln('PASS:$mode');
  } catch (error, stack) {
    stderr.writeln('RPC_FIXTURE_FAILED');
    if (error is OperationalRpcException)
      stderr.writeln('${error.code.name}:${error.origin.name}');
    stderr.writeln(stack.toString().split('\n').take(8).join('\n'));
    exitCode = 1;
  }
}
