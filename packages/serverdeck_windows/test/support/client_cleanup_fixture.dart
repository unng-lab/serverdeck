import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';

void check(bool value) {
  if (!value) throw StateError('CLEANUP_FIXTURE_FAILED');
}

/// Only a test fault after genuine physical cleanup. Native proof and all IO
/// still come from the actual worker; this does not qualify a native API failure.
final class FailureAfterClose implements PipeWorker {
  FailureAfterClose(this.actual);
  final PipeWorker actual;
  Future<void>? _close;
  @override
  Future<OperationalPipePeer> verifyOperationalPeer() =>
      actual.verifyOperationalPeer();
  @override
  Future<TrustedPipePeer> verifyTrustedPeer() => actual.verifyTrustedPeer();
  @override
  Future<void> close() => _close ??= () async {
    await actual.close();
    throw StateError('SYNTHETIC_CLEANUP_FAILURE');
  }();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('UNUSED_FIXTURE_METHOD');
}

Future<void> run(List<String> args, String generation, List<int> token) async {
  final trusted = args[3] == 'cleanup3';
  final root = args[1], name = args[2];
  if (args[0] == 'client') {
    final worker = trusted
        ? await PipeWorker.openTrustedClient(name, currentUserSid(), root)
        : await PipeWorker.openOperationalClient(name, currentUserSid(), root);
    try {
      final bound = FailureAfterClose(worker);
      // Dynamic is confined to this two-version test driver. Actual bootstrap
      // factories still require their own native peer and mint distinct types.
      final dynamic rpc = trusted
          ? TrustedApiClient(
              await TrustedBootstrapClient(
                pipe: bound,
                generation: generation,
                token: token,
              ).authenticate(),
            )
          : OperationalApiClient(
              await OperationalBootstrapClient(
                pipe: bound,
                generation: generation,
                token: token,
              ).authenticate(),
            );
      Object? first;
      for (var n = 0; n < 3; n++) {
        try {
          await (n == 1 ? rpc.done : rpc.close());
          throw StateError('EXPECTED_CLEANUP_FAILURE');
        } catch (error) {
          if (trusted) {
            check(
              error is TrustedRpcException &&
                  error.code == 'SERVICE_UNAVAILABLE' &&
                  error.terminal &&
                  error.origin == OperationalRpcFailureOrigin.transport,
            );
          } else {
            check(
              error is OperationalRpcException &&
                  error.code == ErrorCode.serviceUnavailable &&
                  error.terminal &&
                  error.origin == OperationalRpcFailureOrigin.transport,
            );
          }
          if (first != null) check(identical(first, error));
          first = error;
        }
      }
      check(rpc.isClosed == true && rpc.pendingRequests == 0);
      stdout.writeln('CLIENT_PASS');
    } finally {
      await worker.close();
    }
    return;
  }
  final worker = trusted
      ? await PipeWorker.createTrustedServer(name, currentUserSid(), root)
      : await PipeWorker.createOperationalServer(name, currentUserSid(), root);
  Process? child;
  try {
    final accepted = worker.accept(deadline: const Duration(seconds: 5));
    accepted.ignore();
    child = await Process.start(p.join(root, 'serverdeck.exe'), [
      'client',
      root,
      name,
      args[3],
    ]);
    final output = child.stdout.transform(utf8.decoder).join();
    final errors = child.stderr.transform(utf8.decoder).join();
    await accepted;
    final dynamic peer = trusted
        ? await worker.verifyTrustedPeer()
        : await worker.verifyOperationalPeer();
    final dynamic io = trusted
        ? TrustedHandshakeIo(peer as TrustedPipePeer)
        : OperationalHandshakeIo(peer as OperationalPipePeer);
    Duration remaining() => const Duration(seconds: 5);
    String mac(List<int> bytes) {
      final key = SecretKeyData(List.of(token), overwriteWhenDestroyed: true);
      try {
        return base64Url
            .encode(
              DartHmac.sha256()
                  .calculateMacSync(bytes, secretKeyData: key, nonce: const [])
                  .bytes,
            )
            .replaceAll('=', '');
      } finally {
        key.destroy();
      }
    }

    String nonce(int n) =>
        base64Url.encode(List.filled(32, n)).replaceAll('=', '');
    final hello = OperationalHello(
      generation: generation,
      serverNonce: nonce(1),
      buildId: peer.buildId as String,
      clientRole: OperationalRole.owner,
    );
    await io.write(hello.toJson(), remaining);
    final auth = OperationalAuthenticate.decode(await io.read(remaining));
    final transcript = OperationalBootstrapTranscript(
      hello: hello,
      clientNonce: auth.clientNonce,
      requestedCapabilities: auth.requestedCapabilities,
    );
    check(auth.proof == mac(transcript.clientBytes()));
    final unsigned = OperationalAuthenticated(
      sessionId: nonce(2),
      clientRole: OperationalRole.owner,
      capabilities: ['owner'],
      proof: nonce(3),
    );
    await io.write(
      OperationalAuthenticated(
        sessionId: unsigned.sessionId,
        clientRole: unsigned.clientRole,
        capabilities: unsigned.capabilities,
        proof: mac(transcript.serverBytes(unsigned)),
      ).toJson(),
      remaining,
    );
    final code = await child.exitCode.timeout(const Duration(seconds: 10));
    final out = await output, err = await errors;
    if (code != 0 || !out.contains('CLIENT_PASS') || err.isNotEmpty) {
      stderr.write(err);
      throw StateError('CLEANUP_CHILD_FAILED');
    }
  } finally {
    if (child != null) {
      try {
        await child.stdin.close();
      } on IOException {
        /* Owned child exited. */
      }
      child.kill();
      await child.exitCode.timeout(const Duration(seconds: 5));
    }
    await worker.close();
  }
}
