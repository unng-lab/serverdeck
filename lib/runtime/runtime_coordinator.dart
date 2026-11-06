import 'dart:async';

import 'package:flutter/foundation.dart';

import 'capability.dart';
import 'native_platform.dart';

enum RuntimeState {
  starting,
  running,
  storageBlocked,
  shuttingDown,
  shutdownBlocked,
  terminated,
}

class RuntimeCoordinator extends ChangeNotifier {
  RuntimeCoordinator({
    required this.platform,
    required this.store,
    required this.epoch,
    this.shutdownTimeout = const Duration(seconds: 10),
  });
  final RuntimePlatform platform;
  final RuntimeStore store;
  final String epoch;
  final Duration shutdownTimeout;
  final List<RuntimeCapability> _capabilities = [];
  final Map<String, Future<void>> _steps = {};
  StreamSubscription<PlatformEvent>? _subscription;
  Future<void> _events = Future.value();
  Future<void>? _shutdown, _startup;
  int _seq = 0;
  RuntimeState state = RuntimeState.starting;
  WindowState window = WindowState.visible;
  bool trayAvailable = false;
  String? error;
  bool get acceptsOperations => state == RuntimeState.running;
  bool updateRestartRequested = false;
  Future<bool>? _restartRequest;
  String? _restartVersion;

  Future<bool> requestUpdateRestart(String version) {
    if (_restartRequest != null)
      return version == _restartVersion
          ? _restartRequest!
          : Future.value(false);
    if (!acceptsOperations) return Future.value(false);
    _restartVersion = version;
    return _restartRequest = _requestUpdateRestart(version).whenComplete(() {
      _restartRequest = null;
      _restartVersion = null;
    });
  }

  Future<bool> _requestUpdateRestart(String version) async {
    bool accepted;
    try {
      accepted = await platform.requestUpdateRestart(version);
    } catch (_) {
      accepted = false;
    }
    if (!accepted) return false;
    updateRestartRequested = true;
    await requestExit();
    return true;
  }

  void register(RuntimeCapability capability) {
    if (state != RuntimeState.starting ||
        _startup != null ||
        _capabilities.any((c) => c.id == capability.id)) {
      throw StateError('Capability registration is closed or id is duplicated');
    }
    _capabilities.add(capability);
  }

  Future<void> start() {
    return _startup ??= _start();
  }

  Future<void> _start() async {
    _subscription = platform.events.listen((event) {
      _events = _events.then((_) => _event(event)).catchError((Object _) {
        error = 'Ошибка связи с платформой';
        notifyListeners();
      });
    });
    try {
      await _snapshot();
      if (state != RuntimeState.starting) return;
      await retryOpen();
    } catch (_) {
      if (state == RuntimeState.starting) {
        state = RuntimeState.storageBlocked;
        error = 'Не удалось инициализировать приложение';
        notifyListeners();
      }
    }
  }

  Future<void>? _opening;
  Future<void> retryOpen() {
    if (state != RuntimeState.starting &&
        state != RuntimeState.storageBlocked) {
      return Future.value();
    }
    if (_opening != null) return _opening!;
    _opening = _open().whenComplete(() => _opening = null);
    return _opening!.then((_) => _snapshot());
  }

  Future<void> _open() async {
    try {
      await store.open();
      if (state == RuntimeState.starting ||
          state == RuntimeState.storageBlocked) {
        state = RuntimeState.running;
        error = null;
      } else {
        // Shutdown may have closed admission while native/Isar open awaited.
        store.stopAdmission();
      }
    } catch (_) {
      if (state == RuntimeState.starting ||
          state == RuntimeState.storageBlocked) {
        state = RuntimeState.storageBlocked;
        error = 'Не удалось открыть данные. Существующие данные сохранены.';
      }
    }
    notifyListeners();
  }

  Future<void> _snapshot() async {
    final value = await platform.snapshot(runtimeState: state.name);
    if (value.epoch != epoch || value.seq < _seq) return;
    _seq = value.seq;
    window = value.window;
    trayAvailable = value.trayAvailable;
    if (value.osEnding || value.exitRequested) {
      updateRestartRequested = !value.osEnding && value.updateRestartRequested;
      await requestExit();
    }
    notifyListeners();
  }

  Future<void> _event(PlatformEvent event) async {
    if (event.epoch != epoch ||
        event.seq <= _seq ||
        state == RuntimeState.terminated)
      return;
    if (event.seq != _seq + 1) {
      await _snapshot();
      if (event.seq <= _seq) return;
    }
    // Snapshot reconciles facts; irreversible exit events remain latched natively.
    if (event.seq > _seq) _seq = event.seq;
    switch (event.type) {
      case 'trayExit':
      case 'osSessionEnding':
        updateRestartRequested = false;
        await requestExit();
      case 'updateRestart':
        updateRestartRequested = true;
        await requestExit();
      case 'trayOpen':
      case 'activationRequested':
        await platform.restore();
        window = WindowState.visible;
      case 'closeRequested':
        if (await platform.hideToTray())
          window = WindowState.trayHidden;
        else {
          window = WindowState.visible;
          trayAvailable = false;
        }
      case 'trayLost':
        trayAvailable = false;
        await platform.restore();
        window = WindowState.visible;
      case 'trayReady':
        trayAvailable = true;
    }
    notifyListeners();
  }

  Future<void> retryTray() async {
    if (state == RuntimeState.terminated) return;
    trayAvailable = await platform.retryTray();
    if (!trayAvailable) {
      await platform.restore();
      window = WindowState.visible;
    }
    notifyListeners();
  }

  Future<void> _step(String id, Future<void> Function() action) {
    return _steps.putIfAbsent(id, () {
      return Future.sync(action).catchError((Object error, StackTrace stack) {
        _steps.remove(id);
        Error.throwWithStackTrace(error, stack);
      });
    });
  }

  Future<void> requestExit() {
    if (state == RuntimeState.terminated) return Future.value();
    if (_shutdown != null) return _shutdown!;
    state = RuntimeState.shuttingDown;
    store.stopAdmission();
    error = null;
    notifyListeners();
    return _shutdown = _exit().whenComplete(() => _shutdown = null);
  }

  Future<void> _cleanup() async {
    final elapsed = Stopwatch()..start();
    Future<void> stage(String id, Future<void> Function() action) {
      final remaining = shutdownTimeout - elapsed.elapsed;
      if (remaining <= Duration.zero)
        throw TimeoutException('Shutdown deadline');
      return _step(id, action).timeout(remaining);
    }

    Future<bool> allCapabilities(
      String name,
      Future<void> Function(RuntimeCapability) action,
    ) async {
      // Start all independent owners even when another one fails or stalls.
      // Retain each underlying future: timeout does not cause duplicate cleanup.
      final attempts = [
        for (final c in _capabilities) _step('${c.id}/$name', () => action(c)),
      ];
      final remaining = shutdownTimeout - elapsed.elapsed;
      final wait = remaining > Duration.zero ? remaining : Duration.zero;
      final results = await Future.wait(
        attempts.map((attempt) async {
          try {
            await attempt.timeout(wait);
            return true;
          } catch (_) {
            return false;
          }
        }),
      );
      return results.every((success) => success);
    }

    final stopped = await allCapabilities('stop', (c) => c.stopAdmission());
    final cancelled = await allCapabilities('cancel', (c) => c.cancelPending());
    final sessions = await allCapabilities(
      'sessions',
      (c) => c.closeSessions(),
    );
    final drained = await allCapabilities('drain', (c) => c.drain());
    if (!stopped || !cancelled || !sessions || !drained) {
      throw StateError('Capability cleanup incomplete');
    }
    await stage('opening', () async {
      await _opening;
      store.stopAdmission();
    });
    await stage('writes', store.finishWrites);
    if (!await allCapabilities('dispose', (c) => c.dispose())) {
      throw StateError('Capability disposal incomplete');
    }
    await stage('store', store.close);
    await stage('activation', platform.closeActivation);
    await stage('exit', platform.finishExit);
  }

  Future<void> _exit() async {
    try {
      await _cleanup();
      state = RuntimeState.terminated;
    } catch (_) {
      state = RuntimeState.shutdownBlocked;
      error = updateRestartRequested
          ? 'Не удалось безопасно завершить работу. Повторите завершение обновления.'
          : 'Не удалось безопасно завершить работу. Повторите «Выход» в трее.';
      try {
        await platform.restore();
      } catch (_) {
        error = 'Не удалось безопасно завершить работу или восстановить окно. Повторите «Выход» в трее.';
      }
      window = WindowState.visible;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
