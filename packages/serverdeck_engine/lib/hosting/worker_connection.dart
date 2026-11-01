import 'dart:async';
import 'dart:isolate';

import 'in_process_gateway.dart';
import 'worker_root.dart';
import 'worker_power.dart';

abstract interface class WorkerWindowLink {
  Object get replyAddress;
  GatewayChannel get channel;
  void workerLost();
}

/// One process-private worker incarnation. No recovery/replacement or kill API.
abstract interface class WorkerConnection {
  Stream<Object?> get messages;
  Future<void> start(int expiresAt);
  void send(Map<String, Object?> frame);
  WorkerWindowLink openWindow(Capability binding);
  void acknowledgeClosed(int sequence);
}

final class _DartWindowLink implements WorkerWindowLink {
  _DartWindowLink(SendPort mailbox, Capability binding) {
    final replies = ReceivePort();
    replyAddress = replies.sendPort;
    channel = DartGatewayChannel(
      mailbox: mailbox,
      binding: binding,
      replies: replies,
    );
  }
  @override
  late final SendPort replyAddress;
  @override
  late final DartGatewayChannel channel;
  @override
  void workerLost() => channel.workerLost();
}

/// Concrete VM adapter. All listeners precede spawn; queued controls are bounded
/// and retained until the one mailbox arrives. Exit/error alone never means Closed.
final class DartWorkerConnection implements WorkerConnection {
  DartWorkerConnection(this._entry);
  final void Function(EngineWorkerBoot) _entry;
  final _control = Capability();
  final _messages = StreamController<Object?>(sync: true);
  final _queued = WorkerStartupQueue();
  final _links = <_DartWindowLink>{};
  ReceivePort? _replies, _errors, _exits;
  SendPort? _mailbox;
  Future<void>? _starting;
  bool _lost = false, _expectedExit = false;
  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  Future<void> start(int expiresAt) {
    if (_starting != null) return _starting!;
    final done = Completer<void>();
    _starting = done.future;
    done.future.ignore();
    _replies = ReceivePort()..listen(_receive);
    _errors = ReceivePort()..listen((_) => _lose());
    _exits = ReceivePort()
      ..listen((_) {
        if (!_expectedExit) {
          _lose();
          return;
        }
        _disposePorts();
        _messages.close().ignore();
      });
    Isolate.spawn<EngineWorkerBoot>(
      _entry,
      EngineWorkerBoot(_control, _replies!.sendPort, expiresAt),
      onError: _errors!.sendPort,
      onExit: _exits!.sendPort,
      errorsAreFatal: true,
      debugName: 'serverdeck-engine',
    ).then<void>(
      (_) => done.complete(),
      onError: (Object _, StackTrace __) {
        _lose();
        done.completeError(EngineCallFailure('SERVICE_UNAVAILABLE'));
      },
    );
    return done.future;
  }

  void _receive(Object? value) {
    if (_lost) {
      discardWorkerFrame(value);
      return;
    }
    if (value is Map<String, Object?> && value['kind'] == 'mailbox') {
      if (_mailbox != null ||
          value.length != 2 ||
          value['mailbox'] is! SendPort) {
        _lose();
        return;
      }
      _mailbox = value['mailbox'] as SendPort;
      final queued = _queued.takeForStart();
      for (final frame in queued) {
        if (_lost) break;
        try {
          _mailbox!.send([_control, frame]);
        } catch (_) {
          _lose();
        }
      }
      return;
    }
    if (_mailbox == null) {
      _lose();
      return;
    }
    _messages.add(value);
  }

  @override
  void send(Map<String, Object?> frame) {
    if (_lost || _expectedExit) throw EngineCallFailure('SERVICE_UNAVAILABLE');
    if (_mailbox == null) {
      _queued.add(frame);
      return;
    }
    try {
      _mailbox!.send([_control, frame]);
    } catch (_) {
      _lose();
      throw EngineCallFailure('SERVICE_UNAVAILABLE');
    }
  }

  @override
  WorkerWindowLink openWindow(Capability binding) {
    if (_lost || _expectedExit || _mailbox == null)
      throw EngineCallFailure('SERVICE_UNAVAILABLE');
    // Closed links carry no native authority; prune before creating another.
    _links.removeWhere((link) => link.channel.isDisposed);
    if (_links.length >= 8) throw EngineCallFailure('RESOURCE_LIMIT');
    final link = _DartWindowLink(_mailbox!, binding);
    _links.add(link);
    return link;
  }

  @override
  void acknowledgeClosed(int sequence) {
    if (_lost || _expectedExit || _mailbox == null)
      throw EngineCallFailure('SERVICE_UNAVAILABLE');
    _expectedExit = true; // Before worker can exit on the other port.
    try {
      _mailbox!.send([
        _control,
        {'kind': 'ackClosed', 'sequence': sequence},
      ]);
    } catch (_) {
      _expectedExit = false;
      _lose();
    }
  }

  void _lose() {
    if (_lost) return;
    _lost = true;
    _queued.clear();
    for (final link in _links) {
      link.workerLost();
    }
    _messages.addError(EngineCallFailure('SERVICE_UNAVAILABLE'));
    // No Isolate.kill: native ownership may outlive observation/error delivery.
    _disposePorts();
    _messages.close().ignore();
  }

  void _disposePorts() {
    _replies?.close();
    _errors?.close();
    _exits?.close();
  }
}
