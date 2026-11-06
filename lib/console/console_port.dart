import 'dart:typed_data';

import '../domain/actor.dart';
import '../domain/app_operations.dart';
import '../domain/models.dart';
import '../runtime/owned_work.dart';

final class ConsoleInvalidation {
  const ConsoleInvalidation(this.profileId, {required this.clear});
  final String profileId;
  final bool clear;
}

abstract interface class ConsoleConnectionPort {
  Stream<ConsoleInvalidation> get consoleInvalidations;
  ConnectionView connection(String profileId);
  ConsoleConnectionBinding bindConsole(Actor actor, String profileId);
}

final class ConsoleConnectionBinding {
  const ConsoleConnectionBinding({
    required this.profileId,
    required this.connectionRevision,
    required this.sshSessionId,
    required this.fence,
    required this.check,
    required this.open,
  });
  final String profileId, sshSessionId;
  final int connectionRevision;
  final VersionFence fence;
  final void Function() check;
  final ConsoleOpening Function({
    String? path,
    required void Function(Uint8List) onData,
    required void Function() guard,
  })
  open;
}

abstract interface class ConsoleOpening {
  Future<ConsoleChannel> get opened;
  void cancel();
}

enum ConsoleOpenFailureCode {
  ptyDenied,
  shellDenied,
  timeout,
  cleanupRequired,
  unsupportedServer,
  networkError,
  cancelled,
}

final class ConsoleOpenFailure implements Exception {
  const ConsoleOpenFailure(this.code);
  final ConsoleOpenFailureCode code;
  @override
  String toString() => 'ConsoleOpenFailure(${code.name})';
}

final class ConsoleWriteOutcome {
  const ConsoleWriteOutcome(this.acceptedBytes, this.status);
  final int acceptedBytes;
  final String status;
}

abstract interface class ConsoleChannel {
  Future<void> get done;
  int? get exitCode;
  String? get failure;
  void abort();
  Future<ConsoleWriteOutcome> write(
    Uint8List bytes, {
    required void Function() guard,
    required WorkCancellation cancellation,
  });
  Future<void> resize(int columns, int rows, void Function() guard);
}

abstract interface class ConsoleSshConnection {
  ConsoleOpening openConsole({
    String? path,
    required void Function(Uint8List) onData,
    required void Function() guard,
  });
}
