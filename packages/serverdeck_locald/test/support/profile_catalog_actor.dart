import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/api/operational_channel.dart';
import 'package:serverdeck_locald/api/operational_server.dart';
import 'package:serverdeck_locald/api/owner_foundation.dart';
import 'package:serverdeck_locald/api/owner_grants.dart';
import 'package:serverdeck_locald/api/owner_profiles.dart';
import 'package:serverdeck_locald/api/owner_service_probe.dart';
import 'package:serverdeck_locald/automation/profiles.dart';
import 'package:serverdeck_locald/mcp/profile_services.dart';
import 'package:serverdeck_locald/mcp/router.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/grant_write_probe.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'operational_auth_actor.dart' as a;
import 'operational_grant_actor.dart' as g;
import 'profile_catalog_storage_scenarios.dart' show catalogBody;

String id(int n) => '82345678-1234-4234-8234-${n.toString().padLeft(12, '0')}';
Map<String, Object?> create(int n) => {
  'requestId': id(n),
  'name': 'Synthetic catalog $n',
  'body': catalogBody(),
};

Future<void> cleanupCatalogFixture(
  List<Future<void> Function()> actions,
) async {
  Object? failure;
  StackTrace? trace;
  for (final action in actions) {
    try {
      await action();
    } catch (error, stack) {
      failure ??= error;
      trace ??= stack;
    }
  }
  if (failure != null) Error.throwWithStackTrace(failure, trace!);
}

/// Delays only delivery/start of a genuine shared read. Never creates authority
/// or replaces its actual result; ordinary fixture modes use the delegate.
final class DeferredCatalogServices implements McpToolServices {
  DeferredCatalogServices(this.delegate);
  final McpToolServices delegate;
  Future<McpToolResult>? observedResult;
  OperationalMcpContext? observedContext;
  bool deferStart = false, deferResult = false, consumed = false;
  final entered = Completer<void>(), completed = Completer<void>();
  final releaseStart = Completer<void>(), releaseResult = Completer<void>();
  @override
  McpServiceOperation start(
    OperationalMcpContext context,
    McpToolDefinition tool,
    Map<String, Object?> arguments,
  ) {
    observedContext = context;
    if (consumed ||
        tool.name != 'serverdeck_profiles_list' ||
        !deferStart && !deferResult) {
      final actual = delegate.start(context, tool, arguments);
      observedResult = actual.result;
      return actual;
    }
    consumed = true;
    entered.complete();
    McpServiceOperation? actual;
    var retired = false;
    final result = () async {
      if (deferStart) await releaseStart.future;
      if (retired) return McpToolResult.failure('NOT_READY');
      actual = delegate.start(context, tool, arguments);
      final value = await actual!.result;
      completed.complete();
      if (deferResult) await releaseResult.future;
      return value;
    }();
    return McpServiceOperation(result, () async {
      retired = true;
      await actual?.cancelInterest();
    });
  }

  void release() {
    if (!releaseStart.isCompleted) releaseStart.complete();
    if (!releaseResult.isCompleted) releaseResult.complete();
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
      await session.openGrant(g.files(args[2]), args[3]);
    client = OperationalApiClient(session);
    stdout.writeln('READY');
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      final input = jsonDecode(line) as Map;
      try {
        stdout.writeln(
          jsonEncode({
            'result': await client.call(
              input['method'] as String,
              Map<String, Object?>.from(input['params'] as Map),
            ),
          }),
        );
      } on OperationalRpcException catch (error) {
        stdout.writeln(jsonEncode({'error': error.code.wireName}));
      }
    }
  } finally {
    await client?.close();
    await pipe.close();
  }
}

final class Rpc {
  Rpc._(
    this.worker,
    this.child,
    this.lines,
    this.errors,
    this.channel,
    this.serving,
  );
  final PipeWorker worker;
  final Process child;
  final StreamIterator<String> lines;
  final Future<String> errors;
  final OperationalServerChannel channel;
  final Future<void> serving;
  bool _abandoned = false;
  static Future<Rpc> open(
    String root,
    OperationalSessions sessions,
    OperationalApiServer server, {
    String? grant,
  }) async {
    final name = a.pipeName();
    final worker = await PipeWorker.createOperationalServer(
      name,
      currentUserSid(),
      root,
    );
    Process? child;
    Future<String>? childErrors;
    try {
      final accepting = worker.accept();
      child = await Process.start(
        p.join(root, grant == null ? 'serverdeck.exe' : 'mcp.exe'),
        ['rpc-client', name, root, grant ?? 'owner'],
      );
      final lines = StreamIterator(
        child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      final errors = childErrors = child.stderr.transform(utf8.decoder).join();
      await accepting;
      final channel = OperationalServerChannel(
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
      a.check(
        await lines.moveNext().timeout(const Duration(seconds: 10)) &&
            lines.current == 'READY',
      );
      return Rpc._(worker, child, lines, errors, channel, serving);
    } catch (_) {
      child?.kill();
      if (child != null) await child.exitCode;
      if (childErrors != null) stderr.write(await childErrors);
      await worker.close();
      rethrow;
    }
  }

  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params,
  ) async {
    child.stdin.writeln(jsonEncode({'method': method, 'params': params}));
    a.check(await lines.moveNext().timeout(const Duration(seconds: 15)));
    a.check(lines.current.length < 8 * 1024 * 1024);
    return jsonDecode(lines.current) as Map<String, Object?>;
  }

  Future<Map<String, Object?>> owner(
    String operation,
    Map<String, Object?> arguments,
  ) async {
    final reply = await call('automation.profiles.$operation', arguments);
    if (reply['error'] case final String code)
      throw StateError('CATALOG_RPC_$code');
    return Map<String, Object?>.from(reply['result'] as Map);
  }

  Future<Map<String, Object?>> tool(
    String operation,
    Map<String, Object?> arguments, {
    String? failure,
  }) async {
    var reply = await call('mcp.invoke', {
      'request': {
        'name': 'serverdeck_profiles_$operation',
        'arguments': arguments,
      },
    });
    if (reply['error'] case final String code)
      throw StateError('CATALOG_RPC_$code');
    var value = Map<String, Object?>.from(reply['result'] as Map);
    final watch = Stopwatch()..start();
    while (value['done'] == false) {
      a.check(watch.elapsed < const Duration(seconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      reply = await call('mcp.invoke', {
        'poll': {'operationId': value['operationId']},
      });
      a.check(!reply.containsKey('error'));
      value = Map<String, Object?>.from(reply['result'] as Map);
    }
    final result = value['result'] as Map;
    final content = result['structuredContent'] as Map;
    if (failure != null) {
      a.check(
        result['isError'] == true &&
            (content['error'] as Map)['code'] == failure,
      );
      return {};
    }
    a.check(result['isError'] == false && content['ok'] == true);
    return Map<String, Object?>.from(content['data'] as Map);
  }

  Future<void> close() async {
    if (!_abandoned) await a.finishClient(child);
    await serving.timeout(const Duration(seconds: 10));
    if (!_abandoned)
      a.check(await child.exitCode == 0 && (await errors).isEmpty);
    await channel.close();
    await lines.cancel();
    await worker.close();
  }

  Future<void> abandon() async {
    _abandoned = true;
    child.kill();
    await child.exitCode;
    await channel.close();
  }
}

Future<void> until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    a.check(watch.elapsed < const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> deniedGate(OperationalPublicationGate gate) async {
  OperationalPublicationLease? acquired;
  try {
    acquired = await gate.acquire(deadline: const Duration(milliseconds: 100));
    throw StateError('EXPECTED_GATE_WAIT');
  } on StateError catch (error) {
    a.check(error.message == 'TIMEOUT');
  } finally {
    await acquired?.close();
  }
}

Future<void> main(List<String> args) async {
  containCurrentFixtureTree();
  if (args.first == 'rpc-client') {
    await rpcClient(args);
    return;
  }
  if (args.first == 'client') {
    await a.client(args);
    return;
  }
  final mode = args[1];
  g.PausedProtection? protection;
  Completer<void>? publicationRelease;
  try {
    await g.scenario(
      args[0],
      'catalog-$mode',
      inspectProtection: (value) => protection = value,
      readyRun: (root, store, authority, legacy, write, advance) async {
        final seed = await a.Pair.start(root, 'serverdeck.exe', legacy);
        final clients = <Rpc>[];
        OperationalSessions? registry;
        AutomationProfileService? service;
        OperationalFoundationOwnerApi? foundation;
        McpRouter? router;
        OperationalPublicationGate? external;
        OperationalPublicationLease? held;
        ReceiptKeyMaterial? key;
        DeferredCatalogServices? deferred;
        OperationalNativeObservation? nativeObservation;
        List<int>? originalManifest;
        try {
          await seed.exchange();
          a.check(await seed.next() == 'AUTH:owner');
          final sessions = registry =
              await OperationalSessions.withNativePublicationGate(
                generation: a.generation,
                peer: seed.peer!,
              );
          final local = p.join(root, 'private'), sid = currentUserSid();
          final custody = KeyCustody(DpapiProtection(), sid);
          final material = key = await custody.openReceiptKey(
            await readProtectedFile(
              local,
              p.join(g.files(root).directory, 'receipt-key.dpapi'),
              sid,
              maxBytes: 16384,
            ),
            g.workspaceId,
            g.keyId,
          );
          var wall = DateTime.now().toUtc();
          final catalog = service = AutomationProfileService(
            store: store,
            custody: custody,
            receiptKey: material,
            sessions: sessions,
            authority: authority,
            clock: () => wall,
          );
          final api = OperationalProfileOwnerApi(catalog);
          foundation = OperationalFoundationOwnerApi(
            store: store,
            coordinator: MutationCoordinator.operational(
              store,
              custody,
              material,
            ),
            sessions: sessions,
          );
          final services = deferred = DeferredCatalogServices(
            ProfileCatalogMcpServices(catalog),
          );
          var routerTime = Duration.zero;
          router = McpRouter(
            sessions: sessions,
            authority: authority,
            services: services,
            elapsed: mode.startsWith('retention-') ? () => routerTime : null,
          );
          final server = OperationalApiServer(
            sessions: sessions,
            authority: authority,
            router: router,
            owner: OperationalOwnerApiGroup([
              api,
              foundation,
              OperationalGrantOwnerApi(store: store, sessions: sessions),
            ]),
            readiness: () => OperationalReadiness(
              state: ReadinessState.ready,
              generation: a.generation,
              workspaceId: g.workspaceId,
            ),
          );
          Future<Rpc> client([String? grant]) async {
            final value = await Rpc.open(root, sessions, server, grant: grant);
            clients.add(value);
            return value;
          }

          final owner = await client();
          var authorityTime =
              store.operational.automation.grants[g.grantId]!.issuedAt;
          void alignAuthorityClock() {
            final now = DateTime.now().toUtc();
            advance(now.difference(authorityTime));
            authorityTime = now;
          }

          if (mode.startsWith('physical-')) {
            if (mode == 'physical-release-failure') {
              final mcp = await client(g.grantId);
              external = await seed.peer!.publicationGate(a.generation);
              sessions.failNextAuthorityLeaseReleaseForTest();
              // Outer RPC may be denied after generation poison. The actual
              // service result is retained separately, without replacing it.
              await mcp.call('mcp.invoke', {
                'request': {
                  'name': 'serverdeck_profiles_create',
                  'arguments': create(19600),
                },
              });
              final result = (await services.observedResult!).toJson();
              a.check(result['isError'] == true);
              a.check(
                ((result['structuredContent'] as Map)['error']
                        as Map)['code'] ==
                    'SERVICE_UNAVAILABLE',
              );
              a.check(
                store.isAutomationReady &&
                    store.operational.automation.profiles.length == 1 &&
                    store.operational.automation.receipts.containsKey(
                      id(19600),
                    ),
              );
              // Actual operation result has completed and retired before close;
              // only remembered physical completion failure can deny this close.
              final closing = catalog.close();
              a.check(identical(closing, catalog.close()));
              await a.fails(closing, 'SERVICE_UNAVAILABLE');
              await a.fails(external.acquire(), 'SERVICE_UNAVAILABLE');
            } else if (mode == 'physical-observer') {
              var effects = 0;
              var notifications = 0;
              final completions = <Future<void>>[];
              await a.fails(
                sessions.runAuthorityMutation<void>(
                  () async {
                    effects++;
                  },
                  observeNativeCompletion: (actual) {
                    notifications++;
                    completions.add(actual);
                    if (notifications == 2)
                      throw StateError('SYNTHETIC_OBSERVER_FAILURE');
                  },
                ),
                'SERVICE_UNAVAILABLE',
              );
              a.check(effects == 0 && notifications == 2);
              await Future.wait(completions);
              notifications = 0;
              await a.fails(
                sessions.runAuthorityMutation<void>(
                  () async {
                    effects++;
                  },
                  observeNativeCompletion: (_) {
                    notifications++;
                    throw StateError('SYNTHETIC_OBSERVER_FAILURE');
                  },
                ),
                'SERVICE_UNAVAILABLE',
              );
              a.check(effects == 0 && notifications == 2);
              external = await seed.peer!.publicationGate(a.generation);
              held = await external.acquire();
              await held.close();
              held = null;
            } else {
              final proof = mode.startsWith('physical-proof');
              final failure = mode.endsWith('-failure');
              final mcp = await client(g.grantId);
              Map initial;
              if (proof) {
                services.deferStart = true;
                final reply = await mcp.call('mcp.invoke', {
                  'request': {
                    'name': 'serverdeck_profiles_list',
                    'arguments': <String, Object?>{},
                  },
                });
                initial = reply['result'] as Map;
                nativeObservation = await mcp.channel.handshake.peer
                    .observeNextRevalidationForTest();
                services.releaseStart.complete();
              } else {
                nativeObservation = sessions
                    .observeNextAuthorityAcquisitionForTest();
                final reply = await mcp.call('mcp.invoke', {
                  'request': {
                    'name': 'serverdeck_profiles_create',
                    'arguments': create(19000),
                  },
                });
                initial = reply['result'] as Map;
              }
              a.check(initial['done'] == false);
              await nativeObservation.reached.timeout(
                const Duration(seconds: 3),
              );
              await Future<void>.delayed(const Duration(milliseconds: 5200));
              // Logical proof/acquisition has timed out; actual native delivery
              // remains paused with its genuine work/late lease still owned.
              final closing = catalog.close();
              a.check(identical(closing, catalog.close()));
              var settled = false;
              String? closeFailure;
              unawaited(
                closing.then<void>(
                  (_) => settled = true,
                  onError: (Object error, StackTrace _) {
                    settled = true;
                    closeFailure = error is StateError
                        ? error.message
                        : 'INTERNAL';
                  },
                ),
              );
              await Future<void>.delayed(const Duration(milliseconds: 40));
              a.check(
                !settled && store.operational.automation.profiles.isEmpty,
              );
              if (!proof) {
                external = await seed.peer!.publicationGate(a.generation);
                await deniedGate(external);
              }
              if (failure) {
                final file = File(p.join(root, 'foundation.manifest.json'));
                originalManifest = file.readAsBytesSync();
                file.writeAsBytesSync([...originalManifest, 10]);
              }
              await nativeObservation.release();
              if (failure) {
                await a.fails(closing, 'SERVICE_UNAVAILABLE');
                a.check(settled && closeFailure == 'SERVICE_UNAVAILABLE');
                File(p.join(root, 'foundation.manifest.json'))
                    .writeAsBytesSync(originalManifest!);
                originalManifest = null;
              } else {
                await closing;
                a.check(settled && closeFailure == null);
                if (!proof) {
                  held = await external!.acquire();
                  await held.close();
                  held = null;
                }
                final reply = await mcp.call('mcp.invoke', {
                  'poll': {'operationId': initial['operationId']},
                });
                final tool = (reply['result'] as Map)['result'] as Map;
                a.check(
                  tool['isError'] == true &&
                      (((tool['structuredContent'] as Map)['error']
                              as Map)['code']) ==
                          'TIMEOUT',
                );
              }
              a.check(store.operational.automation.profiles.isEmpty);
            }
          } else if (mode.startsWith('snapshot-')) {
            final mcp = await client(g.grantId);
            final reached = Completer<void>();
            final release = publicationRelease = Completer<void>();
            OwnerServiceProbe.install((boundary, method) async {
              if (boundary !=
                      OwnerServiceBoundary.afterProfileCatalogSnapshot ||
                  method != 'automation.profiles.list' ||
                  reached.isCompleted)
                return;
              reached.complete();
              await release.future;
            });
            final started = await mcp.call('mcp.invoke', {
              'request': {
                'name': 'serverdeck_profiles_list',
                'arguments': <String, Object?>{},
              },
            });
            final operation = started['result'] as Map;
            a.check(operation['done'] == false);
            await reached.future.timeout(const Duration(seconds: 3));
            if (mode == 'snapshot-revoke') {
              a.check(
                !(await owner.call('grants.revoke', {
                  'requestId': id(18000),
                  'grantId': g.grantId,
                  'expectedRevision': 4,
                })).containsKey('error'),
              );
              a.check(
                router.retainedOperations == 0 && router.chargedOperations == 1,
              );
            } else {
              await owner.owner('create', create(18001));
            }
            release.complete();
            if (mode == 'snapshot-revoke') {
              await until(() => router!.chargedOperations == 0);
              final denied = await mcp.call('mcp.invoke', {
                'poll': {'operationId': operation['operationId']},
              });
              a.check(
                denied.containsKey('error') && !denied.containsKey('result'),
              );
            } else {
              Map value;
              final watch = Stopwatch()..start();
              do {
                final reply = await mcp.call('mcp.invoke', {
                  'poll': {'operationId': operation['operationId']},
                });
                a.check(
                  !reply.containsKey('error') &&
                      watch.elapsed < const Duration(seconds: 5),
                );
                value = reply['result'] as Map;
                if (value['done'] == false)
                  await Future<void>.delayed(const Duration(milliseconds: 10));
              } while (value['done'] == false);
              final tool = value['result'] as Map;
              a.check(
                tool['isError'] == true &&
                    (((tool['structuredContent'] as Map)['error']
                            as Map)['code']) ==
                        'REVISION_CONFLICT',
              );
            }
          } else if (mode == 'entry-race' || mode.startsWith('retention-')) {
            final mcp = await client(g.grantId);
            services.deferStart = mode == 'entry-race';
            services.deferResult = mode.startsWith('retention-');
            final initial = await mcp.call('mcp.invoke', {
              'request': {
                'name': 'serverdeck_profiles_list',
                'arguments': <String, Object?>{},
              },
            });
            final operation = initial['result'] as Map;
            a.check(operation['done'] == false);
            await services.entered.future.timeout(const Duration(seconds: 3));
            if (mode != 'entry-race') {
              await services.completed.future.timeout(
                const Duration(seconds: 3),
              );
            }
            protection!.pauseNext = 1;
            final writing = owner.owner('create', create(17000));
            writing.ignore();
            await protection!.reached(1);
            a.check(store.hasPendingMcpAuthorityPublication);
            if (mode == 'entry-race') {
              services.releaseStart.complete();
              await Future<void>.delayed(const Duration(milliseconds: 40));
            } else {
              routerTime = const Duration(milliseconds: 29990);
              services.releaseResult.complete();
              await Future<void>.delayed(Duration.zero);
              if (mode == 'retention-scheduler-first') {
                routerTime = const Duration(seconds: 30);
                router.sweep();
              }
              await Future<void>.delayed(const Duration(milliseconds: 40));
              routerTime = const Duration(seconds: 30);
            }
            protection!.release();
            await writing;
            Map result;
            final watch = Stopwatch()..start();
            do {
              final reply = await mcp.call('mcp.invoke', {
                'poll': {'operationId': operation['operationId']},
              });
              a.check(!reply.containsKey('error'));
              result = reply['result'] as Map;
              a.check(watch.elapsed < const Duration(seconds: 5));
              if (result['done'] == false)
                await Future<void>.delayed(const Duration(milliseconds: 10));
            } while (result['done'] == false);
            final tool = result['result'] as Map;
            final content = tool['structuredContent'] as Map;
            if (mode == 'entry-race') {
              a.check(
                tool['isError'] == false &&
                    ((content['data'] as Map)['items'] as List).length == 1,
              );
            } else {
              a.check(
                tool['isError'] == true &&
                    (content['error'] as Map)['code'] == 'TIMEOUT',
              );
              routerTime = const Duration(seconds: 90);
              router.sweep();
              final denied = await mcp.call('mcp.invoke', {
                'poll': {'operationId': operation['operationId']},
              });
              a.check(denied['error'] == 'FORBIDDEN');
            }
          } else if (mode.startsWith('overlap-') || mode.startsWith('grant-')) {
            final mcp = await client(g.grantId);
            final request = create(16000);
            Completer<void>? grantReached, grantRelease;
            Future<Map<String, Object?>> mutation;
            if (mode.startsWith('grant-')) {
              final otherId = id(16001);
              if (mode == 'grant-unrelated') {
                a.check(
                  !(await owner.call('grants.create', {
                    'requestId': id(16002),
                    'grantId': otherId,
                    'label': 'Other synthetic author',
                    'scopes': ['author'],
                    'serverIds': <String>[],
                    'lifetimeSeconds': 300,
                  })).containsKey('error'),
                );
                alignAuthorityClock();
              }
              grantReached = Completer<void>();
              grantRelease = publicationRelease = Completer<void>();
              GrantWriteProbe.install((point) async {
                if (point != GrantWriteBoundary.afterCommit) return;
                grantReached!.complete();
                await grantRelease!.future;
                if (mode == 'grant-blocked')
                  throw StateError('SYNTHETIC_READBACK_FAILURE');
              });
              mutation = owner.call(
                mode == 'grant-revoke' ? 'grants.revoke' : 'grants.replace',
                {
                  'requestId': id(16003),
                  'grantId': mode == 'grant-unrelated' ? otherId : g.grantId,
                  'expectedRevision': mode == 'grant-unrelated' ? 1 : 4,
                  if (mode != 'grant-revoke') ...{
                    'label': 'Updated synthetic author',
                    'scopes': ['author'],
                    'serverIds': <String>[],
                    'lifetimeSeconds': 300,
                  },
                },
              );
              mutation.ignore();
              await grantReached.future.timeout(const Duration(seconds: 3));
            } else {
              protection!.pauseNext = 1;
              mutation = owner.call('automation.profiles.create', request);
              mutation.ignore();
              await protection!.reached(1);
            }
            a.check(
              store.hasPendingMcpAuthorityPublication &&
                  !store.isAutomationReady,
            );
            try {
              store.currentMcpGrant(g.grantId, at: authorityTime);
              throw StateError('EXPECTED_SYNCHRONOUS_AUTHORITY_GATE');
            } on StateError catch (error) {
              a.check(error.message == 'STORAGE_BLOCKED');
            }
            var readSettled = false;
            final pendingRead = mcp.call('mcp.invoke', {
              'request': {
                'name': 'serverdeck_profiles_list',
                'arguments': <String, Object?>{},
              },
            });
            unawaited(pendingRead.then((_) => readSettled = true));
            await Future<void>.delayed(const Duration(milliseconds: 60));
            a.check(!readSettled && sessions.count == 2);
            final shortWait = Stopwatch()..start();
            try {
              await store.waitForMcpAuthority(
                deadline: const Duration(milliseconds: 40),
              );
              throw StateError('EXPECTED_PUBLICATION_TIMEOUT');
            } on StateError catch (error) {
              a.check(
                error.message == 'TIMEOUT' &&
                    shortWait.elapsed < const Duration(seconds: 1),
              );
            }
            a.check(
              store.hasPendingMcpAuthorityPublication && sessions.count == 2,
            );
            if (mode == 'overlap-expiry') advance(const Duration(minutes: 5));
            Future<void>? storageClose;
            if (mode == 'overlap-close') storageClose = store.close();
            if (mode == 'overlap-authority-close') authority.close();
            if (mode == 'overlap-close' || mode == 'overlap-authority-close') {
              final detach = Stopwatch()..start();
              await until(() => sessions.count == 1);
              if (detach.elapsed >= const Duration(seconds: 1)) {
                throw StateError('CATALOG_CLOSE_PREPARATION_NOT_RETIRED');
              }
            }
            if (mode == 'overlap-timeout') {
              await Future<void>.delayed(const Duration(seconds: 5));
              final timeoutReply = await pendingRead;
              a.check(timeoutReply['error'] == 'TIMEOUT');
              external = await seed.peer!.publicationGate(a.generation);
              await deniedGate(external);
            }
            protection!.release();
            grantRelease?.complete();
            final written = await mutation;
            final read = await pendingRead;
            if (mode == 'overlap-close') {
              await storageClose;
              a.check(!store.isAutomationReady);
            } else if (mode == 'overlap-authority-close') {
              a.check(read.containsKey('error') && store.isAutomationReady);
            } else if (mode == 'grant-blocked') {
              a.check(
                written['error'] == 'STORAGE_BLOCKED' &&
                    read.containsKey('error'),
              );
              a.check(
                !store.isAutomationReady &&
                    !store.hasPendingMcpAuthorityPublication,
              );
              try {
                await store.waitForMcpAuthority(
                  deadline: const Duration(seconds: 1),
                );
                throw StateError('EXPECTED_PERMANENT_BLOCK');
              } on StateError catch (error) {
                a.check(error.message == 'STORAGE_BLOCKED');
              }
              a.check(
                await Isar.getInstance('workspace')!.storedAutomationReceipts
                        .getByEntityId(id(16003)) !=
                    null,
              );
            } else if (mode == 'overlap-expiry' ||
                mode == 'overlap-timeout' ||
                mode == 'grant-revoke' ||
                mode == 'grant-replace') {
              a.check(read.containsKey('error') && !read.containsKey('result'));
              await catalog.close();
              a.check(store.isAutomationReady);
              if (mode.startsWith('overlap-'))
                a.check(store.operational.automation.profiles.length == 1);
            } else {
              a.check(
                written.containsKey('result') && read.containsKey('result'),
              );
              a.check(sessions.count == 2);
              final listed = await mcp.tool('list', {});
              a.check(
                (listed['items'] as List).length ==
                    (mode == 'grant-unrelated' ? 0 : 1),
              );
              final fresh = await client(g.grantId);
              a.check((await fresh.tool('list', {}))['items'] is List);
            }
          } else if (mode == 'permissions') {
            final target = id(10000);
            a.check(
              !(await owner.call('profiles.create', {
                'profileId': target,
                'name': 'Synthetic permission target',
                'address': 'catalog-fixture.invalid',
                'port': 22,
                'sshUser': 'fixture',
                'tags': <String>[],
              })).containsKey('error'),
            );
            for (final entry in {
              id(10001): ['read'],
              id(10002): <String>[],
            }.entries) {
              a.check(
                !(await owner.call('grants.create', {
                  'requestId': id(entry.key == id(10001) ? 10101 : 10102),
                  'grantId': entry.key,
                  'label': 'Synthetic restricted grant',
                  'scopes': entry.value,
                  'serverIds': entry.value.isEmpty ? <String>[] : [target],
                  'lifetimeSeconds': 300,
                })).containsKey('error'),
              );
              // The scenario authority clock is deliberately frozen. A grant
              // issued by the real owner adapter must not be opened before its
              // issuedAt instant on that synthetic clock.
              alignAuthorityClock();
              final restricted = await client(entry.key);
              final denied = await restricted.call('mcp.invoke', {
                'request': {
                  'name': 'serverdeck_profiles_get',
                  'arguments': {'profileId': id(9999)},
                },
              });
              a.check(denied['error'] == 'FORBIDDEN');
            }
          } else if (mode == 'admitted-disconnect') {
            final mcp = await client(g.grantId);
            protection!.pauseNext = 1;
            final request = create(15000);
            final pending = mcp.call('mcp.invoke', {
              'request': {
                'name': 'serverdeck_profiles_create',
                'arguments': request,
              },
            });
            pending.ignore();
            await protection!.reached(1);
            a.check(
              await Isar.getInstance('workspace')!.storedAutomationReceipts
                      .getByEntityId(id(15000)) !=
                  null,
            );
            await mcp.abandon();
            external = await seed.peer!.publicationGate(a.generation);
            await deniedGate(external);
            protection!.release();
            await until(() => store.isAutomationReady);
            final fresh = await client(g.grantId);
            final replay = await fresh.tool('create', request);
            a.check(
              replay['revision'] == 1 &&
                  store.operational.automation.profiles.length == 1,
            );
          } else if (mode == 'close') {
            protection!.pauseNext = 1;
            final request = create(11000);
            final pending = owner.owner('create', request);
            pending.ignore();
            await protection!.reached(1);
            a.check(
              await Isar.getInstance('workspace')!.storedAutomationReceipts
                      .getByEntityId(request['requestId'] as String) !=
                  null,
            );
            external = await seed.peer!.publicationGate(a.generation);
            await deniedGate(external);
            var closed = false;
            final closing = catalog.close();
            a.check(identical(closing, catalog.close()));
            unawaited(closing.then((_) => closed = true));
            await Future<void>.delayed(const Duration(milliseconds: 40));
            a.check(!closed);
            protection!.release();
            final ack = await pending;
            await closing;
            a.check(
              closed &&
                  store.operational.automation.profiles.containsKey(
                    ack['profileId'],
                  ),
            );
            held = await external.acquire();
            await held.close();
            held = null;
          } else {
            final mcp = await client(g.grantId);
            if (mode == 'key-boundary') {
              final unrelated = await custody.createReceiptKey(
                g.workspaceId,
                g.keyId,
              );
              try {
                await a.fails(
                  Future.sync(
                    () => AutomationProfileService(
                      store: store,
                      custody: custody,
                      receiptKey: unrelated,
                      sessions: sessions,
                      authority: authority,
                    ),
                  ),
                  'STORAGE_BLOCKED',
                );
                a.check(store.isAutomationReady);
              } finally {
                unrelated.close();
              }
            }
            if (mode == 'foreign-binding') {
              await mcp.tool('list', {});
              final actualContext = services.observedContext!;
              final otherRegistry =
                  await OperationalSessions.withNativePublicationGate(
                    generation: a.generation,
                    peer: seed.peer!,
                  );
              final otherService = AutomationProfileService(
                store: store,
                custody: custody,
                receiptKey: material,
                sessions: otherRegistry,
                authority: authority,
              );
              try {
                final other = ProfileCatalogMcpServices(otherService);
                final attempt = other.start(
                  actualContext,
                  mcpTool('serverdeck_profiles_create')!,
                  {'requestId': 'invalid-input-must-not-be-parsed'},
                );
                final result = (await attempt.result).toJson();
                a.check(
                  result['isError'] == true &&
                      ((result['structuredContent'] as Map)['error']
                              as Map)['code'] ==
                          'FORBIDDEN',
                );
                await a.fails(
                  Future.sync(
                    () => otherService.mcpActor(actualContext, 'list'),
                  ),
                  'FORBIDDEN',
                );
                a.check(
                  store.isAutomationReady &&
                      store.operational.automation.profiles.isEmpty,
                );
              } finally {
                await cleanupCatalogFixture([
                  otherService.close,
                  otherRegistry.close,
                ]);
              }
              // Closing the foreign service/registry must not own the real key,
              // authority or generation used by the original verified client.
              a.check(((await mcp.tool('list', {}))['items'] as List).isEmpty);
            }
            if (mode == 'unicode') {
              final invalidName = {...create(19500), 'name': 'e\u0301'};
              await mcp.tool('create', invalidName, failure: 'VALIDATION');
              a.check(
                (await owner.call(
                      'automation.profiles.create',
                      invalidName,
                    ))['error'] ==
                    'VALIDATION',
              );
              final invalidBody = {
                ...catalogBody(),
                'parameters': {
                  'text': {
                    'type': 'string',
                    'maxLength': 64,
                    'default': 'e\u0301',
                  },
                },
              };
              a.check(
                (await mcp.tool('validate', {'body': invalidBody}))['valid'] ==
                    false,
              );
              a.check(
                (await owner.owner('validate', {
                      'body': invalidBody,
                    }))['valid'] ==
                    false,
              );
              a.check(store.operational.automation.profiles.isEmpty);
            }
            if (mode == 'gate') {
              external = await seed.peer!.publicationGate(a.generation);
              held = await external.acquire();
              final request = create(12000);
              final reply = await mcp.call('mcp.invoke', {
                'request': {
                  'name': 'serverdeck_profiles_create',
                  'arguments': request,
                },
              });
              final operation = reply['result'] as Map;
              a.check(operation['done'] == false);
              await Future<void>.delayed(const Duration(milliseconds: 50));
              a.check(store.operational.automation.profiles.isEmpty);
              final cancelled = await mcp.call('mcp.invoke', {
                'cancel': {'operationId': operation['operationId']},
              });
              a.check((cancelled['result'] as Map)['cancelled'] == true);
              await held.close();
              held = null;
              await catalog.close();
              a.check(
                store.isAutomationReady &&
                    !store.operational.automation.receipts.containsKey(
                      request['requestId'],
                    ) &&
                    store.operational.automation.profiles.isEmpty,
              );
            } else {
              final first = await mcp.tool('create', create(13000));
              final profile = first['profileId'] as String;
              final fromOwner = await owner.owner('get', {
                'profileId': profile,
              });
              a.check(
                (fromOwner['revision'] as Map)['authorGrantId'] == g.grantId,
              );
              final updated = await owner.owner('update', {
                'requestId': id(13001),
                'profileId': profile,
                'expectedRevision': 1,
                'description': 'Owner metadata',
                'body': catalogBody(),
              });
              a.check(
                updated['revision'] == 2 &&
                    updated['digest'] == first['digest'],
              );
              final historical = await mcp.tool('get', {
                'profileId': profile,
                'revision': 1,
              });
              a.check(
                (historical['revision'] as Map)['authorGrantId'] == g.grantId,
              );
              final compared = await mcp.tool('compare', {
                'profileId': profile,
                'fromRevision': 1,
                'toRevision': 2,
              });
              a.check(
                (compared['changes'] as List).isEmpty &&
                    compared['truncated'] == false,
              );
              a.check(
                (await mcp.tool('validate', {
                      'body': catalogBody(),
                    }))['valid'] ==
                    true,
              );
              final invalid = {
                ...catalogBody(),
                'parameters': <String, Object?>{},
                'steps': [
                  {
                    'id': 'invalid_ref',
                    'kind': 'config_file',
                    'resourceId': 'system.motd',
                    'values': {
                      'text': {'param': 'missing'},
                    },
                  },
                ],
              };
              a.check(
                (await mcp.tool('validate', {'body': invalid}))['valid'] ==
                    false,
              );
              await mcp.tool('archive', {
                'requestId': id(13002),
                'profileId': profile,
                'expectedRevision': 2,
              });
              a.check(((await mcp.tool('list', {}))['items'] as List).isEmpty);
              a.check(
                ((await mcp.tool('list', {'includeArchived': true}))['items']
                            as List)
                        .length ==
                    1,
              );
              a.check(
                (await mcp.tool('create', create(13000)))['revision'] == 1,
              );
              await mcp.tool('update', {
                'requestId': id(13003),
                'profileId': profile,
                'expectedRevision': 1,
                'body': catalogBody(),
              }, failure: 'REVISION_CONFLICT');
              if (mode == 'authors' || mode == 'cursor') {
                final grant = id(14000);
                a.check(
                  !(await owner.call('grants.create', {
                    'requestId': id(14001),
                    'grantId': grant,
                    'label': 'Second author',
                    'scopes': ['author'],
                    'serverIds': <String>[],
                    'lifetimeSeconds': 300,
                  })).containsKey('error'),
                );
                alignAuthorityClock();
                final other = await client(grant);
                final second = await other.tool('create', create(14002));
                final third = await mcp.tool('create', create(14003));
                a.check(
                  (await other.tool('get', {
                        'profileId': third['profileId'],
                      }))['revision']
                      is Map,
                );
                await other.tool('create', create(14003), failure: 'FORBIDDEN');
                final page = await mcp.tool('list', {'limit': 1});
                final cursor = page['nextCursor'] as String;
                a.check(cursor.length <= 512);
                await other.tool('list', {
                  'limit': 1,
                  'cursor': cursor,
                }, failure: 'CURSOR_EXPIRED');
                a.check(
                  ((await mcp.tool('list', {
                                'limit': 1,
                                'cursor': cursor,
                              }))['items']
                              as List)
                          .length ==
                      1,
                );
                final tampered =
                    cursor.substring(0, cursor.length - 1) +
                    (cursor.endsWith('A') ? 'B' : 'A');
                await mcp.tool('list', {
                  'limit': 1,
                  'cursor': tampered,
                }, failure: 'CURSOR_EXPIRED');
                await mcp.tool('list', {
                  'limit': 1,
                  'includeArchived': true,
                  'cursor': cursor,
                }, failure: 'CURSOR_EXPIRED');
                if (mode == 'cursor') {
                  wall = wall.add(const Duration(milliseconds: 299999));
                  await mcp.tool('list', {'limit': 1, 'cursor': cursor});
                  wall = wall.add(const Duration(milliseconds: 1));
                  await mcp.tool('list', {
                    'limit': 1,
                    'cursor': cursor,
                  }, failure: 'CURSOR_EXPIRED');
                } else {
                  await other.tool('update', {
                    'requestId': id(14004),
                    'profileId': second['profileId'],
                    'expectedRevision': 1,
                    'body': catalogBody(),
                    'name': 'Changed metadata',
                  });
                  await mcp.tool('list', {
                    'limit': 1,
                    'cursor': cursor,
                  }, failure: 'CURSOR_EXPIRED');
                }
              }
            }
          }
          api.close();
        } finally {
          if (originalManifest != null) {
            File(p.join(root, 'foundation.manifest.json'))
                .writeAsBytesSync(originalManifest);
          }
          await nativeObservation?.release();
          deferred?.release();
          if (publicationRelease != null && !publicationRelease!.isCompleted) {
            publicationRelease!.complete();
          }
          protection?.release();
          await cleanupCatalogFixture([
            () async => held?.close(),
            for (final client in clients.reversed) client.close,
            () async {
              if (mode.startsWith('physical-') && mode.endsWith('-failure')) {
                await a.fails(service!.close(), 'SERVICE_UNAVAILABLE');
              } else {
                await service?.close();
              }
            },
            () async => foundation?.close(),
            () async => router?.close(),
            () async {
              if (mode == 'physical-gate-failure' ||
                  mode == 'physical-release-failure') {
                if (external != null)
                  await a.fails(external.close(), 'SERVICE_UNAVAILABLE');
              } else {
                await external?.close();
              }
            },
            () async {
              if (mode == 'physical-gate-failure' ||
                  mode == 'physical-release-failure') {
                await a.fails(registry!.close(), 'SERVICE_UNAVAILABLE');
              } else {
                await registry?.close();
              }
            },
            seed.close,
            () async => key?.close(),
          ]);
        }
      },
    );
    stdout.writeln('PASS:$mode');
  } catch (error, stack) {
    protection?.release();
    stderr.writeln('CATALOG_FIXTURE_FAILED');
    if (error is StateError) stderr.writeln(error.message);
    stderr.writeln(stack.toString().split('\n').take(8).join('\n'));
    exitCode = 1;
  }
}
