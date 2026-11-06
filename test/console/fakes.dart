import 'dart:async';
import 'dart:typed_data';

import 'package:serverdeck/console/console_port.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/runtime/owned_work.dart';

final class FakeConsolePort implements ConsoleConnectionPort {
  FakeConsolePort(this.versions);
  final EntityVersions? Function(String) versions;
  final events = StreamController<ConsoleInvalidation>.broadcast(sync: true);
  final openings = <FakeConsoleOpening>[];
  bool connected = true;
  bool autoOpen = true;
  @override
  Stream<ConsoleInvalidation> get consoleInvalidations => events.stream;
  @override
  ConnectionView connection(String profileId) => ConnectionView(
    state: connected ? ConnectionState.connected : ConnectionState.disconnected,
    sessionId: connected ? '00000001-0000-4000-8000-000000000000' : null,
  );
  @override
  ConsoleConnectionBinding bindConsole(Actor actor, String id) {
    final v = versions(id)!;
    void check() {
      if (!connected) throw const OperationFailure(FailureCode.conflict);
    }

    check();
    return ConsoleConnectionBinding(
      profileId: id,
      connectionRevision: v.connectionRevision,
      sshSessionId: connection(id).sessionId!,
      fence: VersionFence(
        profileId: id,
        connectionRevision: v.connectionRevision,
      ),
      check: check,
      open: ({String? path, required onData, required guard}) {
        guard();
        final result = FakeConsoleOpening(
          FakeConsoleChannel(onData, guard),
          path,
        );
        openings.add(result);
        if (autoOpen) result.complete();
        return result;
      },
    );
  }
}

final class FakeConsoleOpening implements ConsoleOpening {
  FakeConsoleOpening(this.channel, this.path);
  final FakeConsoleChannel channel;
  final String? path;
  final ready = Completer<ConsoleChannel>();
  bool cancelled = false;
  void complete() {
    if (!ready.isCompleted) ready.complete(channel);
  }

  @override
  Future<ConsoleChannel> get opened => ready.future;
  @override
  void cancel() {
    cancelled = true;
    channel.abort();
    if (!ready.isCompleted) ready.completeError(const WorkCancelled());
  }
}

final class FakeConsoleChannel implements ConsoleChannel {
  FakeConsoleChannel(this.output, this.bindingGuard);
  final void Function(Uint8List) output;
  final void Function() bindingGuard;
  final ended = Completer<void>();
  final writes = <Uint8List>[];
  Completer<void>? hold;
  ConsoleWriteOutcome? outcome;
  bool closed = false;
  @override
  int? exitCode;
  @override
  String? failure;
  void emit(List<int> data) => output(Uint8List.fromList(data));
  void end([int? code = 0]) {
    exitCode = code;
    closed = true;
    if (!ended.isCompleted) ended.complete();
  }

  @override
  Future<void> get done => ended.future;
  @override
  void abort() {
    closed = true;
    if (!ended.isCompleted) ended.complete();
  }

  @override
  Future<ConsoleWriteOutcome> write(
    Uint8List bytes, {
    required void Function() guard,
    required WorkCancellation cancellation,
  }) async {
    await hold?.future;
    cancellation.check();
    bindingGuard();
    guard();
    if (closed) throw const WorkCancelled();
    writes.add(Uint8List.fromList(bytes));
    return outcome ?? ConsoleWriteOutcome(bytes.length, 'complete');
  }

  @override
  Future<void> resize(int columns, int rows, void Function() guard) async {
    bindingGuard();
    guard();
  }
}
