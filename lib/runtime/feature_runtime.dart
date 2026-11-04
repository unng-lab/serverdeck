import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../connections/connection_owner.dart';
import '../journals/journal_owner.dart';
import '../connections/host_signature.dart';
import '../connections/private_signer.dart';
import '../domain/actor.dart';
import '../domain/app_operations.dart';
import '../domain/canonical_state.dart';
import '../domain/mutation_receipts.dart';
import '../domain/owned_app_operations.dart';
import '../domain/receipt_book.dart';
import '../mcp/grant_owner.dart';
import '../mcp/pipe_adapter.dart';
import '../mcp/router.dart';
import '../mcp/tool_schemas.dart';
import '../profiles/credential_input.dart';
import '../profiles/key_parse_worker.dart';
import '../profiles/profile_owner.dart';
import '../storage/domain_repository.dart';
import '../trust/trust_owner.dart';
import '../monitoring/monitoring_owner.dart';
import 'capability.dart';
import 'native_platform.dart';
import 'local_diagnostics.dart';

final class _Protector implements SecretProtector {
  const _Protector(this.platform);
  final NativePlatform platform;
  @override
  Future<Uint8List> protect(Uint8List bytes, String purpose) =>
      platform.protect(bytes, purpose);
}

/// Complete owner graph, built before RuntimeCoordinator admits any operations.
final class FeatureRuntime implements RuntimeCapability {
  FeatureRuntime({
    required this.platform,
    required this.repository,
    required this.signer,
    required this.isRunning,
    this.monitoringAutoAllowed = false,
  }) {
    actors = ActorAuthority(platform.epoch);
    parser = CancellableKeyParser();
    verifier = HostSignatureVerifier();
    privateSigner = PrivateSigner();
    pipe = McpPipeAdapter(
      port: NativeMcpPipePort(platform),
      ownerEpoch: platform.epoch,
      getGrants: () => grants,
      getRouter: () => router,
      utcNow: utcNow,
      onUnavailable: () =>
          mcpError = 'Канал MCP недоступен. Повторите его запуск в настройках.',
    );
    connections = ConnectionOwner(
      actors: actors,
      repository: repository,
      getGate: () => gate,
      getState: () => state,
      getTrust: () => trust,
      unprotect: platform.unprotect,
      verifier: verifier,
      signer: privateSigner,
      newId: newId,
      utcNow: utcNow,
    );
    grants = GrantOwner(
      repository: repository,
      actors: actors,
      getGate: () => gate,
      connections: connections,
      transport: pipe,
      protect: platform.protect,
      unprotect: platform.unprotect,
      newId: newId,
      utcNow: utcNow,
      userSid: platform.context.userSid,
      logonSid: platform.context.logonSid,
      exePath: platform.context.exePath,
    );
    state = CanonicalOperationState(
      actors: actors,
      repository: repository,
      isRunning: () => !_stopped && isRunning(),
      grants: grants,
      connections: connections,
    );
    final diagnostics = LocalDiagnostics(platform.context.dataRoot);
    gate = DomainCommandGate(
      actors: actors,
      state: state,
      onFailure: (error, stack) => diagnostics.record('command', error, stack),
    );
    final receipts = ReceiptBook(signer, utcNow);
    trust = TrustOwner(
      repository: repository,
      getGate: () => gate,
      connections: connections,
      receipts: receipts,
      newId: newId,
      utcNow: utcNow,
    );
    profiles = ProfileOwner(
      onFailure: (error, stack) => diagnostics.record('profile', error, stack),
      gate: gate,
      repository: repository,
      receipts: receipts,
      credentials: CredentialPreparer(_Protector(platform), parser),
      connections: connections,
      newId: newId,
      utcNow: utcNow,
    );
    operations = OwnedAppOperations(profiles, connections, trust);
    monitoring = MonitoringOwner(
      historyStore: repository,
      operations: operations,
      actor: actors.ui,
      connections: connections,
      startupAutoAllowed: monitoringAutoAllowed,
      utcNow: utcNow,
    );
    journals = JournalsOwner(
      repository: repository,
      actor: actors.ui,
      connections: connections,
      newId: newId,
      utcNow: utcNow,
    );
    _capabilities = [
      journals,
      monitoring,
      pipe,
      grants,
      profiles,
      trust,
      connections,
      parser,
      verifier,
      privateSigner,
    ];
  }
  final NativePlatform platform;
  final DomainRepository repository;
  final ReceiptSigner signer;
  final bool Function() isRunning;
  final bool monitoringAutoAllowed;
  late final ActorAuthority actors;
  late final CanonicalOperationState state;
  late final DomainCommandGate gate;
  late final CancellableKeyParser parser;
  late final HostSignatureVerifier verifier;
  late final PrivateSigner privateSigner;
  late final ConnectionOwner connections;
  late final ProfileOwner profiles;
  late final TrustOwner trust;
  late final GrantOwner grants;
  late final McpPipeAdapter pipe;
  late final OwnedAppOperations operations;
  late final MonitoringOwner monitoring;
  late final JournalsOwner journals;
  late McpRouter router;
  late final List<RuntimeCapability> _capabilities;
  bool _stopped = false, _initialized = false;
  String? mcpError;
  @override
  String get id => 'feature-003';
  static int utcNow() => DateTime.now().toUtc().millisecondsSinceEpoch;
  static String newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final text = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
  }

  Future<void> initialize() async {
    if (_initialized || _stopped) return;
    await journals.start();
    try {
      router = McpRouter(
        operations: operations,
        grants: grants,
        schemas: await ToolSchemas.load(),
        release: platform.context.release,
      );
      if (_stopped) return;
      await pipe.initialize();
      if (_stopped) return;
      await grants.initialize();
      if (_stopped) return;
      await pipe.setEnabled(grants.enabled);
      mcpError = null;
    } catch (_) {
      mcpError = 'MCP недоступен. Профили и SSH продолжают работать.';
      grants.transportReady(false);
      try {
        await pipe.setEnabled(false);
      } catch (_) {}
    }
    _initialized = true;
  }

  Future<void> retryMcp() async {
    if (_stopped) return;
    try {
      await pipe.setEnabled(false);
    } catch (_) {
      mcpError = 'Не удалось закрыть прежние каналы MCP. Повторите закрытие.';
      return;
    }
    _initialized = false;
    await initialize();
  }

  Future<void> _each(Future<void> Function(RuntimeCapability) action) async {
    Object? failure;
    StackTrace? trace;
    await Future.wait(
      _capabilities.map((capability) async {
        try {
          await action(capability);
        } catch (error, stack) {
          failure ??= error;
          trace ??= stack;
        }
      }),
    );
    if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  }

  @override
  Future<void> stopAdmission() async {
    _stopped = true;
    gate.stopAdmission();
    await _each((c) => c.stopAdmission());
  }

  @override
  Future<void> cancelPending() => _each((c) => c.cancelPending());
  @override
  Future<void> closeSessions() => _each((c) => c.closeSessions());
  @override
  Future<void> drain() async {
    await _each((c) => c.drain());
    await gate.drain();
  }

  @override
  Future<void> dispose() async {
    await stopAdmission();
    await cancelPending();
    await closeSessions();
    await drain();
    await _each((c) => c.dispose());
    signer.dispose();
  }
}
