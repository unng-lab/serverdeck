import 'dart:async';

import 'package:serverdeck_engine/hosting/engine_host.dart';
import 'package:serverdeck_engine/hosting/in_process_gateway.dart';
import 'package:serverdeck_engine/hosting/sessions.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

import 'authority_test.dart' as ram;
import 'engine_host_test.dart' as fixture;
import 'in_process_gateway_test.dart' as gateway;
import 'mcp_host_publication_test.dart' as publication;
import 'sessions_test.dart' as session;

Matcher failure(String code) =>
    throwsA(isA<EngineCallFailure>().having((e) => e.code, 'safe code', code));

void main() {
  void later(int ticks, void Function() action) {
    if (ticks == 0) {
      action();
      return;
    }
    scheduleMicrotask(() => later(ticks - 1, action));
  }

  test('actual Host and pool keep pre-publication pauses across activation microtasks', () async {
    var before = 0, after = 0;
    for (var ticks = 0; ticks <= 40; ticks++) {
      final p = publication.Setup(), s = p.hostFixture;
      final delivered = Completer<HostPause>();
      var armed = false, ioAccepted = false, acknowledged = false;
      s.runtime.onProof = () {
        if (armed || p.publication == null) return;
        armed = true;
        later(ticks, () {
          ioAccepted = p.discovery.events.contains('publish.begin');
          delivered.complete(s.host.suspend());
        });
      };
      final starting = s.start().then((result) {
        acknowledged = true;
        return result;
      });
      final pause = await delivered.future;
      await pause.settled;
      await ram.settle();
      if (!ioAccepted) {
        before++;
        expect(
          p.discovery.events,
          isNot(contains('publish.begin')),
          reason: 'ticks=$ticks',
        );
        expect(acknowledged, isFalse, reason: 'ticks=$ticks');
      } else {
        after++;
      }
      await s.host.resume(pause);
      expect(await starting, HostStartResult.ready, reason: 'ticks=$ticks');
      expect(p.publication!.isPublished, isTrue);
      expect(s.acquisitions, 1);
      await s.host.shutdown('exit');
      await p.finish();
    }
    expect(before, greaterThan(0));
    expect(after, greaterThan(0));
  });

  test(
    'startup acknowledgement honors pauses across final microtask boundaries',
    () async {
      var before = 0, after = 0;
      for (var ticks = 0; ticks <= 40; ticks++) {
        final s = fixture.Setup(), delivered = Completer<HostPause>();
        var armed = false, wasReady = false, acknowledged = false;
        s.runtime.onProof = () {
          if (armed || !s.resources.events.contains('services.open')) return;
          armed = true;
          later(ticks, () {
            wasReady = s.host.readiness.state == ReadinessState.ready;
            delivered.complete(s.host.suspend());
          });
        };
        final starting = s.start().then((result) {
          acknowledged = true;
          return result;
        });
        final pause = await delivered.future;
        await pause.settled;
        await ram.settle();
        if (!wasReady) {
          before++;
          expect(acknowledged, isFalse, reason: 'ticks=$ticks');
        } else {
          after++;
        }
        await s.host.resume(pause);
        expect(await starting, HostStartResult.ready);
        await s.host.shutdown('exit');
      }
      expect(before, greaterThan(0));
      expect(after, greaterThan(0));
    },
  );

  test(
    'final startup commit rechecks elapsed budget across microtask boundaries',
    () async {
      var before = 0, after = 0;
      for (var ticks = 0; ticks <= 40; ticks++) {
        final s = fixture.Setup(), delivered = Completer<void>();
        var armed = false, wasReady = false;
        s.runtime.onProof = () {
          if (armed || !s.resources.events.contains('services.open')) return;
          armed = true;
          later(ticks, () {
            wasReady = s.host.readiness.state == ReadinessState.ready;
            s.clock.elapsed = const Duration(seconds: 30);
            delivered.complete();
          });
        };
        final starting = s.start();
        await delivered.future;
        final result = await starting;
        if (!wasReady) {
          before++;
          expect(
            result,
            HostStartResult.startingFailure,
            reason: 'ticks=$ticks',
          );
        } else {
          after++;
          expect(result, HostStartResult.ready);
        }
        expect(await s.host.shutdown('exit'), HostCloseResult.closed);
      }
      expect(before, greaterThan(0));
      expect(after, greaterThan(0));
    },
  );

  test(
    'resume does not extend the original monotonic startup budget',
    () async {
      final s = fixture.Setup();
      s.resources.servicesOpening = Completer<void>();
      final starting = s.start();
      await ram.settle();
      final pause = s.host.suspend();
      s.resources.servicesOpening!.complete();
      await pause.settled;
      s.clock.elapsed = const Duration(seconds: 30);
      await expectLater(s.host.resume(pause), failure('TIMEOUT'));
      expect(await starting, HostStartResult.startingFailure);
      expect(s.resources.events, isNot(contains('services.resume')));
      expect(await s.host.shutdown('exit'), HostCloseResult.closed);
    },
  );

  test('suspend never starts an unstarted Host', () async {
    final s = fixture.Setup();
    expect(() => s.host.suspend(), failure('NOT_READY'));
    expect(s.acquisitions, 0);
    expect(s.resources.events, isEmpty);
    await s.start();
    await s.host.shutdown('exit');
  });

  test(
    'foreign and consumed pause handles cannot resume the current cycle',
    () async {
      final s = fixture.Setup(), other = fixture.Setup();
      await s.start();
      await other.start();
      final first = s.host.suspend(), foreign = other.host.suspend();
      await Future.wait([first.settled, foreign.settled]);
      await expectLater(s.host.resume(foreign), failure('NOT_READY'));
      await s.host.resume(first);
      final next = s.host.suspend();
      await next.settled;
      await expectLater(s.host.resume(first), failure('NOT_READY'));
      expect(s.host.isSuspended, isTrue);
      await s.host.resume(next);
      await other.host.resume(foreign);
      await s.host.shutdown('exit');
      await other.host.shutdown('exit');
    },
  );

  test(
    'reentrant suspend after provider restore fences the older resume',
    () async {
      final s = fixture.Setup();
      await s.start();
      final first = s.host.suspend();
      await first.settled;
      HostPause? next;
      s.resources.afterResume = () {
        s.resources.afterResume = null;
        next = s.host.suspend();
        final proofs = s.runtime.proofs;
        expect(
          () => McpServerHandshake(
            peer: session.Channel(
              s.runtime.ownerIdentity,
              s.runtime.appRoot,
              s.runtime.buildId,
            ),
            token: List.filled(32, 7),
            channel: 'reentrant-pause',
            sessions: s.resources.sessions!,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'safe code',
              'NOT_READY',
            ),
          ),
        );
        expect(s.runtime.proofs, proofs);
      };
      await expectLater(s.host.resume(first), failure('NOT_READY'));
      expect(s.host.readiness.state, isNot(ReadinessState.ready));
      await next!.settled;
      await s.host.resume(next!);
      expect(s.host.readiness.state, ReadinessState.ready);
      expect(s.host.failureCode, isNull);
      expect(s.acquisitions, 1);
      await s.host.shutdown('exit');
    },
  );

  test(
    'elapsed original resume budget is checked before service admission',
    () async {
      final s = fixture.Setup();
      await s.start();
      final pause = s.host.suspend();
      await pause.settled;
      final physical = s.vault.paused = Completer<void>();
      final resuming = s.host.resume(pause);
      final failed = expectLater(resuming, failure('TIMEOUT'));
      await ram.settle();
      s.clock.elapsed = const Duration(seconds: 30);
      s.vault.paused = null;
      physical.complete();
      await failed;
      expect(s.resources.events, isNot(contains('services.resume')));
      expect(await s.host.shutdown('exit'), HostCloseResult.closed);
    },
  );

  test(
    'shutdown retains late service revalidation until explicit wait',
    () async {
      final s = fixture.Setup();
      await s.start();
      final pause = s.host.suspend();
      await pause.settled;
      s.resources.servicesRevalidating = Completer<void>();
      final resuming = s.host.resume(pause);
      final failed = expectLater(resuming, failure('SERVICE_UNAVAILABLE'));
      await ram.settle();
      expect(s.resources.events, contains('services.revalidate'));
      expect(
        await s.host.shutdown(
          'exit',
          deadline: const Duration(milliseconds: 10),
        ),
        HostCloseResult.closeBlocked,
      );
      expect(s.lease.closes, 0);
      expect(s.resources.events, isNot(contains('workspace.close')));
      s.resources.servicesRevalidating!.complete();
      await failed;
      expect(await s.host.waitForClose(), HostCloseResult.closed);
    },
  );

  test(
    'shutdown before service readiness owns the failed pause checkpoint',
    () async {
      final s = fixture.Setup();
      s.resources.servicesOpening = Completer<void>();
      final starting = s.start();
      await ram.settle();
      final pause = s.host.suspend();
      final pauseFailed = expectLater(
        pause.settled,
        failure('SERVICE_UNAVAILABLE'),
      );
      expect(
        await s.host.shutdown(
          'exit',
          deadline: const Duration(milliseconds: 10),
        ),
        HostCloseResult.closeBlocked,
      );
      expect(await starting, HostStartResult.startingFailure);
      expect(s.lease.closes, 0);
      s.resources.servicesOpening!.complete();
      await pauseFailed;
      expect(await s.host.waitForClose(), HostCloseResult.closed);
    },
  );

  test(
    'pause preserves Host/store/lease and resumes only fresh owners',
    () async {
      final s = fixture.Setup();
      await s.start();
      final generation = s.host.generation;
      final old = await s.host.openOwner(Object());
      final pause = s.host.suspend();
      expect(identical(s.host.suspend(), pause), isTrue);
      expect(s.host.readiness.state, ReadinessState.recovering);
      expect(s.host.readiness.features.any, isFalse);
      await expectLater(s.host.openOwner(Object()), failure('NOT_READY'));
      await pause.settled;
      expect(old.isClosed, isTrue);
      expect(s.lease.closes, 0);
      expect(s.vault.closes, 0);
      expect(s.host.capabilities.coreUsable, isFalse);
      expect(s.resources.events, isNot(contains('workspace.close')));
      await s.host.resume(pause);
      expect(s.host.generation, generation);
      expect(s.host.readiness.state, ReadinessState.ready);
      expect(s.acquisitions, 1);
      expect(s.storeRuntime.validations, 1);
      expect(s.vault.probes, 2);
      final fresh = await s.host.openOwner(Object());
      await fresh.call('settings.get', {}, requestId: gateway.id);
      expect(s.resources.events.where((e) => e == 'workspace.open').length, 1);
      await expectLater(s.host.resume(pause), failure('NOT_READY'));
      expect(await s.host.shutdown('exit'), HostCloseResult.closed);
    },
  );

  test(
    'late revoked owner issuance remains physically owned before resume',
    () async {
      final s = fixture.Setup();
      await s.start();
      final physical = s.runtime.paused = Completer<void>();
      final binding = Object();
      final opening = s.host.openOwner(binding);
      final refused = expectLater(opening, failure('UNAUTHORIZED'));
      await ram.settle();
      final pause = s.host.suspend();
      await refused;
      await expectLater(
        pause.settled.timeout(Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      expect(s.lease.isHeld, isTrue);
      s.runtime.paused = null;
      physical.complete();
      await pause.settled;
      await s.host.resume(pause);
      final owner = await s.host.openOwner(binding);
      expect(owner.isClosed, isFalse);
      await s.host.shutdown('exit');
    },
  );

  test(
    'startup pause holds Ready and MCP publication until same startup resumes',
    () async {
      final p = publication.Setup(), s = p.hostFixture;
      s.resources.servicesOpening = Completer<void>();
      var started = false;
      final starting = s.start().then((value) {
        started = true;
        return value;
      });
      await ram.settle();
      final pause = s.host.suspend();
      s.resources.servicesOpening!.complete();
      await pause.settled;
      expect(started, isFalse);
      expect(p.publication, isNull);
      expect(s.host.readiness.state, isNot(ReadinessState.ready));
      await s.host.resume(pause);
      expect(await starting, HostStartResult.ready);
      expect(p.publication!.isPublished, isTrue);
      expect(s.acquisitions, 1);
      await s.host.shutdown('exit');
      await p.finish();
    },
  );

  test('original startup timeout wakes pause checkpoint for cleanup', () async {
    final s = fixture.Setup();
    s.resources.servicesOpening = Completer<void>();
    final starting = s.start(deadline: const Duration(milliseconds: 30));
    await ram.settle();
    final pause = s.host.suspend();
    s.resources.servicesOpening!.complete();
    await pause.settled;
    expect(await starting, HostStartResult.startingFailure);
    expect(s.host.failureCode, 'TIMEOUT');
    expect(await s.host.shutdown('exit'), HostCloseResult.closed);
    expect(s.lease.closes, 1);
    await expectLater(s.host.resume(pause), failure('SERVICE_UNAVAILABLE'));
  });

  test(
    'shutdown waits physical suspension after logical observer timeout',
    () async {
      final s = fixture.Setup();
      await s.start();
      s.resources.servicesSuspending = Completer<void>();
      final pause = s.host.suspend();
      await expectLater(
        pause.settled.timeout(Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      expect(
        await s.host.shutdown(
          'exit',
          deadline: const Duration(milliseconds: 10),
        ),
        HostCloseResult.closeBlocked,
      );
      expect(s.lease.closes, 0);
      expect(s.vault.closes, 0);
      s.resources.servicesSuspending!.complete();
      await pause.settled;
      expect(await s.host.waitForClose(), HostCloseResult.closed);
    },
  );

  test(
    'resume original deadline cannot publish late Ready or release lease',
    () async {
      final s = fixture.Setup();
      await s.start();
      final pause = s.host.suspend();
      await pause.settled;
      final physical = s.vault.paused = Completer<void>();
      final resuming = s.host.resume(
        pause,
        deadline: const Duration(milliseconds: 20),
      );
      await expectLater(resuming, failure('TIMEOUT'));
      expect(s.host.capabilities.coreUsable, isFalse);
      expect(s.host.readiness.state, isNot(ReadinessState.ready));
      expect(s.lease.closes, 0);
      s.vault.paused = null;
      physical.complete();
      expect(await s.host.shutdown('exit'), HostCloseResult.closed);
      expect(s.resources.events, isNot(contains('services.resume')));
    },
  );

  test(
    'new suspend supersedes pending resume without replacing the Host',
    () async {
      final s = fixture.Setup();
      await s.start();
      final first = s.host.suspend();
      await first.settled;
      final physical = s.vault.paused = Completer<void>();
      final oldResume = s.host.resume(first);
      final oldFailure = expectLater(oldResume, failure('NOT_READY'));
      await ram.settle();
      final next = s.host.suspend();
      expect(s.host.capabilities.coreUsable, isFalse);
      expect(identical(first, next), isFalse);
      expect(s.host.readiness.state, isNot(ReadinessState.ready));
      s.vault.paused = null;
      physical.complete();
      await oldFailure;
      expect(s.host.capabilities.coreUsable, isFalse);
      await next.settled;
      await s.host.resume(next);
      expect(s.host.capabilities.coreUsable, isTrue);
      expect(s.host.readiness.state, ReadinessState.ready);
      expect(s.host.failureCode, isNull);
      expect(s.acquisitions, 1);
      await s.host.shutdown('exit');
    },
  );

  test(
    'vault, lease and provider failure cannot reopen suspended services',
    () async {
      for (final defect in [
        'vault',
        'lease',
        'native',
        'snapshot',
        'restore',
        'workspace',
      ]) {
        final s = fixture.Setup();
        await s.start();
        final pause = s.host.suspend();
        await pause.settled;
        if (defect == 'vault') s.vault.access = VaultAccess.locked;
        if (defect == 'lease') s.lease.isHeld = false;
        if (defect == 'native')
          s.storeRuntime.error = StateError('PRIVATE_NATIVE');
        if (defect == 'snapshot')
          s.resources.revalidationError = StateError('PRIVATE_SNAPSHOT');
        if (defect == 'restore')
          s.resources.resumeError = StateError('PRIVATE_RESTORE');
        if (defect == 'workspace')
          s.resources.workspaceId = '12345678-1234-4234-9234-123456789aff';
        await expectLater(
          s.host.resume(pause),
          failure(
            defect == 'vault'
                ? 'STORAGE_BLOCKED'
                : defect == 'lease' || defect == 'workspace'
                ? 'UNAUTHORIZED'
                : 'SERVICE_UNAVAILABLE',
          ),
        );
        expect(s.host.readiness.state, isNot(ReadinessState.ready));
        expect(await s.host.shutdown('exit'), HostCloseResult.closed);
        expect(s.acquisitions, 1);
      }
    },
  );
}
