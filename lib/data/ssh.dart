import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../domain/models.dart';
import 'credentials.dart';
import 'read_adapters.dart';

final class EnrolledIdentity {
  EnrolledIdentity({
    required this.endpoint,
    required this.port,
    required this.keyType,
    required this.fingerprint,
  }) {
    if (!RegExp(r'^SHA256:[a-zA-Z0-9+/]{43}$').hasMatch(fingerprint) ||
        keyType.isEmpty ||
        port < 1 ||
        port > 65535) {
      throw ArgumentError('Explicit enrolled host identity required');
    }
  }
  final String endpoint, keyType, fingerprint;
  final int port;
  bool accepts(String type, Uint8List presented) =>
      type == keyType &&
      utf8.decode(presented, allowMalformed: true) == fingerprint;
}

class ReadCommandResult {
  const ReadCommandResult(this.stdout, this.stderr, this.exitCode);
  final String stdout, stderr;
  final int? exitCode;
  bool get succeeded => exitCode == 0;
  ReadFailure? get failure =>
      succeeded ? null : classifyReadFailure(exitCode ?? 255, stderr);
}

class ReadBudgetExceeded implements Exception {
  @override
  String toString() => 'Read output exceeded bounded budget';
}

/// Initial read-only transport. No shell/SFTP/write/session API is exposed.
/// Not connected by the fixture UI; explicit enrollment flow is still required.
class HostIdentityRejected implements Exception {
  @override
  String toString() => 'Host identity mismatch; connection denied';
}

final class SshReadClient {
  SshReadClient._(this._client);
  final SSHClient _client;
  bool _busy = false;
  static Future<SshReadClient> connect({
    required ServerProfile profile,
    required EnrolledIdentity identity,
    required String credentialReference,
    required CredentialStore credentials,
  }) async {
    if (profile.endpoint != identity.endpoint ||
        profile.port != identity.port) {
      throw ArgumentError('Host enrollment does not match endpoint');
    }
    final credential = await credentials.read(credentialReference);
    if (credential == null) {
      throw StateError('Credential unavailable in OS custody');
    }
    List<SSHKeyPair>? identities;
    if (credential.kind == 'key') {
      try {
        identities = SSHKeyPair.fromPem(
          credential.material,
          credential.passphrase,
        );
      } catch (_) {
        throw StateError('Protected SSH key could not be decoded');
      }
    }
    final socket = await SSHSocket.connect(
      profile.endpoint,
      profile.port,
      timeout: const Duration(seconds: 10),
    );
    SSHClient? client;
    var identityRejected = false;
    try {
      client = SSHClient(
        socket,
        username: profile.user,
        identities: identities,
        onPasswordRequest: credential.kind == 'password'
            ? () => credential.material
            : null,
        onVerifyHostKey: (type, fingerprint) {
          final accepted = identity.accepts(type, fingerprint);
          identityRejected = !accepted;
          return accepted;
        },
        handshakeTimeout: const Duration(seconds: 15),
        authTimeout: const Duration(seconds: 15),
      );
      await client.authenticated;
      return SshReadClient._(client);
    } catch (_) {
      if (client != null) {
        await client.close();
      } else {
        socket.destroy();
      }
      if (identityRejected) {
        throw HostIdentityRejected();
      }
      rethrow;
    }
  }

  Future<ReadCommandResult> execute(
    ReadOperation operation, {
    int maxBytes = 4 * 1024 * 1024,
    Duration deadline = const Duration(seconds: 30),
  }) async {
    if (_busy) {
      throw StateError('Read channel busy');
    }
    if (maxBytes < 1 ||
        maxBytes > 4 * 1024 * 1024 ||
        deadline <= Duration.zero ||
        deadline > const Duration(seconds: 30)) {
      throw ArgumentError('Read budget exceeds policy');
    }
    // Live follow has a different bounded streaming contract, not this snapshot API.
    if (operation.command.endsWith(' --follow')) {
      throw ArgumentError('Use bounded stream adapter for follow');
    }
    _busy = true;
    SSHSession? session;
    var bytes = 0;
    Future<String> consume(Stream<Uint8List> stream) async {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        bytes += chunk.length;
        if (bytes > maxBytes) {
          throw ReadBudgetExceeded();
        }
        builder.add(chunk);
      }
      return utf8.decode(builder.takeBytes());
    }

    Future<ReadCommandResult> run() async {
      session = await _client.execute(operation.command);
      await session!.stdin.close();
      final output = await Future.wait([
        consume(session!.stdout),
        consume(session!.stderr),
      ], eagerError: true);
      await session!.done;
      return ReadCommandResult(output[0], output[1], session!.exitCode);
    }

    try {
      return await run().timeout(deadline);
    } catch (_) {
      session?.close();
      await _client.close();
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> close() => _client.close();
}
