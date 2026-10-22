import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/api/owner_api.dart';
import 'package:serverdeck_locald/api/owner_trust_probes.dart';
import 'package:serverdeck_locald/api/owner_trust_mutations.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/remote/trust_probes.dart';
import 'package:serverdeck_locald/remote/ssh_transport.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/models.dart';

import 'trusted_auth_actor.dart' as a;
import 'trust_write_scenarios.dart';

Future<void> exerciseTrustProbes(
  String root,
  String mode,
  StateStore store,
  KeyCustody custody,
  ReceiptKeyMaterial key,
  a.Pair owner,
  TrustedSessions plain, {
  required void Function(Duration) advanceNative,
}) async {
  const profile = '62345678-1234-4234-8234-000000080000';
  var next = 80000;
  String id() =>
      '62345678-1234-4234-8234-${(++next).toString().padLeft(12, '0')}';
  final pool = SshTransportPool();
  final coordinator = TrustedMutationCoordinator(store, custody, key);
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <Socket>[];
  final subscription = server.listen((socket) {
    sockets.add(socket);
    socket.listen((_) {}, onError: (Object _) {});
  });
  HostTrustProbeService? service;
  TrustMutationOwnerApi? writeApi;
  Process? ssh;
  StreamIterator<String>? sshLines;
  Future<String>? sshErrors;
  Map<String, Object?>? sshKey;
  a.Pair? other;
  var elapsed = Duration.zero;
  var shiftOnSweep = false;
  final wallReached = Completer<void>();
  try {
    var port = server.port;
    if (mode.startsWith('probe-success')) {
      final python = Platform.environment['SERVERDECK_TRUST_FIXTURE_PYTHON'];
      final script = Platform.environment['SERVERDECK_TRUST_FIXTURE_SCRIPT'];
      if (python == null || script == null)
        throw StateError('TRUST_FIXTURE_PREREQUISITE');
      ssh = await Process.start(python, [
        '-I',
        script,
        if (mode == 'probe-success-stale') '--paused',
      ]);
      sshErrors = ssh.stderr.transform(utf8.decoder).join();
      sshLines = StreamIterator(
        ssh.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      a.check(await sshLines.moveNext().timeout(const Duration(seconds: 8)));
      final metadata = jsonDecode(sshLines.current) as Map;
      port = metadata['port'] as int;
      sshKey = Map<String, Object?>.from(metadata['key'] as Map);
    }
    if (mode == 'probe-basic' || mode == 'probe-retention')
      await server.close();
    await coordinator.submit(id(), ApiMethod.profilesCreate, {
      'profileId': profile,
      'name': 'Synthetic probe target',
      'address': '127.0.0.1',
      'port': port,
      'sshUser': 'fixture',
      'tags': <String>[],
      'credential': {'action': 'remove'},
    }, requester: 'fixture');
    if (mode == 'probe-gate') {
      await a.fails(
        Future.sync(
          () => HostTrustProbeService(
            store: store,
            sessions: plain,
            transports: pool,
          ),
        ),
        'NOT_READY',
      );
      return;
    }
    final probes = service = HostTrustProbeService(
      store: store,
      sessions: owner.registry,
      transports: pool,
      elapsed: () {
        if (shiftOnSweep) advanceNative(const Duration(seconds: 6));
        return elapsed;
      },
      clock: () {
        if (mode == 'probe-success-deadline') {
          advanceNative(const Duration(seconds: 30));
          if (!wallReached.isCompleted) wallReached.complete();
        }
        return DateTime.now();
      },
    );
    final TrustedOwnerApi api = mode.startsWith('probe-success-write-')
        ? TrustedOwnerApiGroup([
            TrustProbeOwnerApi(probes),
            writeApi = TrustMutationOwnerApi(
              service: probes,
              coordinator: coordinator,
            ),
          ])
        : TrustProbeOwnerApi(probes);
    Future<Map<String, Object?>> call(
      String method,
      Map<String, Object?> params, {
      String? requestId,
    }) async {
      final request = await owner.registry.begin(
        owner.channel,
        owner.response!.sessionId,
        method,
      );
      try {
        return await api.dispatch(
          request,
          method,
          params,
          requestId: requestId ?? id(),
        );
      } finally {
        request.complete();
      }
    }

    Map<String, Object?> body() => {
      'profileId': profile,
      'expectedRevision': '1',
    };
    final snapshot = await call('servers.trust.get', {'profileId': profile});
    a.check(snapshot['trust'] == null && snapshot['trustRevision'] == '1');
    if (mode == 'probe-admission-clock') {
      final request = await owner.registry.begin(
        owner.channel,
        owner.response!.sessionId,
        'servers.trust.probe',
      );
      final invocation = api.prepare(
        request,
        request.method,
        body(),
        requestId: id(),
      );
      try {
        shiftOnSweep = true;
        await a.fails(() async {
          final value = await invocation.execute();
          if (value['state'] == 'running')
            stdout.writeln('ADMISSION_CLOCK_RETURNED_RUNNING');
        }(), 'TIMEOUT');
        a.check(pool.activeTransports == 0 && sockets.isEmpty);
      } finally {
        shiftOnSweep = false;
        invocation.close();
        request.complete();
      }
      a.check(probes.retainedProbes == 0);
      return;
    }
    if (mode == 'probe-reservation' ||
        mode == 'probe-quota' ||
        mode == 'probe-reserved-cancel') {
      final request = owner.registry.reserve(
        owner.channel,
        owner.response!.sessionId,
        'servers.trust.probe',
      );
      final invocations = <TrustedOwnerInvocation>[];
      String? reserved;
      try {
        final count = mode == 'probe-quota' ? 16 : 1;
        for (var i = 0; i < count; i++) {
          reserved = id();
          invocations.add(
            api.prepare(
              request,
              'servers.trust.probe',
              body(),
              requestId: reserved,
            ),
          );
        }
        a.check(probes.retainedProbes == count && pool.activeTransports == 0);
        if (mode == 'probe-quota') {
          await a.fails(
            Future.sync(
              () => api.prepare(
                request,
                'servers.trust.probe',
                body(),
                requestId: id(),
              ),
            ),
            'RESOURCE_LIMIT',
          );
        }
        await a.fails(invocations.first.execute(), 'FORBIDDEN');
        if (mode == 'probe-reserved-cancel') {
          a.check(
            (await call('servers.trust.probeCancel', {
                  'operationId': reserved,
                }))['cancelled'] ==
                true,
          );
          await owner.registry.completeAdmission(request);
          await invocations.first.execute();
          a.check(pool.activeTransports == 0);
          a.check(
            (await call('servers.trust.probeStatus', {
                  'operationId': reserved,
                }))['code'] ==
                'CANCELLED',
          );
        }
      } finally {
        for (final invocation in invocations) {
          invocation.close();
        }
        request.complete();
      }
      if (mode == 'probe-reserved-cancel') {
        a.check(probes.retainedProbes == 1);
        elapsed = const Duration(seconds: 60);
      }
      a.check(probes.retainedProbes == 0);
      return;
    }
    if (mode == 'probe-role' || mode == 'probe-foreign') {
      final mcp = mode == 'probe-role';
      final registry = mcp ? owner.registry : plain;
      final pair = other = await a.Pair.start(
        root,
        mcp ? 'mcp.exe' : 'serverdeck.exe',
        registry,
      );
      await pair.exchange();
      a.check(await pair.next() == (mcp ? 'AUTH:mcp' : 'AUTH:owner'));
      final method = mcp ? 'session.ping' : 'servers.trust.get';
      final request = await registry.begin(
        pair.channel,
        pair.response!.sessionId,
        method,
      );
      try {
        if (mcp) {
          await a.fails(
            registry.begin(
              pair.channel,
              pair.response!.sessionId,
              'servers.trust.get',
            ),
            'FORBIDDEN',
          );
          await a.fails(
            registry.begin(
              pair.channel,
              pair.response!.sessionId,
              'servers.trust.probe',
            ),
            'FORBIDDEN',
          );
        }
        await a.fails(
          Future.sync(
            () => api.prepare(request, method, {
              'bad': true,
            }, requestId: 'invalid'),
          ),
          'FORBIDDEN',
        );
      } finally {
        request.complete();
      }
      return;
    }
    if (mode.startsWith('probe-physical-')) {
      final request = await owner.registry.begin(
        owner.channel,
        owner.response!.sessionId,
        'servers.trust.probe',
      );
      final observation = await owner.peer!.observeNextRevalidationForTest();
      final operation = id();
      final invocation = api.prepare(
        request,
        request.method,
        body(),
        requestId: operation,
      );
      try {
        await invocation.execute();
        invocation.close();
        request.complete();
        await observation.reached.timeout(const Duration(seconds: 3));
        if (mode == 'probe-physical-stale') {
          final current = store.state.profiles[profile]!.toJson();
          await coordinator.submit(id(), ApiMethod.profilesUpdate, {
            'profileId': profile,
            'expectedRevision': current['revision'],
            for (final field in ['name', 'address', 'port', 'sshUser', 'tags'])
              field: current[field],
            'name': 'Changed during native proof',
            'credential': {'action': 'keep'},
          }, requester: 'fixture-change');
          await observation.release();
          final wait = Stopwatch()..start();
          Map<String, Object?> state;
          do {
            a.check(wait.elapsed < const Duration(seconds: 3));
            state = await call('servers.trust.probeStatus', {
              'operationId': operation,
            });
            if (state['state'] == 'running')
              await Future<void>.delayed(const Duration(milliseconds: 5));
          } while (state['state'] == 'running');
          a.check(state['code'] == 'REVISION_CONFLICT' && sockets.isEmpty);
        } else {
          if (mode == 'probe-physical-detach') {
            owner.handshake!.close();
          } else {
            a.check(
              (await call('servers.trust.probeCancel', {
                    'operationId': operation,
                  }))['cancelled'] ==
                  true,
            );
          }
          a.check(probes.retainedProbes == 1 && sockets.isEmpty);
          var drained = false;
          final closing = probes.close().then<void>((_) {
            drained = true;
          });
          await Future<void>.delayed(const Duration(milliseconds: 20));
          a.check(!drained && probes.retainedProbes == 1);
          await observation.release();
          await closing;
          a.check(
            drained &&
                probes.retainedProbes == 0 &&
                pool.activeTransports == 0 &&
                sockets.isEmpty,
          );
        }
      } finally {
        invocation.close();
        request.complete();
        await observation.release();
      }
      return;
    }
    final operation = id();
    a.check(
      (await call(
            'servers.trust.probe',
            body(),
            requestId: operation,
          ))['operationId'] ==
          operation,
    );
    if (mode == 'probe-success-deadline') {
      // Advance only the background service clock; do not straddle that jump
      // with an unrelated five-second status/duplicate RPC.
      await wallReached.future.timeout(const Duration(seconds: 5));
    } else {
      a.check(
        (await call(
              'servers.trust.probe',
              body(),
              requestId: operation,
            ))['operationId'] ==
            operation,
      );
      await a.fails(
        call('servers.trust.probe', {
          ...body(),
          'expectedRevision': '2',
        }, requestId: operation),
        'IDEMPOTENCY_CONFLICT',
      );
    }
    if (mode == 'probe-close') {
      final closing = probes.close();
      a.check(identical(closing, probes.close()));
      await closing;
      a.check(probes.retainedProbes == 0 && pool.activeTransports == 0);
      await a.fails(
        call('servers.trust.get', {'profileId': profile}),
        'SERVICE_UNAVAILABLE',
      );
      return;
    }
    if (mode == 'probe-cancel') {
      a.check(
        (await call('servers.trust.probeCancel', {
              'operationId': operation,
            }))['cancelled'] ==
            true,
      );
      a.check(
        (await call('servers.trust.probeCancel', {
              'operationId': operation,
            }))['cancelled'] ==
            false,
      );
    }
    if (mode == 'probe-success-stale') {
      final wait = Stopwatch()..start();
      while (true) {
        ssh!.stdin.writeln('stats');
        a.check(await sshLines!.moveNext().timeout(const Duration(seconds: 3)));
        final stats = jsonDecode(sshLines.current) as Map;
        if (stats['accepted'] == 1) break;
        a.check(wait.elapsed < const Duration(seconds: 3));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final observation = await owner.peer!.observeNextRevalidationForTest();
      try {
        ssh.stdin.writeln('release');
        await observation.reached.timeout(const Duration(seconds: 3));
        a.check(pool.activeTransports == 0);
        final current = store.state.profiles[profile]!.toJson();
        await coordinator.submit(id(), ApiMethod.profilesUpdate, {
          'profileId': profile,
          'expectedRevision': current['revision'],
          for (final field in ['name', 'address', 'port', 'sshUser', 'tags'])
            field: current[field],
          'address': '127.0.0.2',
          'credential': {'action': 'keep'},
        }, requester: 'fixture-change-after-key');
      } finally {
        await observation.release();
      }
    }
    final watch = Stopwatch()..start();
    Map<String, Object?> result;
    do {
      a.check(watch.elapsed < const Duration(seconds: 5));
      result = await call('servers.trust.probeStatus', {
        'operationId': operation,
      });
      if (result['state'] == 'running')
        await Future<void>.delayed(const Duration(milliseconds: 5));
    } while (result['state'] == 'running');
    if (mode == 'probe-success-stale' || mode == 'probe-success-deadline') {
      if (mode == 'probe-success-deadline' && result['state'] == 'succeeded')
        stdout.writeln('DEADLINE_CLOCK_RETURNED_CHALLENGE');
      a.check(
        result['state'] == 'failed' &&
            result['code'] ==
                (mode == 'probe-success-stale'
                    ? 'REVISION_CONFLICT'
                    : 'TIMEOUT'),
      );
      a.check(!jsonEncode(result).contains(sshKey!['fingerprint'] as String));
    } else if (mode.startsWith('probe-success')) {
      a.check(result['state'] == 'succeeded');
      final challenge = result['challenge'] as Map;
      a.check(jsonEncode(challenge['key']) == jsonEncode(sshKey));
      a.check(
        challenge['profileId'] == profile &&
            challenge['expectedRevision'] == '1' &&
            pool.activeTransports == 0,
      );
      final closing = Stopwatch()..start();
      while (true) {
        ssh!.stdin.writeln('stats');
        a.check(await sshLines!.moveNext().timeout(const Duration(seconds: 3)));
        final stats = jsonDecode(sshLines.current) as Map;
        a.check(stats['authentication'] == 0 && stats['accepted'] == 1);
        if (stats['active'] == 0) break;
        a.check(closing.elapsed < const Duration(seconds: 3));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      if (mode.startsWith('probe-success-write-')) {
        await exerciseTrustWrites(
          root: root,
          mode: mode,
          profile: profile,
          operation: operation,
          challenge: challenge,
          api: api,
          coordinator: coordinator,
          service: probes,
          store: store,
          owner: owner,
          id: id,
          advance: (value) => elapsed = value,
          armClock: (value) => shiftOnSweep = value,
        );
        return;
      }
      if (mode == 'probe-success-cancel') {
        a.check(
          (await call('servers.trust.probeCancel', {
                'operationId': operation,
              }))['cancelled'] ==
              true,
        );
        a.check(
          (await call('servers.trust.probeCancel', {
                'operationId': operation,
              }))['cancelled'] ==
              false,
        );
        a.check(
          jsonEncode(
                await call('servers.trust.probeStatus', {
                  'operationId': operation,
                }),
              ) ==
              jsonEncode(result),
        );
        elapsed = const Duration(seconds: 60);
        await a.fails(
          call('servers.trust.probeStatus', {'operationId': operation}),
          'NOT_FOUND',
        );
        a.check(probes.retainedProbes == 0);
      } else if (mode == 'probe-success-ttl') {
        elapsed = const Duration(seconds: 60);
        await a.fails(
          call('servers.trust.probeStatus', {'operationId': operation}),
          'NOT_FOUND',
        );
        a.check(probes.retainedProbes == 1);
        await a.fails(
          call('servers.trust.probe', body(), requestId: operation),
          'NOT_FOUND',
        );
        await a.fails(
          call('servers.trust.probe', {
            ...body(),
            'expectedRevision': '2',
          }, requestId: operation),
          'IDEMPOTENCY_CONFLICT',
        );
        elapsed = const Duration(seconds: 300);
        a.check(probes.retainedProbes == 0);
        a.check(
          (await call(
                'servers.trust.probe',
                body(),
                requestId: operation,
              ))['operationId'] ==
              operation,
        );
      } else if (mode == 'probe-success-other') {
        final pair = other = await a.Pair.start(
          root,
          'serverdeck.exe',
          owner.registry,
        );
        await pair.exchange();
        a.check(await pair.next() == 'AUTH:owner');
        final request = await owner.registry.begin(
          pair.channel,
          pair.response!.sessionId,
          'servers.trust.probeStatus',
        );
        try {
          await a.fails(
            api.dispatch(request, request.method, {
              'operationId': operation,
            }, requestId: id()),
            'NOT_FOUND',
          );
        } finally {
          request.complete();
        }
      }
    } else {
      a.check(
        result['state'] == 'failed' &&
            result['code'] ==
                (mode == 'probe-cancel' ? 'CANCELLED' : 'CONNECTION_FAILED'),
      );
    }
    if (mode == 'probe-retention') {
      elapsed = const Duration(seconds: 60);
      await a.fails(
        call('servers.trust.probeStatus', {'operationId': operation}),
        'NOT_FOUND',
      );
      a.check(probes.retainedProbes == 0);
    }
    a.check(store.trustedOperational.foundation.trust.isEmpty);
  } finally {
    await writeApi?.close();
    try {
      await service?.close();
    } finally {
      try {
        await coordinator.close();
      } finally {
        try {
          await pool.close();
        } finally {
          for (final socket in sockets) {
            socket.destroy();
          }
          await subscription.cancel();
          await server.close();
          await other?.close();
          if (ssh != null) {
            ssh.stdin.writeln('close');
            await ssh.stdin.close();
            try {
              await ssh.exitCode.timeout(const Duration(seconds: 5));
            } on TimeoutException {
              ssh.kill();
              await ssh.exitCode;
            }
            await sshLines?.cancel();
            a.check((await sshErrors!).isEmpty);
          }
        }
      }
    }
  }
}
