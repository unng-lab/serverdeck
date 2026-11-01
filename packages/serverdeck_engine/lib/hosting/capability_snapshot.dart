import '../platform/ports.dart' show VaultAccess;

enum EnginePlatformKind { windows, linux, macos, android, ios, web }

enum EngineBackgroundPolicy { desktopWhileRunning, foregroundOnly, unsupported }

/// Observed availability only. No identity, grant or runtime authority is here.
final class EngineCapabilities {
  factory EngineCapabilities({
    required EnginePlatformKind platform,
    required bool storageReady,
    required VaultAccess vaultStatus,
    required bool directSsh,
    required bool localMcpBridge,
    required bool trayAvailable,
    required EngineBackgroundPolicy backgroundPolicy,
    required Iterable<String> reasonCodes,
  }) {
    final reasons = reasonCodes.toSet().toList()..sort();
    if (reasons.any((r) => !safeReasons.contains(r)) ||
        backgroundPolicy != policy(platform))
      _invalid();
    if (platform != EnginePlatformKind.windows) {
      if (storageReady ||
          vaultStatus != VaultAccess.unavailable ||
          directSsh ||
          localMcpBridge ||
          trayAvailable ||
          reasons.length != 1 ||
          reasons.single != 'PREREQUISITE_UNAVAILABLE')
        _invalid();
    } else if (storageReady) {
      if (vaultStatus != VaultAccess.available || reasons.isNotEmpty)
        _invalid();
    } else if (vaultStatus == VaultAccess.available ||
        directSsh ||
        localMcpBridge ||
        reasons.isEmpty) {
      _invalid();
    }
    return EngineCapabilities._(
      platform,
      storageReady,
      vaultStatus,
      directSsh,
      localMcpBridge,
      trayAvailable,
      backgroundPolicy,
      List.unmodifiable(reasons),
    );
  }
  const EngineCapabilities._(
    this.platform,
    this.storageReady,
    this.vaultStatus,
    this.directSsh,
    this.localMcpBridge,
    this.trayAvailable,
    this.backgroundPolicy,
    this.reasonCodes,
  );
  factory EngineCapabilities.unavailable(
    EnginePlatformKind platform, {
    String reason = 'NOT_READY',
    VaultAccess vaultStatus = VaultAccess.unavailable,
    bool trayAvailable = false,
  }) => EngineCapabilities(
    platform: platform,
    storageReady: false,
    vaultStatus:
        platform == EnginePlatformKind.windows &&
            vaultStatus != VaultAccess.available
        ? vaultStatus
        : VaultAccess.unavailable,
    directSsh: false,
    localMcpBridge: false,
    trayAvailable: platform == EnginePlatformKind.windows && trayAvailable,
    backgroundPolicy: policy(platform),
    reasonCodes: [
      platform == EnginePlatformKind.windows
          ? (safeReasons.contains(reason) ? reason : 'SERVICE_UNAVAILABLE')
          : 'PREREQUISITE_UNAVAILABLE',
    ],
  );
  factory EngineCapabilities.fromJson(Object? input) {
    if (input is! Map<String, Object?> ||
        input.length != 8 ||
        !input.keys.toSet().containsAll(const {
          'platform',
          'storageReady',
          'vaultStatus',
          'directSsh',
          'localMcpBridge',
          'trayAvailable',
          'backgroundPolicy',
          'reasonCodes',
        }))
      _invalid();
    final platform = EnginePlatformKind.values
        .where((v) => v.name == input['platform'])
        .firstOrNull;
    final vault = VaultAccess.values
        .where((v) => v.name == input['vaultStatus'])
        .firstOrNull;
    final background = EngineBackgroundPolicy.values
        .where((v) => v.name == input['backgroundPolicy'])
        .firstOrNull;
    final reasons = input['reasonCodes'];
    if (platform == null ||
        vault == null ||
        background == null ||
        input['storageReady'] is! bool ||
        input['directSsh'] is! bool ||
        input['localMcpBridge'] is! bool ||
        input['trayAvailable'] is! bool ||
        reasons is! List ||
        reasons.length > 8 ||
        reasons.any((v) => v is! String))
      _invalid();
    final captured = reasons.cast<String>().toList();
    for (var i = 1; i < captured.length; i++) {
      if (captured[i - 1].compareTo(captured[i]) >= 0) _invalid();
    }
    return EngineCapabilities(
      platform: platform,
      storageReady: input['storageReady'] as bool,
      vaultStatus: vault,
      directSsh: input['directSsh'] as bool,
      localMcpBridge: input['localMcpBridge'] as bool,
      trayAvailable: input['trayAvailable'] as bool,
      backgroundPolicy: background,
      reasonCodes: captured,
    );
  }
  static Never _invalid() => throw const FormatException('INCOMPATIBLE');
  static const safeReasons = {
    'NOT_READY',
    'TIMEOUT',
    'STORAGE_BLOCKED',
    'INCOMPATIBLE',
    'PREREQUISITE_UNAVAILABLE',
    'UNAUTHORIZED',
    'RESOURCE_LIMIT',
    'SERVICE_UNAVAILABLE',
  };
  static EngineBackgroundPolicy policy(EnginePlatformKind kind) =>
      switch (kind) {
        EnginePlatformKind.windows =>
          EngineBackgroundPolicy.desktopWhileRunning,
        EnginePlatformKind.android ||
        EnginePlatformKind.ios => EngineBackgroundPolicy.foregroundOnly,
        _ => EngineBackgroundPolicy.unsupported,
      };
  final EnginePlatformKind platform;
  final bool storageReady, directSsh, localMcpBridge, trayAvailable;
  final VaultAccess vaultStatus;
  final EngineBackgroundPolicy backgroundPolicy;
  final List<String> reasonCodes;
  bool get coreUsable =>
      platform == EnginePlatformKind.windows &&
      storageReady &&
      vaultStatus == VaultAccess.available &&
      reasonCodes.isEmpty;
  EngineCapabilities withTray(bool available) => EngineCapabilities(
    platform: platform,
    storageReady: storageReady,
    vaultStatus: vaultStatus,
    directSsh: directSsh,
    localMcpBridge: localMcpBridge,
    trayAvailable: available,
    backgroundPolicy: backgroundPolicy,
    reasonCodes: reasonCodes,
  );
  EngineCapabilities withdraw(String reason) => EngineCapabilities.unavailable(
    platform,
    reason: reason,
    vaultStatus: vaultStatus,
    trayAvailable: trayAvailable,
  );
  Map<String, Object?> toJson() => {
    'platform': platform.name,
    'storageReady': storageReady,
    'vaultStatus': vaultStatus.name,
    'directSsh': directSsh,
    'localMcpBridge': localMcpBridge,
    'trayAvailable': trayAvailable,
    'backgroundPolicy': backgroundPolicy.name,
    'reasonCodes': List<String>.of(reasonCodes),
  };
}
