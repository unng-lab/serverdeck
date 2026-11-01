import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/credentials/discovery_custody.dart';
import 'package:serverdeck_engine/credentials/mcp_credential_files.dart';
import 'package:serverdeck_engine/credentials/mcp_credentials.dart';
import 'package:serverdeck_engine/mcp/client.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_engine/platform/vm_clock.dart';
import 'package:serverdeck_protocol/discovery.dart';

import 'embedded_build_bundle.dart';
import 'embedded_pipe.dart';
import 'engine_platform.dart';
import 'paths.dart';
import 'security.dart';

/// One connection-only stdio incarnation of the actual serverdeck.exe. Own this
/// object before calling connect: failed/late native attempts stay owned too.
/// There is no app-root input, launch, writer mutex, Isar or domain Host here.
final class WindowsMcpConnector {
  final EngineClock _clock = VmEngineClock();
  EmbeddedBuildBundle? _bundle;
  RetainedProcessIdentity? _identity;
  VerifiedApplicationPeer? _self;
  WindowsProtectedFiles? _files;
  SecureVault? _vault;
  DiscoveryDescriptor? _descriptor;
  EmbeddedPipeChannel? _channel;
  McpClient? _client;
  PublicationGate? _gate;
  Future<McpClient>? _connecting;
  Future<void>? _connectPhysical, _closing;
  Future<PublicationGate>? _gateCreating;
  bool _closed = false, _unsafeClose = false, _gateCreationFailed = false;
  bool _identityCreationFailed = false;
  late Duration _until;
  String? _sid;

  void _current() {
    if (_closed) throw StateError('SERVICE_UNAVAILABLE');
    if (_self != null) {
      _self!.requireCurrentProcess(_bundle!);
      if (currentUserSid() != _sid) throw StateError('UNAUTHORIZED');
    }
  }

  Duration _remaining() {
    _current();
    final left = _until - _clock.elapsed;
    if (left <= Duration.zero) throw StateError('TIMEOUT');
    return left;
  }

  static StateError _safe(Object e) => StateError(
    e is StateError &&
            const {
              'TIMEOUT',
              'UNAUTHORIZED',
              'INCOMPATIBLE',
              'STORAGE_BLOCKED',
              'SERVICE_UNAVAILABLE',
              'PREREQUISITE_UNAVAILABLE',
              'RESOURCE_LIMIT',
            }.contains(e.message)
        ? e.message
        : e is FileSystemException
        ? 'STORAGE_BLOCKED'
        : 'SERVICE_UNAVAILABLE',
  );

  Future<McpClient> connect() {
    if (_connecting != null || _closed)
      return Future.error(StateError('SERVICE_UNAVAILABLE'));
    final reply = Completer<McpClient>(), physical = Completer<void>();
    _connecting = reply.future;
    _connectPhysical = physical.future;
    reply.future.ignore();
    _until = _clock.elapsed + const Duration(seconds: 5);
    final actual = Future<McpClient>.sync(_connect);
    actual.then<void>(
      (_) => physical.complete(),
      onError: (Object e, StackTrace _) {
        if (e is FileSystemException &&
                e.message == 'PHYSICAL_CLOSE_UNCONFIRMED' ||
            e is RemoteError)
          _unsafeClose = true;
        physical.complete();
      },
    );
    Duration left;
    try {
      left = _remaining();
    } catch (e) {
      close().ignore();
      reply.completeError(_safe(e));
      return reply.future;
    }
    actual
        .timeout(left)
        .then<void>(
          (client) {
            if (_closed) {
              reply.completeError(StateError('SERVICE_UNAVAILABLE'));
              return;
            }
            reply.complete(client);
          },
          onError: (Object e, StackTrace _) {
            close().ignore();
            reply.completeError(
              e is TimeoutException
                  ? StateError(
                      _client == null ? 'SERVICE_UNAVAILABLE' : 'TIMEOUT',
                    )
                  : _safe(e),
            );
          },
        );
    return reply.future;
  }

  Future<McpClient> _connect() async {
    _remaining();
    if (!Platform.isWindows) throw StateError('PREREQUISITE_UNAVAILABLE');
    final root = p.dirname(Platform.resolvedExecutable);
    _bundle = await verifyEmbeddedBuildBundle(root);
    _remaining();
    if (_bundle!.manifest.testOnly) throw StateError('UNAUTHORIZED');
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || !p.isAbsolute(local))
      throw StateError('PREREQUISITE_UNAVAILABLE');
    requireSafePath(local, local);
    _sid = currentUserSid();
    try {
      _identity = RetainedProcessIdentity.open(pid);
    } catch (_) {
      // A failed factory does not give this owner a retained object with which
      // to prove partial handle cleanup. Never report a clean connector close.
      _identityCreationFailed = true;
      rethrow;
    }
    _self = _bundle!.verifyPeer(_identity!, _sid!);
    _current();
    _files = WindowsProtectedFiles(
      root: local,
      ownerIdentity: _sid!,
      onUnconfirmedClose: () {
        _unsafeClose = true;
      },
    );
    _vault = createWindowsVault(ownerIdentity: _sid!);
    final directory = p.join(local, 'ServerDeckNext', 'v1', 'runtime');
    final path = p.join(directory, DiscoveryNamespace.fileName);
    final directoryKind = _files!.kind(directory);
    if (directoryKind == ProtectedPathKind.absent)
      throw StateError('SERVICE_UNAVAILABLE');
    if (directoryKind != ProtectedPathKind.directory)
      throw StateError('STORAGE_BLOCKED');
    _files!.requireOwnerOnly(directory);
    final fileKind = _files!.kind(path);
    if (fileKind == ProtectedPathKind.absent)
      throw StateError('SERVICE_UNAVAILABLE');
    if (fileKind != ProtectedPathKind.file) throw StateError('STORAGE_BLOCKED');
    final wrapped = await readProtectedFile(
      local,
      path,
      _sid!,
      maxBytes: 16384,
    );
    try {
      _remaining();
      _descriptor = await DiscoveryCustody(
        _vault!,
        _sid!,
      ).unprotect(wrapped, _bundle!.buildId);
    } finally {
      wrapped.fillRange(0, wrapped.length, 0);
    }
    _remaining();
    for (final name in _descriptor!.pipeNames) {
      _remaining();
      final channel = _channel = EmbeddedPipeChannel.connecting(
        name,
        serverPid: _descriptor!.serverPid,
      );
      try {
        await channel.ready;
        _remaining();
        break;
      } catch (e) {
        // Retain the failed attempt until physical close, including failure.
        await channel.disconnect();
        _channel = null;
        _remaining();
        if (e is! StateError || e.message != 'SERVICE_UNAVAILABLE') rethrow;
      }
    }
    if (_channel == null) throw StateError('SERVICE_UNAVAILABLE');
    _client = McpClient(
      peer: _channel!,
      descriptor: _descriptor!,
      clock: _clock,
      bootstrapBudget: _remaining(),
    );
    _descriptor!.close(); // Client owns its independent bootstrap-token copy.
    await _client!.authenticate();
    _remaining();
    return _client!;
  }

  McpCredentialFiles credentials() {
    _current();
    if (_client == null || _client!.isClosed)
      throw StateError('SERVICE_UNAVAILABLE');
    return McpCredentialFiles(
      localAppData: _files!.root,
      protectedFiles: _files!,
      workspaceId: _client!.workspaceId,
      ownerSid: _sid!,
      custody: McpCredentialCustody(_vault!),
    );
  }

  Future<PublicationGate> publicationGate() {
    if (_gateCreating != null) return _gateCreating!;
    _current();
    if (_client == null || _client!.isClosed)
      return Future.error(StateError('SERVICE_UNAVAILABLE'));
    final done = Completer<PublicationGate>();
    _gateCreating = done.future;
    done.future.ignore();
    Future<PublicationGate>.sync(() async {
      _gate = await _channel!.publicationGate(_client!.generation);
      _current();
      if (_client!.isClosed || _gate!.isClosed)
        throw StateError('SERVICE_UNAVAILABLE');
      return _gate!;
    }).then<void>(
      done.complete,
      onError: (Object e, StackTrace _) {
        _gateCreationFailed = true;
        done.completeError(_safe(e));
      },
    );
    return done.future;
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    final done = Completer<void>();
    _closing = done.future;
    done.future.ignore();
    _closed = true;
    // Interrupt a pending connect/read before waiting on its physical future.
    final early = _client?.close() ?? _channel?.disconnect();
    early?.ignore();
    () async {
      var clean = true;
      try {
        await early;
      } catch (_) {
        clean = false;
      }
      await _connectPhysical;
      try {
        await _gateCreating;
      } catch (_) {
        clean = false;
      }
      for (final closer in <Future<void> Function()>[
        () async {
          await _client?.close();
        },
        () async {
          await _channel?.disconnect();
        },
        () async {
          await _gate?.close();
        },
        () async {
          await _vault?.dispose();
        },
      ]) {
        try {
          await closer();
        } catch (_) {
          clean = false;
        }
      }
      _descriptor?.close();
      try {
        if (_identity != null && !_identity!.close()) clean = false;
      } catch (_) {
        clean = false;
      }
      if (!clean ||
          _unsafeClose ||
          _gateCreationFailed ||
          _identityCreationFailed)
        throw StateError('SERVICE_UNAVAILABLE');
    }().then<void>(
      done.complete,
      onError: (Object _, StackTrace __) =>
          done.completeError(StateError('SERVICE_UNAVAILABLE')),
    );
    return done.future;
  }
}
