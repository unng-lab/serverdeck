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
  const SshIoCommand.read(SshReadRequest request)
    : read = request,
      operation = null;
  const SshIoCommand.executor() : read = null, operation = null;
  const SshIoCommand.direct(DirectSshCommand command)
    : read = null,
      operation = command;
  final SshReadRequest? read;
  final DirectSshCommand? operation;
  bool get isExecutor => read == null && operation == null;
  String get _command =>
      read?._command ??
      (operation == null
          ? 'sudo -n /usr/libexec/serverdeck-executor-bridge'
          : _directBootstrap);

  // Drain the bounded compiler input before a prerequisite refusal. An early
  // remote exit must not race stdin transmission and obscure the safe frame.
  static const _directBootstrap = r'''/bin/sh -c '
if [ ! -x /usr/bin/cat ]; then
  while IFS= read -r discard || [ -n "$discard" ]; do :; done
  printf "SDSSH_ERROR\tPREREQUISITE_UNAVAILABLE\n"
  exit 127
fi
payload=$(/usr/bin/cat) || exit 255
if [ ! -x /usr/bin/id ]; then
  printf "SDSSH_ERROR\tPREREQUISITE_UNAVAILABLE\n"
  exit 127
fi
uid=$(/usr/bin/id -u) || exit 255
case "$uid" in ""|*[!0-9]*) exit 255;; esac
if [ "$uid" = 0 ]; then
  printf "%s\n" "$payload" | /bin/sh -s
elif [ ! -x /usr/bin/sudo ]; then
  printf "SDSSH_ERROR\tPREREQUISITE_UNAVAILABLE\n"
  exit 127
else
  printf "%s\n" "$payload" | /usr/bin/sudo -n -- /bin/sh -s
fi
' ''';
}
