import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:serverdeck_locald/api/operational_auth.dart';

import 'package:serverdeck_locald/mcp/router.dart';
import 'package:serverdeck_locald/storage/state_store.dart';

import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/codec.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'mcp_runtime_actor.dart' as runtime;
import 'trusted_auth_actor.dart' as native;
import 'trusted_grant_actor.dart' as grant;

Map<String, Object?> body() => {
  'format': 1,
  'environment': 'ubuntu24.04-amd64-systemd',
  'parameters': <String, Object?>{},
  'steps': <Object?>[],
};

final class Pending {
  final result = Completer<McpToolResult>(), cleanup = Completer<void>();
  int cancelled = 0;
}

/// Scheduling fixture only; not qualification of remote services.
final class Services implements TrustedMcpToolServices {
  bool delayed = false, throwCleanup = false;
  bool invalidDepth = false;
  McpToolResult output() {
    var data = <String, Object?>{'v': 0};
    for (var i = 0; i < 13; i++) {
      data = {'v': data};
    }
    return McpToolResult.success(data);
  }

  final pending = <Pending>[], contexts = <TrustedMcpContext>[];
  int calls = 0;
  @override
  McpServiceOperation start(
    TrustedMcpContext context,
    McpToolDefinition tool,
    Map<String, Object?> args,
  ) {
    calls++;
    contexts.add(context);
    if (!delayed) {
      AutomationBody.fromJson(args['body'] as Map<String, Object?>);
      return McpServiceOperation(
        Future.sync(
          () => invalidDepth
              ? output()
              : McpToolResult.success({'valid': true, 'issues': <Object?>[]}),
        ),
        () async {},
      );
    }
    final p = Pending();
    pending.add(p);
    return McpServiceOperation(
      p.result.future.then((result) => invalidDepth ? output() : result),
      () {
        p.cancelled++;
        if (throwCleanup) throw StateError('PRIVATE_CLEANUP');
        return p.cleanup.future;
      },
    );
  }

  void release() {
    for (final p in pending) {
      if (!p.result.isCompleted)
        p.result.complete(McpToolResult.success({'late': 'e\u0301\n😀'}));
      if (!p.cleanup.isCompleted) p.cleanup.complete();
    }
  }
}

Future<void> drained(TrustedMcpRouter router, int expected) async {
  final watch = Stopwatch()..start();
  while (router.chargedOperations != expected) {
    native.check(watch.elapsed < const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> run(
  String root,
  StateStore store,
  TrustedMcpAuthority authority,
  TrustedSessions registry,
  native.Pair first,
  Future<void> Function(String) write,
  void Function(Duration) advanceWall,
  String mode,
) async {
  final services = Services();
  var elapsed = Duration.zero;
  final removeFault = mode == 'detach-listener-failure'
      ? registry.onSessionDetached((_) => throw StateError('PRIVATE_CALLBACK'))
      : null;
  final router = TrustedMcpRouter(
    sessions: registry,
    authority: authority,
    services: services,
    elapsed: () => elapsed,
  );
  final pairs = <native.Pair>[];
  Future<McpInvokeReply> invoke(
    Object? params, {
    native.Pair? pair,
    String method = 'mcp.invoke',
  }) async {
    final p = pair ?? first,
        request = await registry.begin(
          (pair ?? first).channel,
          (pair ?? first).response!.sessionId,
          method,
        );
    native.check(request.sessionId == p.response!.sessionId);
    try {
      return await router.invoke(
        request,
        params is Map
            ? StrictCodec().decode(utf8.encode(jsonEncode(params)))
            : params,
      );
    } finally {
      request.complete();
    }
  }

  Future<McpInvokeReply> start({native.Pair? pair}) => invoke({
    'request': {
      'name': 'serverdeck_profiles_validate',
      'arguments': {'body': body()},
    },
  }, pair: pair);
  String handle(McpInvokeReply r) {
    native.check(r.kind == McpInvokeReplyKind.pending);
    return r.toJson()['operationId'] as String;
  }

  Future<McpInvokeReply> poll(String id, {native.Pair? pair}) => invoke({
    'poll': {'operationId': id},
  }, pair: pair);
  Future<native.Pair> another({bool owner = false}) async {
    final p = await native.Pair.start(
      root,
      owner ? 'serverdeck.exe' : 'mcp.exe',
      registry,
    );
    pairs.add(p);
    await p.exchange();
    native.check(await p.next() == 'AUTH:${owner ? 'owner' : 'mcp'}');
    if (!owner) {
      final params = await grant.signedParams(root, p),
          request = await registry.begin(
            p.channel,
            p.response!.sessionId,
            'mcp.open',
          );
      try {
        await request.openGrant(authority, params);
      } finally {
        request.complete();
      }
    }
    return p;
  }

  try {
    switch (mode) {
      case 'depth-inline' || 'depth-pending':
        services.invalidDepth = true;
        services.delayed = mode == 'depth-pending';
        var reply = await start();
        String? operationId;
        if (services.delayed) {
          operationId = handle(reply);
          services.pending.single.result.complete(McpToolResult.success({}));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          reply = await poll(operationId);
        }
        final result = reply.toJson()['result'] as Map;
        native.check(
          reply.kind == McpInvokeReplyKind.done &&
              ((result['structuredContent'] as Map)['error'] as Map)['code'] ==
                  'INTERNAL',
        );
        if (operationId != null) {
          native.check(
            (await poll(operationId)).toJson().toString() ==
                reply.toJson().toString(),
          );
          native.check(router.chargedOperations == 1);
          services.pending.single.cleanup.complete();
          await invoke({
            'cancel': {'operationId': operationId},
          });
          native.check(services.pending.single.cancelled == 1);
        }
        break;
      case 'basic':
        final names =
            ((await invoke({'catalog': {}})).toJson()['tools'] as List)
                .map((t) => (t as Map)['name'])
                .toSet();
        native.check(
          names.length == 7 &&
              names.contains('serverdeck_profiles_validate') &&
              !names.contains('serverdeck_servers_list') &&
              router.chargedOperations == 0,
        );
        native.check(
          (await start()).kind == McpInvokeReplyKind.done &&
              services.calls == 1 &&
              router.chargedOperations == 0,
        );
        for (final input in <Object?>[
          {},
          {
            'catalog': {'extra': true},
          },
          {
            'poll': {'operationId': 'bad'},
          },
        ]) {
          try {
            await invoke(input);
            throw StateError('NO_VALIDATION');
          } on FormatException catch (e) {
            native.check(e.message == 'VALIDATION');
          }
        }
        for (final input in [
          {
            'request': {'name': 'serverdeck_shell', 'arguments': {}},
          },
          {
            'request': {
              'name': 'serverdeck_profiles_validate',
              'arguments': {'body': body(), 'extra': true},
            },
          },
        ]) {
          native.check(
            (await invoke(input)).kind == McpInvokeReplyKind.invalidParams,
          );
        }
        await native.fails(
          invoke({
            'request': {
              'name': 'serverdeck_server_get',
              'arguments': {'serverId': grant.requestId},
            },
          }),
          'FORBIDDEN',
        );
        native.check(services.calls == 1);
        final owner = await another(owner: true);
        await native.fails(
          invoke(null, pair: owner, method: 'grants.list'),
          'FORBIDDEN',
        );
        await native.fails(invoke(null, method: 'session.ping'), 'FORBIDDEN');
        final foreign = TrustedSessions(generation: native.generation);
        final foreignRouter = TrustedMcpRouter(
          sessions: foreign,
          authority: authority,
          services: services,
        );
        final original = await registry.begin(
          first.channel,
          first.response!.sessionId,
          'mcp.invoke',
        );
        try {
          await native.fails(foreignRouter.invoke(original, null), 'FORBIDDEN');
          native.check(services.calls == 1);
        } finally {
          original.complete();
          foreignRouter.close();
          await foreign.close();
        }
        services.delayed = true;
        final id = handle(await start());
        native.check((await poll(id)).kind == McpInvokeReplyKind.pending);
        await services.contexts.last
            .revalidate(); // Original RPC has completed.
        services.pending.single.result.complete(
          McpToolResult.success({'text': 'e\u0301\n😀'}),
        );
        await Future<void>.delayed(Duration.zero);
        final completed = await poll(id);
        native.check(
          completed.kind == McpInvokeReplyKind.done &&
              router.retainedOperations == 1,
        );
        native.check(
          (((completed.toJson()['result'] as Map)['structuredContent']
                      as Map)['data']
                  as Map)['text'] ==
              'e\u0301\n😀',
        );
        final other = await another();
        await native.fails(poll(id, pair: other), 'FORBIDDEN');
        await native.fails(
          invoke({
            'cancel': {'operationId': grant.requestId},
          }),
          'FORBIDDEN',
        );
      case 'revoke' ||
          'replace' ||
          'disconnect' ||
          'close' ||
          'expiry' ||
          'detach-listener-failure':
        services.delayed = true;
        await start();
        await start();
        services.pending.first.result.complete(
          McpToolResult.success({'cached': 'private observation'}),
        );
        await Future<void>.delayed(Duration.zero);
        native.check(
          router.retainedOperations == 2 && router.chargedOperations == 2,
        );
        if (mode == 'revoke' || mode == 'replace') {
          await write(mode == 'revoke' ? 'grant.revoke' : 'grant.replace');
          native.check(store.isTrustedSnapshotLoaded);
        } else if (mode == 'disconnect') {
          registry.disconnect(first.channel);
        } else if (mode == 'detach-listener-failure') {
          await native.fails(
            Future<Object?>.sync(() {
              registry.disconnect(first.channel);
              return null;
            }),
            'UNAUTHORIZED',
          );
        } else if (mode == 'close') {
          router.close();
        } else {
          advanceWall(const Duration(seconds: 300));
          router.sweep();
        }
        // No new invocation or poll since the lifecycle change.
        native.check(
          router.retainedOperations == 0 &&
              router.chargedOperations == 2 &&
              services.pending.every((p) => p.cancelled == 1),
        );
        services.release();
        await drained(router, 0);
        native.check(router.retainedOperations == 0);
      case 'quota':
        services.delayed = true;
        for (var n = 0; n < 16; n++) handle(await start());
        await native.fails(start(), 'RESOURCE_LIMIT');
        final second = await another();
        for (var n = 0; n < 16; n++) handle(await start(pair: second));
        final third = await another();
        await native.fails(start(pair: third), 'RESOURCE_LIMIT');
        native.check(services.calls == 32 && router.chargedOperations == 32);
        native.check(
          (await invoke({'catalog': {}}, pair: third)).kind ==
              McpInvokeReplyKind.catalog,
        );
        registry.disconnect(first.channel);
        registry.disconnect(second.channel);
        registry.disconnect(third.channel);
        native.check(
          router.retainedOperations == 0 && router.chargedOperations == 32,
        );
        final fourth = await another();
        await native.fails(start(pair: fourth), 'RESOURCE_LIMIT');
        native.check(
          services.calls == 32 &&
              services.pending.every((p) => p.cancelled == 1),
        );
        services.release();
        await drained(router, 0);
      case 'cancel' || 'cleanup-error':
        services.delayed = true;
        services.throwCleanup = mode == 'cleanup-error';
        final id = handle(await start()),
            cancel = {
              'cancel': {'operationId': id},
            };
        await native.fails(
          invoke(cancel),
          mode == 'cancel' ? 'TIMEOUT' : 'INTERNAL',
        );
        await native.fails(
          invoke(cancel),
          mode == 'cancel' ? 'TIMEOUT' : 'INTERNAL',
        );
        native.check(
          services.pending.single.cancelled == 1 &&
              router.chargedOperations == 1,
        );
        await native.fails(poll(id), 'FORBIDDEN');
        elapsed = const Duration(seconds: 60);
        router.sweep();
        await native.fails(invoke(cancel), 'FORBIDDEN');
        native.check(
          router.retainedOperations == 0 && router.chargedOperations == 1,
        );
        services.release();
        await drained(router, 0);
      case 'timeouts':
        services.delayed = true;
        final id = handle(await start());
        elapsed = const Duration(seconds: 30);
        router.sweep();
        final timed = await poll(id);
        native.check(
          ((((timed.toJson()['result'] as Map)['structuredContent']
                      as Map)['error']
                  as Map)['code']) ==
              'TIMEOUT',
        );
        native.check(
          services.pending.single.cancelled == 1 &&
              router.chargedOperations == 1,
        );
        services.pending.single.result.complete(
          McpToolResult.success({'must': 'discard'}),
        );
        await Future<void>.delayed(Duration.zero);
        native.check(router.chargedOperations == 1);
        elapsed = const Duration(seconds: 90);
        router.sweep();
        await native.fails(poll(id), 'FORBIDDEN');
        services.pending.single.cleanup.complete();
        await drained(router, 0);
        final next = handle(await start());
        services.pending.last.result.complete(
          McpToolResult.success({'ok': 'cached'}),
        );
        await Future<void>.delayed(Duration.zero);
        elapsed = const Duration(milliseconds: 149999);
        router.sweep();
        native.check((await poll(next)).kind == McpInvokeReplyKind.done);
        elapsed = const Duration(seconds: 150);
        router.sweep();
        await native.fails(poll(next), 'FORBIDDEN');
        await drained(router, 0);
      case 'late-deadline':
        services.delayed = true;
        final id = handle(await start());
        elapsed = const Duration(seconds: 30);
        services.pending.single.result.complete(
          McpToolResult.success({'too': 'late'}),
        );
        await Future<void>.delayed(Duration.zero);
        final reply = await poll(id);
        native.check(
          ((((reply.toJson()['result'] as Map)['structuredContent']
                      as Map)['error']
                  as Map)['code']) ==
              'TIMEOUT',
        );
        services.release();
      case 'native-failure':
        services.delayed = true;
        await start();
        runtime.manifest(
          root,
          (m) => (m['sha256'] as Map)['mcp.exe'] = '0' * 64,
        );
        await native.fails(
          services.contexts.single.revalidate(),
          'UNAUTHORIZED',
        );
        native.check(
          registry.count == 0 &&
              router.retainedOperations == 0 &&
              services.pending.single.cancelled == 1,
        );
        services.release();
        await drained(router, 0);
      default:
        throw StateError('UNKNOWN_ROUTER_CASE');
    }
  } finally {
    removeFault?.call();
    router.close();
    services.release();
    for (final p in pairs) await p.close();
    await drained(router, 0);
  }
}

Future<void> main(List<String> args) async {
  try {
    containCurrentFixtureTree();
    if (args.first == 'client') {
      if (args[3] == 'normal') {
        await native.client(args);
      } else {
        await grant.client(args);
      }
      return;
    }
    runtime.ownRoot(args[0]);
    await grant.scenario(
      args[0],
      'router-${args[1]}',
      routerRun: (root, store, authority, registry, pair, write, advance) =>
          run(root, store, authority, registry, pair, write, advance, args[1]),
    );

    stdout.writeln('PASS:${args[1]}');
  } catch (_, stack) {
    stderr.writeln('INVOCATION_FIXTURE_FAILED');
    // Owned synthetic fixture only; bounded call sites, never exception input.
    stderr.writeln(stack.toString().split('\n').take(10).join('\n'));
    exitCode = 1;
  }
}
