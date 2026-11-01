import 'dart:async';

import 'package:serverdeck_engine/hosting/engine_host.dart';
import 'package:serverdeck_engine/hosting/worker_controller.dart';
import 'package:serverdeck_engine/hosting/capability_snapshot.dart';

enum DesktopAction {
  closeWindow,
  open,
  servers,
  settings,
  exit,
  trayUnavailable,
  trayAvailable,
  suspend,
  resume,
}

enum DesktopSection { servers, software, logs, jobs, settings }

enum BlockedChoice { wait, force, stay }

abstract interface class DesktopPlatform {
  Stream<DesktopAction> get events;
  Future<bool> initialize();
  Future<bool> hide();
  Future<void> show();
  Future<void> update(DesktopEngineStatus status);
  Future<bool> fallbackClose();
  Future<bool> confirmExit(int? unresolvedJobs);
  Future<BlockedChoice> blockedClose();
  Future<void> finishExit();
  Future<void> forceExit();
}

final class DesktopViewState {
  const DesktopViewState(
    this.visible,
    this.section,
    this.epoch,
    this.navigationEpoch,
  );
  final bool visible;
  final DesktopSection section;
  final int epoch, navigationEpoch;
}

/// Owns tray/app lifetime independently of any window's client. Native dialogs
/// are user actions, never permission to replay/cancel an accepted remote job.
final class DesktopLifetime {
  DesktopLifetime({
    required this.engine,
    required this.platform,
    void Function(Duration, void Function())? schedule,
  }) : _schedule = schedule ?? _timer;
  final DesktopEngineControl engine;
  final DesktopPlatform platform;
  final void Function(Duration, void Function()) _schedule;
  final _views = StreamController<DesktopViewState>.broadcast(sync: true);
  StreamSubscription<DesktopAction>? _events;
  Future<void>? _initializing,
      _windowWork,
      _exitWork,
      _closingWindow,
      _finishing;
  Future<HostCloseResult>? _waiting;
  bool _tray = false,
      _desiredVisible = true,
      _visible = true,
      _exiting = false,
      _finished = false,
      _blockedPrompt = false,
      _physicalClosed = false;
  int _epoch = 0,
      _revision = 0,
      _trayRevision = 0,
      _navigationEpoch = 0,
      _openRequests = 0;
  DesktopSection _section = DesktopSection.servers;
  DesktopEngineStatus? _status;
  bool _workspaceBusy = false;
  bool _started = false,
      _polling = false,
      _pollAgain = false,
      _pollScheduled = false,
      _resumeRequested = false;
  int _powerRevision = 0;
  Stream<DesktopViewState> get views => _views.stream;
  DesktopViewState get view =>
      DesktopViewState(_visible, _section, _epoch, _navigationEpoch);
  bool get trayAvailable => _tray;
  bool get isExiting => _exiting;
  static void _timer(Duration d, void Function() action) {
    Timer(d, action);
  }

  void _publish(bool visible) {
    if (_visible != visible) {
      _visible = visible;
      _epoch++;
    }
    _views.add(view);
  }

  Future<void> initialize() {
    if (_initializing != null) return _initializing!;
    final done = Completer<void>();
    _initializing = done.future;
    done.future.ignore();
    _events = platform.events.listen(
      (event) {
        handle(event).ignore();
      },
      onError: (Object _, StackTrace __) {
        handle(DesktopAction.trayUnavailable).ignore();
      },
    );
    () async {
      final trayRevision = _trayRevision;
      try {
        final available = await platform.initialize();
        if (trayRevision == _trayRevision) {
          _tray = available;
          engine.setTrayAvailable(_tray);
        }
      } catch (_) {
        if (trayRevision == _trayRevision) {
          _tray = false;
          engine.setTrayAvailable(false);
        }
      }
      if (!_tray) await _showWindow();
      _started = true;
      engine.start().then<void>((status) {
        if (status.phase == 'busy') {
          _workspaceBusy = true;
          // An early close may already have hidden this window while the
          // acquisition was pending. Keep the conflict explanation reachable.
          if (!_exiting && !_finished) showWindow().ignore();
        }
      }).ignore();
      _poll();
    }().then<void>(
      done.complete,
      onError: (Object _, StackTrace __) => done.complete(),
    );
    return done.future;
  }

  void _poll() {
    if (_finished) return;
    if (_polling) {
      _pollAgain = true;
      return;
    }
    _polling = true;
    () async {
      do {
        _pollAgain = false;
        final revision = _powerRevision;
        try {
          final sampled = await engine.refreshDesktopStatus();
          if (_finished) return;
          if (revision != _powerRevision) {
            _pollAgain = true;
            continue;
          }
          _status = sampled;
          if (_resumeRequested &&
              sampled.status.phase == 'ready' &&
              !_exiting) {
            _resumeRequested = false;
            _retireWindow();
          }
          await platform.update(_status!);
        } catch (_) {
          if (_finished) return;
          if (revision != _powerRevision) {
            _pollAgain = true;
            continue;
          }
          _status = DesktopEngineStatus(
            WorkerStatus.fromJson({
              'phase': 'failed',
              'reason': 'SERVICE_UNAVAILABLE',
              'readiness': null,
              'capabilities': EngineCapabilities.unavailable(
                engine.platformKind,
                reason: 'SERVICE_UNAVAILABLE',
              ).toJson(),
            }),
            0,
            null,
          );
          try {
            await platform.update(_status!);
          } catch (_) {
            /* no private diagnostics */
          }
        }
      } while (_pollAgain && !_finished);
    }().whenComplete(() {
      _polling = false;
      if (!_finished && !_pollScheduled) {
        _pollScheduled = true;
        _schedule(const Duration(seconds: 2), () {
          _pollScheduled = false;
          _poll();
        });
      }
    }).ignore();
  }

  Future<void> handle(DesktopAction event) => switch (event) {
    DesktopAction.open => showWindow(),
    DesktopAction.servers => showWindow(DesktopSection.servers),
    DesktopAction.settings => showWindow(DesktopSection.settings),
    DesktopAction.closeWindow => closeWindow(),
    DesktopAction.exit => exit(),
    DesktopAction.trayUnavailable => _trayFailed(),
    DesktopAction.trayAvailable => _trayRecovered(),
    DesktopAction.suspend => _power(true),
    DesktopAction.resume => _power(false),
  };

  void _retireWindow() {
    _epoch++;
    _views.add(view);
  }

  Future<void> _power(bool suspended) {
    if (_finished || _exiting) return Future.value();
    _powerRevision++;
    _resumeRequested = !suspended;
    engine.setSuspended(suspended);
    // Existing FoundationApp key disposes private models and starts a fresh
    // binding only when the controller permits it. Navigation alone survives.
    _retireWindow();
    if (_started) _poll();
    return Future.value();
  }

  Future<void> _trayRecovered() async {
    _trayRevision++;
    _tray = true;
    engine.setTrayAvailable(true);
  }

  Future<void> _trayFailed() async {
    _trayRevision++;
    _tray = false;
    engine.setTrayAvailable(false);
    await showWindow();
  }

  void rememberSection(DesktopSection section) {
    _section = section;
  }

  Future<void> showWindow([DesktopSection? section]) {
    _openRequests++;
    return _showWindow(section);
  }

  Future<void> _showWindow([DesktopSection? section]) {
    if (_finished) return Future.value();
    _desiredVisible = true;
    if (section != null) {
      _section = section;
      _navigationEpoch++;
    }
    _revision++;
    _publish(true);
    return _pumpWindow();
  }

  Future<void> closeWindow() {
    if (_finished) return Future.value();
    if (_exiting) return exit();
    if (_closingWindow != null) return _closingWindow!;
    final done = Completer<void>();
    _closingWindow = done.future;
    done.future.ignore();
    final opened = _openRequests;
    () async {
      await initialize();
      if (opened != _openRequests) return;
      if (_workspaceBusy) {
        await exit();
        return;
      }
      if (_tray) {
        _desiredVisible = false;
        _revision++;
        await _pumpWindow();
        if (opened != _openRequests || !_visible || _tray) return;
      }
      // A missing/recreated icon can never strand the last hidden window.
      await showWindow();
      if (await platform.fallbackClose()) await exit();
    }().then<void>(
      (_) {
        _closingWindow = null;
        done.complete();
      },
      onError: (Object _, StackTrace __) {
        _closingWindow = null;
        showWindow().ignore();
        done.complete();
      },
    );
    return done.future;
  }

  Future<void> _pumpWindow() {
    if (_windowWork != null) return _windowWork!;
    final done = Completer<void>();
    _windowWork = done.future;
    done.future.ignore();
    () async {
      var processed = -1;
      while (processed != _revision) {
        processed = _revision;
        if (_desiredVisible || !_tray || _exiting) {
          _publish(true);
          await platform.show();
        } else {
          final hidden = await platform.hide();
          if (!hidden) {
            _tray = false;
            engine.setTrayAvailable(false);
            _desiredVisible = true;
            _revision++;
            continue;
          }
          if (processed == _revision && !_desiredVisible && _tray)
            _publish(false);
        }
      }
    }().then<void>(
      (_) {
        _windowWork = null;
        done.complete();
      },
      onError: (Object _, StackTrace __) {
        _windowWork = null;
        _desiredVisible = true;
        _publish(true);
        platform.show().ignore();
        done.complete();
      },
    );
    return done.future;
  }

  Future<void> exit() {
    if (_finished) return Future.value();
    if (_exitWork != null) return _exitWork!;
    final done = Completer<void>();
    _exitWork = done.future;
    done.future.ignore();
    () async {
      if (!_exiting) {
        try {
          _status = await engine.refreshDesktopStatus();
        } catch (_) {
          _status = null;
        }
        await showWindow();
        if (!_workspaceBusy &&
            !await platform.confirmExit(_status?.unresolvedJobs))
          return;
        _exiting = true;
      }
      final result = await engine.shutdown();
      if (result == HostCloseResult.closed) {
        await _finish(false);
        return;
      }
      await showWindow();
      // Only explicit Wait can authorize the same timed-out cleanup to release.
      late BlockedChoice choice;
      _blockedPrompt = true;
      try {
        choice = await platform.blockedClose();
      } finally {
        _blockedPrompt = false;
      }
      if (_physicalClosed) {
        await _finish(false);
        return;
      }
      switch (choice) {
        case BlockedChoice.wait:
          _waiting ??= engine.waitForClose();
          _waiting!
              .then<void>(
                (result) async {
                  if (result == HostCloseResult.closed) {
                    _physicalClosed = true;
                    if (!_blockedPrompt) await _finish(false);
                  }
                },
                onError: (Object _, StackTrace __) {
                  showWindow().ignore();
                },
              )
              .ignore();
        case BlockedChoice.force:
          await _finish(true);
        case BlockedChoice.stay:
          break;
      }
    }().then<void>(
      (_) {
        _exitWork = null;
        done.complete();
      },
      onError: (Object _, StackTrace __) {
        _exitWork = null;
        showWindow().ignore();
        done.complete();
      },
    );
    return done.future;
  }

  Future<void> _finish(bool forced) {
    if (_finished) return Future.value();
    if (_finishing != null) return _finishing!;
    final done = Completer<void>();
    _finishing = done.future;
    done.future.ignore();
    () async {
      if (forced)
        await platform.forceExit();
      else
        await platform.finishExit();
      _finished = true;
      _events?.cancel().ignore();
    }().then<void>(
      done.complete,
      onError: (Object _, StackTrace __) {
        _finishing = null;
        done.completeError(StateError('SERVICE_UNAVAILABLE'));
      },
    );
    return done.future;
  }
}
