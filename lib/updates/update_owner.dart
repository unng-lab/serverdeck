import 'dart:async';

import 'package:flutter/foundation.dart';

import '../runtime/capability.dart';

enum UpdateState {
  idle,
  checking,
  current,
  available,
  downloading,
  verifying,
  ready,
  failed,
}

final class UpdateOffer {
  const UpdateOffer({
    required this.version,
    required this.notes,
    required this.publishedUtc,
    required this.setupSize,
    required this.platform,
    required this.bootstrapAbi,
    required this.storeFormat,
    required this.compatibility,
    required this.compatibilityReason,
  });
  final String version, notes, platform, compatibility, compatibilityReason;
  final int publishedUtc, setupSize, bootstrapAbi, storeFormat;
}

final class UpdateSnapshot {
  const UpdateSnapshot({
    required this.currentVersion,
    this.state = UpdateState.idle,
    this.enabled = true,
    this.offer,
    this.bytes = 0,
    this.total,
    this.code,
    this.lastAttempt,
    this.lastSuccess,
    this.deferredUntil,
    this.preparedVersion,
    this.preparedCode,
  });
  final String currentVersion;
  final UpdateState state;
  final bool enabled;
  final UpdateOffer? offer;
  final int bytes;
  final int? total, lastAttempt, lastSuccess, deferredUntil;
  final String? code;
  final String? preparedVersion, preparedCode;
  UpdateSnapshot withEnabled(bool value) => UpdateSnapshot(
    currentVersion: currentVersion,
    state: state,
    enabled: value,
    offer: offer,
    bytes: bytes,
    total: total,
    code: code,
    lastAttempt: lastAttempt,
    lastSuccess: lastSuccess,
    deferredUntil: deferredUntil,
    preparedVersion: preparedVersion,
    preparedCode: preparedCode,
  );
  bool get active => const {
    UpdateState.checking,
    UpdateState.downloading,
    UpdateState.verifying,
  }.contains(state);

  factory UpdateSnapshot.decode(Map<Object?, Object?> value) {
    int number(
      String key, {
      int minimum = 0,
      int maximum = 0x7fffffffffffffff,
    }) {
      final item = value[key];
      if (item is! int || item < minimum || item > maximum) {
        throw const FormatException('Invalid update number');
      }
      return item;
    }

    int? optional(String key) => value[key] == null ? null : number(key);
    String text(String key, int maximum) {
      final item = value[key];
      if (item is! String || item.length > maximum || item.contains('\u0000')) {
        throw const FormatException('Invalid update text');
      }
      return item;
    }

    final state = UpdateState.values.byName(text('state', 16));
    final enabled = value['enabled'];
    if (enabled is! bool) {
      throw const FormatException('Invalid update preference');
    }
    UpdateOffer? offer;
    if (const {
      UpdateState.available,
      UpdateState.downloading,
      UpdateState.verifying,
      UpdateState.ready,
    }.contains(state)) {
      final compatibility = text('compatibility', 16);
      final platform = text('platform', 32);
      if (compatibility != 'compatible' || platform != 'windows-x64') {
        throw const FormatException('Invalid offered compatibility');
      }
      offer = UpdateOffer(
        version: text('targetVersion', 32),
        notes: text('notes', 16384),
        publishedUtc: number('publishedUTC'),
        setupSize: number('setupSize', minimum: 1, maximum: 1024 * 1024 * 1024),
        platform: platform,
        bootstrapAbi: number('bootstrapAbi', minimum: 1),
        storeFormat: number('storeFormat', minimum: 1),
        compatibility: compatibility,
        compatibilityReason: text('compatibilityReason', 256),
      );
    }
    final preparedVersion = value['preparedVersion'] == null
        ? null
        : text('preparedVersion', 32);
    final preparedCode = value['preparedCode'] == null
        ? null
        : text('preparedCode', 64);
    if (preparedVersion?.isEmpty == true ||
        (preparedCode != null && preparedVersion == null)) {
      throw const FormatException('Invalid prepared update');
    }
    return UpdateSnapshot(
      currentVersion: text('currentVersion', 32),
      state: state,
      enabled: enabled,
      offer: offer,
      bytes: number('bytes', maximum: 1024 * 1024 * 1024),
      total: optional('total'),
      code: value['code'] == null ? null : text('code', 64),
      lastAttempt: optional('lastAttempt'),
      lastSuccess: optional('lastSuccess'),
      deferredUntil: optional('deferredUntil'),
      preparedVersion: preparedVersion,
      preparedCode: preparedCode,
    );
  }
}

abstract interface class UpdatePort {
  Future<UpdateSnapshot> snapshot();
  Future<bool> check();
  Future<bool> download(String version);
  Future<void> cancel();
  Future<void> setEnabled(bool enabled);
  Future<void> defer();
}

typedef ScheduleUpdate = void Function() Function(Duration, void Function());

/// Native lifecycle is optional for pure in-memory ports. Production must stop
/// native admission and await worker termination before releasing owner leases.
abstract interface class UpdateLifecyclePort {
  Future<void> stopAdmission();
  Future<void> drain();
}

final class _Changes extends ChangeNotifier {
  void changed() => notifyListeners();
}

/// Scheduling and presentation authority only. Native code verifies releases,
/// persists consent, and owns downloads; this owner has no quit/launch API.
final class UpdateOwner implements Listenable, RuntimeCapability {
  UpdateOwner({
    required this.port,
    required String currentVersion,
    int Function()? utcNow,
    Duration Function()? monotonicNow,
    ScheduleUpdate? schedule,
  }) : _snapshot = UpdateSnapshot(currentVersion: currentVersion),
       _utc = utcNow ?? _systemUtc,
       _monotonic = monotonicNow,
       _schedule = schedule ?? _timer {
    _clock.start();
  }
  final UpdatePort port;
  final int Function() _utc;
  final Duration Function()? _monotonic;
  final ScheduleUpdate _schedule;
  final _clock = Stopwatch(), _changes = _Changes();
  final _pending = <Future<void>>{};
  UpdateSnapshot _snapshot;
  UpdateSnapshot get snapshot => _snapshot;
  String? error;
  bool get canRestart =>
      !_stopped &&
      !_disposed &&
      error == null &&
      !_snapshot.active &&
      _snapshot.preparedVersion != null &&
      _snapshot.preparedVersion!.isNotEmpty &&
      _snapshot.preparedCode == null;
  bool _started = false, _stopped = false, _disposed = false;
  bool _backgroundCheck = false;
  Future<void> _commands = Future<void>.value();
  int _generation = 0;
  int _readSequence = 0;
  int? _futureAttempt;
  Duration? _rollbackAnchor;
  void Function()? _cancelTimer;
  Duration get _now => _monotonic?.call() ?? _clock.elapsed;
  static int _systemUtc() =>
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  static void Function() _timer(Duration delay, void Function() callback) {
    final timer = Timer(delay, callback);
    return timer.cancel;
  }

  @override
  String get id => 'updates';
  @override
  void addListener(VoidCallback listener) => _changes.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);
  void _notify() {
    if (!_disposed) _changes.changed();
  }

  Future<void> start() async {
    if (_started || _stopped) return;
    _started = true;
    await refresh();
  }

  Future<void> refresh() => _keep(_refresh());
  Future<void> _refresh() async {
    if (_stopped) return;
    final generation = _generation;
    final sequence = ++_readSequence;
    try {
      final value = await port.snapshot();
      if (_stopped || generation != _generation || sequence != _readSequence)
        return;
      _snapshot = value;
      error = null;
      if (value.state != UpdateState.checking) _backgroundCheck = false;
      _notify();
      _arm();
    } catch (_) {
      if (_stopped || generation != _generation || sequence != _readSequence)
        return;
      error = 'STORAGE_IO';
      _notify();
      _cancelTimer?.call();
      _cancelTimer = null;
    }
  }

  Duration _automaticDelay() {
    final utc = _utc(), attempt = _snapshot.lastAttempt;
    if (attempt != null && attempt > utc) {
      if (_futureAttempt != attempt) {
        _futureAttempt = attempt;
        _rollbackAnchor = _now;
      }
      final remaining = const Duration(hours: 24) - (_now - _rollbackAnchor!);
      return remaining.isNegative ? Duration.zero : remaining;
    }
    _futureAttempt = null;
    _rollbackAnchor = null;
    var due = attempt == null ? utc : attempt + 86400;
    final deferred = _snapshot.deferredUntil;
    if (deferred != null && deferred > due) due = deferred;
    final remaining = due > utc ? due - utc : 0;
    return Duration(seconds: remaining > 86400 ? 86400 : remaining);
  }

  void _arm() {
    _cancelTimer?.call();
    _cancelTimer = null;
    if (_stopped || !_started) return;
    if (_snapshot.active) {
      _cancelTimer = _schedule(const Duration(milliseconds: 500), () {
        unawaited(refresh());
      });
    } else if (_snapshot.enabled) {
      _cancelTimer = _schedule(_automaticDelay(), () {
        unawaited(_check(automatic: true));
      });
    }
  }

  Future<void> _keep(Future<void> future) {
    late final Future<void> tracked;
    tracked = future.whenComplete(() => _pending.remove(tracked));
    _pending.add(tracked);
    return tracked;
  }

  Future<void> _command(Future<void> Function() action) {
    // Serialize admissions, but let cancellation/preferences proceed as soon as
    // the prior action is acknowledged, independently of a delayed snapshot.
    final admitted = _commands.then((_) => _runCommand(action));
    _commands = admitted.then((_) {});
    return _keep(
      admitted.then((success) async {
        if (success) await refresh();
      }),
    );
  }

  Future<bool> _runCommand(Future<void> Function() action) async {
    if (_stopped) return false;
    final generation = _generation;
    try {
      await action();
      return !_stopped && generation == _generation;
    } catch (_) {
      if (!_stopped && generation == _generation) {
        error = 'STORAGE_IO';
        _notify();
      }
      return false;
    }
  }

  Future<void> _check({required bool automatic}) => _command(() async {
    if (_snapshot.active) return;
    if (automatic &&
        (!_snapshot.enabled || _automaticDelay() > Duration.zero)) {
      _arm();
      return;
    }
    _backgroundCheck = automatic;
    final accepted = await port.check();
    _acknowledge(
      _operation(
        accepted ? UpdateState.checking : UpdateState.failed,
        code: !accepted && _snapshot.code == 'UPDATE_NOT_CONFIGURED'
            ? _snapshot.code
            : null,
        lastAttempt: _utc(),
      ),
    );
  });
  Future<void> check() => _check(automatic: false);

  /// Retain the confirmed projection through queued admission, including when
  /// another command refreshes a same-version offer before this action runs.
  Future<void> download(UpdateOffer confirmedOffer) => _command(() async {
    if (_snapshot.state != UpdateState.available ||
        !identical(_snapshot.offer, confirmedOffer)) {
      return;
    }
    final offer = _snapshot.offer;
    if (await port.download(confirmedOffer.version)) {
      _backgroundCheck = false;
      _acknowledge(_operation(UpdateState.downloading, offer: offer));
    }
  });
  Future<void> cancel() => _command(() async {
    await port.cancel();
    if (!_stopped) {
      // Receipt is not a cancellation outcome: publication may already have
      // won. Keep the last phase until an authoritative snapshot confirms it.
      ++_readSequence;
      _arm();
    }
  });
  UpdateSnapshot _operation(
    UpdateState state, {
    UpdateOffer? offer,
    String? code,
    int? lastAttempt,
  }) => UpdateSnapshot(
    currentVersion: _snapshot.currentVersion,
    state: state,
    enabled: _snapshot.enabled,
    offer: offer,
    code: code,
    lastAttempt: lastAttempt ?? _snapshot.lastAttempt,
    lastSuccess: _snapshot.lastSuccess,
    deferredUntil: _snapshot.deferredUntil,
    preparedVersion: _snapshot.preparedVersion,
    preparedCode: _snapshot.preparedCode,
  );
  void _acknowledge(UpdateSnapshot value) {
    if (_stopped) return;
    ++_readSequence; // A pre-ack read cannot restore scheduling authority.
    _snapshot = value;
    _notify();
    _arm();
  }

  Future<void> defer() => _command(() async {
    if (_snapshot.state != UpdateState.available) return;
    await port.defer();
    final now = _utc();
    final scheduled = (_snapshot.lastAttempt ?? 0) + 86400;
    _acknowledge(
      UpdateSnapshot(
        currentVersion: _snapshot.currentVersion,
        enabled: _snapshot.enabled,
        lastAttempt: _snapshot.lastAttempt,
        lastSuccess: _snapshot.lastSuccess,
        deferredUntil: scheduled > now ? scheduled : now + 86400,
        preparedVersion: _snapshot.preparedVersion,
        preparedCode: _snapshot.preparedCode,
      ),
    );
  });
  Future<void> setEnabled(bool enabled) => _command(() async {
    await port.setEnabled(enabled);
    _acknowledge(_snapshot.withEnabled(enabled));
    if (!enabled && _backgroundCheck) {
      _backgroundCheck = false;
      await port.cancel();
    }
  });
  @override
  Future<void> stopAdmission() async {
    _stopped = true;
    ++_generation;
    _cancelTimer?.call();
    _cancelTimer = null;
    final Object lifecycle = port;
    if (lifecycle is UpdateLifecyclePort) await lifecycle.stopAdmission();
  }

  @override
  Future<void> cancelPending() async => port.cancel();
  @override
  Future<void> closeSessions() async {}
  @override
  Future<void> drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
    final Object lifecycle = port;
    if (lifecycle is UpdateLifecyclePort) await lifecycle.drain();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stopAdmission();
    await cancelPending();
    await drain();
    _disposed = true;
    _clock.stop();
    _changes.dispose();
  }
}
