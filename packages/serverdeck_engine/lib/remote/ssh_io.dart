part of 'ssh_transport.dart';

/// Trusted provider dependency, never selected by profile/wire/role metadata.
abstract interface class SshIoFactory {
  SshIoAttempt start(
    SshEndpoint endpoint,
    SshCredential? credential, {
    required Duration deadline,
    required bool Function(SshHostPin observed) verifyHostPin,
  });
}

abstract interface class SshIoAttempt {
  Future<SshIoClient> get result;
  Future<void> get settled;
  void cancel();
}

// A failed settled/close or throwing cleanup means unconfirmed physical drain.
// The pool reports SERVICE_UNAVAILABLE, seals intake and retains that slot;
// cleanup attempts for all other owned resources still proceed. No failure is
// converted into a successful physical completion or a reusable pause handle.

abstract interface class SshIoClient {
  Future<void> get done;
  Future<SshIoSession> execute(SshIoCommand command);
  Future<void> close();
}

abstract interface class SshIoSession {
  Stream<Uint8List> get stdout;
  Stream<Uint8List> get stderr;
  StreamSink<Uint8List> get stdin;
  Future<void> get done;
  int? get exitCode;
  void close();
}

/// Only existing fixed read recipes or the fixed executor bridge. The provider
/// receives no caller-supplied command/script/path and grants no authority.
final class SshIoCommand {
  const SshIoCommand.read(SshReadRequest request) : read = request;
  const SshIoCommand.executor() : read = null;
  final SshReadRequest? read;
  bool get isExecutor => read == null;
  String get _command =>
      read?._command ?? 'sudo -n /usr/libexec/serverdeck-executor-bridge';
}
