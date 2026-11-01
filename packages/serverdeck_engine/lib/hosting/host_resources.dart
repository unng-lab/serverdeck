import 'package:serverdeck_protocol/mcp/readiness.dart';

import '../api/owner_api.dart';
import '../api/mcp_server.dart';
import '../platform/ports.dart';
import '../platform/verified_release.dart';
import '../storage/key_custody.dart';
import '../storage/workspace.dart';
import 'control_services.dart';
import 'sessions.dart';

/// Engine-owned composition, not an OS port or a wire-provided factory. A root
/// supplies one fresh instance per Host. RAM implementations exercise lifecycle
/// without opening Isar; the normal implementation below owns the real store.
abstract interface class HostResources {
  bool get hasOpenReservation;
  String get workspaceId;
  TrustedOwnerApi get ownerApi;
  OperationalFeatures get features;
  int? get unresolvedJobs;
  Future<void> openWorkspace({
    required ProtectedFiles files,
    required NativeStoreRuntime runtime,
    required WorkspaceLease lease,
    required SecureVault vault,
    required void Function() checkStartup,
  });
  Future<void> openServices(EngineSessions sessions);
  Future<void> suspendServices();
  Future<void> revalidateServices();
  void resumeServices();
  McpApiServer mcpServer(
    EngineSessions sessions,
    TrustedReadiness Function() readiness,
  );
  Future<void> closeServices();
  Future<void> closeWorkspace();
}

final class WorkspaceHostResources implements HostResources {
  WorkspaceHostResources({this.executorRelease, this.bundle});
  final VerifiedExecutorRelease? executorRelease;
  final VerifiedAppConfiguration? bundle;
  Workspace? _workspace;
  KeyCustody? _custody;
  TrustedControlServices? _services;
  ControlServicesPause? _pause;
  bool _attempted = false, _uncertainServices = false;

  @override
  bool get hasOpenReservation =>
      _uncertainServices || Workspace.hasOpenReservation;
  @override
  String get workspaceId =>
      _workspace!.store.snapshot.foundation.foundation.workspaceId;
  @override
  TrustedOwnerApi get ownerApi => _services!;
  @override
  int? get unresolvedJobs => _workspace?.store.snapshot.automation.jobs.values
      .where(
        (job) =>
            !const {'succeeded', 'failed', 'cancelled'}.contains(job.state),
      )
      .length;
  @override
  OperationalFeatures get features => OperationalFeatures(
    profiles: true,
    ssh: true,
    jobs: executorRelease != null,
    // MCP becomes available only when the Host root publishes its endpoint.
  );

  @override
  Future<void> openWorkspace({
    required ProtectedFiles files,
    required NativeStoreRuntime runtime,
    required WorkspaceLease lease,
    required SecureVault vault,
    required void Function() checkStartup,
  }) async {
    if (_attempted) throw StateError('NOT_READY');
    _attempted = true;
    final custody = _custody = KeyCustody(vault, lease.ownerIdentity);
    _workspace = await Workspace.open(
      files: files,
      runtime: runtime,
      lease: lease,
      custody: custody,
      checkStartup: checkStartup,
    );
  }

  @override
  Future<void> openServices(EngineSessions sessions) async {
    final workspace = _workspace!;
    _services = await TrustedControlServices.create(
      store: workspace.store,
      custody: _custody!,
      receiptKey: workspace.receiptKey,
      sessions: sessions,
      executorRelease: executorRelease,
      bundle: bundle,
      onCleanupFailure: () => _uncertainServices = true,
    );
  }

  @override
  Future<void> suspendServices() {
    if (_uncertainServices) throw StateError('SERVICE_UNAVAILABLE');
    return (_pause ??= _services!.suspend()).settled;
  }

  @override
  Future<void> revalidateServices() async {
    if (_uncertainServices) throw StateError('SERVICE_UNAVAILABLE');
    // Current repository admission/revisions and selected executor capability;
    // retained app/native library and vault are independently checked by Host.
    _workspace!.store.snapshot;
    executorRelease?.revalidate();
    features;
  }

  @override
  void resumeServices() {
    if (_uncertainServices || _pause == null)
      throw StateError('SERVICE_UNAVAILABLE');
    _services!.resume(_pause!);
    _pause = null;
  }

  @override
  Future<void> closeServices() async {
    if (_uncertainServices) throw StateError('SERVICE_UNAVAILABLE');
    await _services?.close();
  }

  @override
  McpApiServer mcpServer(
    EngineSessions sessions,
    TrustedReadiness Function() readiness,
  ) {
    final services = _services!;
    if (!identical(sessions, services.sessions))
      throw StateError('UNAUTHORIZED');
    return McpApiServer(
      sessions: sessions,
      authority: services.authority,
      router: services.router,
      readiness: readiness,
    );
  }

  @override
  Future<void> closeWorkspace() async {
    if (_uncertainServices) throw StateError('STORAGE_BLOCKED');
    await _workspace?.close();
    if (hasOpenReservation) throw StateError('STORAGE_BLOCKED');
  }
}
