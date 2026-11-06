import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/updates/update_owner.dart';

final class _Deadline {
  _Deadline(this.at, this.callback);
  final Duration at;
  final void Function() callback;
  bool cancelled = false;
}

final class _Clock {
  int utc = 100000;
  Duration now = Duration.zero;
  final deadlines = <_Deadline>[];
  void Function() schedule(Duration delay, void Function() callback) {
    final deadline = _Deadline(now + delay, callback);
    deadlines.add(deadline);
    return () => deadline.cancelled = true;
  }

  Future<void> advance(Duration duration, {bool moveUtc = true}) async {
    now += duration;
    if (moveUtc) utc += duration.inSeconds;
    for (var step = 0; step < 30; step++) {
      final due = deadlines.where((d) => !d.cancelled && d.at <= now).toList();
      if (due.isEmpty) break;
      for (final deadline in due) {
        deadline.cancelled = true;
        deadline.callback();
      }
      for (var tick = 0; tick < 10; tick++) {
        await Future<void>.value();
      }
    }
  }

  List<_Deadline> get active => deadlines.where((d) => !d.cancelled).toList();
}

class _Port implements UpdatePort {
  _Port(this.clock, {this.enabled = true, this.attempt});
  final _Clock clock;
  bool enabled;
  int? attempt, deferred;
  UpdateState state = UpdateState.current;
  int checks = 0, downloads = 0, cancels = 0, reads = 0;
  Completer<UpdateSnapshot>? reply;
  Completer<void>? enabling;
  bool accepted = true, failSnapshots = false;
  bool noOpCancel = false;
  UpdateOffer? offer;
  @override
  Future<UpdateSnapshot> snapshot() async {
    reads++;
    if (reply != null) return reply!.future;
    if (failSnapshots)
      throw const FormatException('synthetic snapshot failure');
    return UpdateSnapshot(
      currentVersion: '0.1.0',
      state: state,
      enabled: enabled,
      lastAttempt: attempt,
      deferredUntil: deferred,
      offer: offer,
    );
  }

  @override
  Future<bool> check() async {
    checks++;
    attempt = clock.utc;
    state = accepted ? UpdateState.checking : UpdateState.failed;
    return accepted;
  }

  @override
  Future<bool> download(String version) async {
    downloads++;
    state = UpdateState.downloading;
    return true;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    if (!noOpCancel) state = UpdateState.failed;
  }

  @override
  Future<void> setEnabled(bool value) async {
    if (enabling != null) await enabling!.future;
    enabled = value;
  }

  @override
  Future<void> defer() async {
    deferred = clock.utc + 86400;
    state = UpdateState.idle;
  }
}

const _offer = UpdateOffer(
  version: '0.2.0',
  notes: 'Исправления',
  publishedUtc: 90000,
  setupSize: 123456,
  platform: 'windows-x64',
  bootstrapAbi: 1,
  storeFormat: 2,
  compatibility: 'compatible',
  compatibilityReason: 'Совместимо',
);

UpdateOwner _owner(_Port port, _Clock clock) => UpdateOwner(
  port: port,
  currentVersion: '0.1.0',
  utcNow: () => clock.utc,
  monotonicNow: () => clock.now,
  schedule: clock.schedule,
);
const _changedOffer = UpdateOffer(
  version: '0.2.0',
  notes: 'Изменённое предложение',
  publishedUtc: 90001,
  setupSize: 654321,
  platform: 'windows-x64',
  bootstrapAbi: 1,
  storeFormat: 2,
  compatibility: 'compatible',
  compatibilityReason: 'Совместимо',
);

final class _LifecyclePort extends _Port implements UpdateLifecyclePort {
  _LifecyclePort(_Clock clock) : super(clock, enabled: false);
  bool failStop = true;
  int stops = 0, drains = 0;
  final released = Completer<void>();
  @override
  Future<void> stopAdmission() async {
    stops++;
    if (failStop) throw StateError('synthetic native stop failure');
  }

  @override
  Future<void> drain() async {
    drains++;
    await released.future;
  }
}

void main() {
  test(
    'local retirement survives native stop failure and drains both owners',
    () async {
      final clock = _Clock(), port = _LifecyclePort(_Clock());
      final owner = UpdateOwner(
        port: port,
        currentVersion: '0.1.0',
        schedule: clock.schedule,
      );
      port.reply = Completer<UpdateSnapshot>();
      final starting = owner.start();
      await expectLater(owner.stopAdmission(), throwsStateError);
      await owner.check();
      expect(port.checks, 0);
      port.failStop = false;
      await owner.stopAdmission();
      expect(port.stops, 2);
      var done = false;
      final draining = owner.drain().then((_) => done = true);
      await Future<void>.value();
      expect(port.drains, 0);
      port.reply!.complete(
        const UpdateSnapshot(currentVersion: '0.1.0', enabled: false),
      );
      await starting;
      for (var i = 0; i < 5; i++) {
        await Future<void>.value();
      }
      expect(port.drains, 1);
      expect(done, isFalse);
      port.released.complete();
      await draining;
      expect(done, isTrue);
      expect(clock.active, isEmpty);
      await owner.dispose();
      expect(port.cancels, 1);
    },
  );
  test(
    'late cancel cannot claim cancellation of committed native readiness',
    () async {
      for (final fail in [false, true]) {
        final clock = _Clock();
        final port = _Port(clock, enabled: false)
          ..state = UpdateState.verifying;
        port.offer = _offer;
        final owner = _owner(port, clock);
        await owner.start();
        port.state = UpdateState.ready;
        port.noOpCancel = true;
        final reply = Completer<UpdateSnapshot>();
        port.reply = reply;
        final cancelling = owner.cancel();
        for (var step = 0; step < 10; step++) {
          await Future<void>.value();
        }
        expect(owner.snapshot.code, isNot('CANCELLED'));
        expect(owner.snapshot.offer, same(_offer));
        if (fail) {
          reply.completeError(const FormatException('synthetic read failure'));
        } else {
          reply.complete(
            const UpdateSnapshot(
              currentVersion: '0.1.0',
              state: UpdateState.ready,
              enabled: false,
              offer: _offer,
            ),
          );
        }
        await cancelling;
        expect(owner.snapshot.code, isNot('CANCELLED'));
        port.reply = null;
        await owner.refresh();
        expect(owner.snapshot.state, UpdateState.ready);
        await owner.dispose();
      }
    },
  );
  test(
    'cancel before attempt snapshot cannot schedule an immediate new check',
    () async {
      for (final previous in [null, 100000 - 90000]) {
        final clock = _Clock();
        final port = _Port(clock, attempt: previous);
        final owner = _owner(port, clock);
        await owner.start();
        final delayed = Completer<UpdateSnapshot>();
        port.reply = delayed;
        final checking = owner.check();
        for (var step = 0; step < 10; step++) {
          await Future<void>.value();
        }
        final cancelling = owner.cancel();
        for (var step = 0; step < 10; step++) {
          await Future<void>.value();
        }
        await clock.advance(Duration.zero);
        expect(port.checks, 1);
        expect(owner.snapshot.lastAttempt, clock.utc);
        delayed.complete(
          UpdateSnapshot(
            currentVersion: '0.1.0',
            enabled: true,
            state: UpdateState.failed,
            lastAttempt: port.attempt,
          ),
        );
        await checking;
        await cancelling;
        await owner.dispose();
      }
    },
  );
  test('false check admission never projects an active operation', () async {
    final clock = _Clock();
    final port = _Port(clock, enabled: false)..accepted = false;
    final owner = _owner(port, clock);
    await owner.start();
    final delayed = Completer<UpdateSnapshot>();
    port.reply = delayed;
    final checking = owner.check();
    for (var step = 0; step < 10; step++) {
      await Future<void>.value();
    }
    expect(owner.snapshot.active, isFalse);
    delayed.complete(
      const UpdateSnapshot(
        currentVersion: '0.1.0',
        state: UpdateState.failed,
        enabled: false,
        code: 'UPDATE_NOT_CONFIGURED',
      ),
    );
    await checking;
    expect(owner.snapshot.code, 'UPDATE_NOT_CONFIGURED');
    port.reply = null;
    port.failSnapshots = true;
    await owner.check();
    expect(owner.snapshot.active, isFalse);
    expect(owner.snapshot.code, 'UPDATE_NOT_CONFIGURED');
    expect(owner.error, 'STORAGE_IO');
    await owner.dispose();
  });
  test('queued consent cannot follow a same-version refreshed offer', () async {
    final clock = _Clock();
    final port = _Port(clock, enabled: false)..state = UpdateState.available;
    port.offer = _offer;
    final owner = _owner(port, clock);
    await owner.start();
    port.enabling = Completer<void>();
    final setting = owner.setEnabled(false);
    for (var step = 0; step < 5; step++) {
      await Future<void>.value();
    }
    final downloading = owner.download(_offer);
    port.offer = _changedOffer;
    await owner.refresh();
    port.enabling!.complete();
    await setting;
    await downloading;
    expect(port.downloads, 0);
    await owner.dispose();
  });
  test(
    'accepted check invalidates old offer before its delayed refresh',
    () async {
      final clock = _Clock();
      final port = _Port(clock, enabled: false)..state = UpdateState.available;
      port.offer = _offer;
      final owner = _owner(port, clock);
      await owner.start();
      final delayed = Completer<UpdateSnapshot>();
      port.reply = delayed;
      final check = owner.check();
      for (var step = 0; step < 10; step++) {
        await Future<void>.value();
      }
      expect(owner.snapshot.state, UpdateState.checking);
      expect(owner.snapshot.offer, isNull);
      final attemptedDownload = owner.download(_offer);
      for (var step = 0; step < 10; step++) {
        await Future<void>.value();
      }
      expect(port.downloads, 0);
      delayed.complete(
        const UpdateSnapshot(
          currentVersion: '0.1.0',
          state: UpdateState.checking,
          enabled: false,
        ),
      );
      await check;
      await attemptedDownload;
      await owner.dispose();
    },
  );
  test('retirement fences a late preference acknowledgement', () async {
    final clock = _Clock();
    final port = _Port(clock, attempt: clock.utc);
    final owner = _owner(port, clock);
    await owner.start();
    port.enabling = Completer<void>();
    final setting = owner.setEnabled(false);
    for (var step = 0; step < 5; step++) {
      await Future<void>.value();
    }
    await owner.stopAdmission();
    port.enabling!.complete();
    await setting;
    expect(owner.snapshot.enabled, isTrue);
    expect(port.enabled, isFalse);
    expect(clock.active, isEmpty);
    await owner.dispose();
  });
  test(
    'acknowledged disable or deferral gates a stale scheduled timer',
    () async {
      for (final defer in [false, true]) {
        final clock = _Clock();
        final port = _Port(clock, attempt: clock.utc - (defer ? 86401 : 86399));
        if (defer) {
          port.state = UpdateState.available;
          port.offer = _offer;
        }
        final owner = _owner(port, clock);
        await owner.start();
        final delayed = Completer<UpdateSnapshot>();
        port.reply = delayed;
        final command = defer ? owner.defer() : owner.setEnabled(false);
        for (var step = 0; step < 10; step++) {
          await Future<void>.value();
        }
        await clock.advance(const Duration(seconds: 1));
        expect(port.checks, 0);
        if (defer) {
          expect(owner.snapshot.state, UpdateState.idle);
        } else {
          expect(owner.snapshot.enabled, isFalse);
          expect(clock.active, isEmpty);
        }
        delayed.complete(
          UpdateSnapshot(
            currentVersion: '0.1.0',
            enabled: defer,
            lastAttempt: port.attempt,
            deferredUntil: port.deferred,
          ),
        );
        await command;
        port.reply = null;
        await owner.check(); // Explicit manual action remains available.
        expect(port.checks, 1);
        await owner.dispose();
      }
    },
  );
  test('disable and cancel survive a delayed command snapshot', () async {
    for (final disable in [false, true]) {
      final clock = _Clock();
      final port = _Port(clock, enabled: disable);
      final owner = _owner(port, clock);
      await owner.start();
      final delayed = Completer<UpdateSnapshot>();
      port.reply = delayed;
      Future<void>? checking;
      if (disable) {
        await clock.advance(Duration.zero);
      } else {
        checking = owner.check();
        for (var step = 0; step < 10; step++) {
          await Future<void>.value();
        }
      }
      expect(port.checks, 1);
      port.reply = null;
      if (disable) {
        await owner.setEnabled(false);
        expect(port.enabled, isFalse);
      } else {
        await owner.cancel();
      }
      expect(port.cancels, 1);
      delayed.complete(
        const UpdateSnapshot(
          currentVersion: '0.1.0',
          state: UpdateState.checking,
        ),
      );
      await checking;
      await owner.drain();
      expect(owner.snapshot.state, UpdateState.failed);
      expect(owner.snapshot.enabled, isFalse);
      await owner.dispose();
    }
  });
  test(
    'disabled manual check bypasses schedule without enabling or downloading',
    () async {
      final clock = _Clock();
      final manualPort = _Port(clock, enabled: false, attempt: clock.utc);
      final owner = _owner(manualPort, clock);
      await owner.start();
      expect(clock.active, isEmpty);
      await owner.check();
      expect(manualPort.checks, 1);
      expect(manualPort.enabled, isFalse);
      expect(manualPort.downloads, 0);
      manualPort.state = UpdateState.available;
      manualPort.offer = _offer;
      await clock.advance(const Duration(milliseconds: 500));
      expect(owner.snapshot.offer?.setupSize, 123456);
      expect(clock.active, isEmpty);
      expect(manualPort.downloads, 0);
      await owner.dispose();
    },
  );

  test(
    'persisted daily attempt and rollback use one bounded monotonic wait',
    () async {
      final clock = _Clock();
      final port = _Port(clock, attempt: clock.utc - 3600);
      final owner = _owner(port, clock);
      await owner.start();
      await clock.advance(const Duration(hours: 22));
      expect(port.checks, 0);
      await clock.advance(const Duration(hours: 1));
      expect(port.checks, 1);
      port.state = UpdateState.current;
      port.attempt = clock.utc + 1000000;
      await owner.refresh();
      await clock.advance(const Duration(hours: 23), moveUtc: false);
      expect(port.checks, 1);
      await owner.refresh(); // Polling cannot restart the rollback timer.
      await clock.advance(const Duration(hours: 1), moveUtc: false);
      expect(port.checks, 2);
      expect(port.downloads, 0);
      await owner.dispose();
    },
  );

  test(
    'disable cancels automatic check but retains user-confirmed download',
    () async {
      final clock = _Clock();
      final automaticPort = _Port(clock);
      final owner = _owner(automaticPort, clock);
      await owner.start();
      await clock.advance(Duration.zero);
      expect(automaticPort.checks, 1);
      await owner.setEnabled(false);
      expect(automaticPort.cancels, 1);
      automaticPort.state = UpdateState.available;
      automaticPort.offer = _offer;
      await owner.refresh();
      await owner.download(_changedOffer);
      expect(automaticPort.downloads, 0);
      await owner.download(_offer);
      expect(automaticPort.downloads, 1);
      await owner.setEnabled(false);
      expect(automaticPort.cancels, 1);
      expect(automaticPort.checks, 1);
      await owner.dispose();
    },
  );

  test('older snapshot cannot overwrite command refresh', () async {
    final clock = _Clock();
    final port = _Port(clock, enabled: false);
    final owner = _owner(port, clock);
    await owner.start();
    final oldReply = Completer<UpdateSnapshot>();
    port.reply = oldReply;
    final oldRead = owner.refresh();
    port.reply = null;
    port.state = UpdateState.available;
    port.offer = _offer;
    await owner.refresh();
    oldReply.complete(const UpdateSnapshot(currentVersion: 'late'));
    await oldRead;
    expect(owner.snapshot.offer?.version, _offer.version);
    await owner.dispose();
  });

  test(
    'retirement rejects late snapshot and drains outstanding work',
    () async {
      final clock = _Clock(), port = _Port(_Clock(), enabled: false);
      final owner = _owner(port, clock);
      await owner.start();
      port.reply = Completer<UpdateSnapshot>();
      final request = owner.refresh();
      await owner.stopAdmission();
      var drained = false;
      final draining = owner.drain().then((_) => drained = true);
      await Future<void>.value();
      expect(drained, isFalse);
      port.reply!.complete(
        const UpdateSnapshot(currentVersion: 'foreign-late'),
      );
      await request;
      await draining;
      expect(owner.snapshot.currentVersion, '0.1.0');
      expect(clock.active, isEmpty);
      await owner.check();
      expect(port.checks, 0);
      await owner.dispose();
    },
  );

  test(
    'snapshot requires signed offer fields separate from observed length',
    () {
      final map = <Object?, Object?>{
        'state': 'available',
        'currentVersion': '0.1.0',
        'enabled': true,
        'targetVersion': '0.2.0',
        'notes': 'Исправления',
        'bytes': 0,
        'publishedUTC': 90000,
        'setupSize': 123456,
        'platform': 'windows-x64',
        'bootstrapAbi': 1,
        'storeFormat': 2,
        'compatibility': 'compatible',
        'compatibilityReason': 'Совместимо',
        'preparedVersion': '0.1.1',
        'preparedCode': 'RELEASE_REVOKED',
      };
      final decoded = UpdateSnapshot.decode(map);
      expect(decoded.offer?.publishedUtc, 90000);
      expect(decoded.offer?.setupSize, 123456);
      expect(decoded.total, isNull);
      expect(decoded.preparedVersion, '0.1.1');
      expect(decoded.withEnabled(false).preparedCode, 'RELEASE_REVOKED');
      final orphan = {...map}..remove('preparedVersion');
      expect(
        () => UpdateSnapshot.decode(orphan),
        throwsA(isA<FormatException>()),
      );
      for (final key in [
        'publishedUTC',
        'setupSize',
        'platform',
        'bootstrapAbi',
        'storeFormat',
        'compatibility',
      ]) {
        final malformed = {...map}..remove(key);
        expect(
          () => UpdateSnapshot.decode(malformed),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );
}
