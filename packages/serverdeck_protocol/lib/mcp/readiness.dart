import '../codec.dart';
import '../models.dart';
import '../validation.dart';
import 'wire.dart';

Never _invalid() => throw const FormatException('VALIDATION');
Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : _invalid();

final class OperationalFeatures {
  const OperationalFeatures({
    this.profiles = false,
    this.ssh = false,
    this.jobs = false,
    this.backend = false,
    this.mcp = false,
  });
  factory OperationalFeatures.fromJson(Object? input) {
    final value = _object(input);
    requireFields(value, {'profiles', 'ssh', 'jobs', 'backend', 'mcp'});
    if (value.values.any((v) => v is! bool)) _invalid();
    return OperationalFeatures(
      profiles: value['profiles'] as bool,
      ssh: value['ssh'] as bool,
      jobs: value['jobs'] as bool,
      backend: value['backend'] as bool,
      mcp: value['mcp'] as bool,
    );
  }
  final bool profiles, ssh, jobs, backend, mcp;
  bool get any => profiles || ssh || jobs || backend || mcp;
  Map<String, Object?> toJson() => {
    'profiles': profiles,
    'ssh': ssh,
    'jobs': jobs,
    'backend': backend,
    'mcp': mcp,
  };
}

String? _reason(ReadinessState state) => switch (state) {
  ReadinessState.starting || ReadinessState.recovering => 'NOT_READY',
  ReadinessState.ready => null,
  ReadinessState.storageBlocked => 'STORAGE_BLOCKED',
  ReadinessState.incompatible => 'INCOMPATIBLE',
  ReadinessState.stopping ||
  ReadinessState.unavailable => 'SERVICE_UNAVAILABLE',
};
String _state(ReadinessState state) =>
    state == ReadinessState.storageBlocked ? 'storage-blocked' : state.name;

/// API1.1 capabilities describe installed components, not target prerequisites
/// or grant scopes. A ready central dispatcher does not enable missing features.
final class OperationalReadiness {
  factory OperationalReadiness({
    required ReadinessState state,
    required String generation,
    String? workspaceId,
    OperationalFeatures features = const OperationalFeatures(),
  }) {
    requireUuid(generation);
    if (workspaceId != null) requireUuid(workspaceId);
    if (state == ReadinessState.ready && workspaceId == null ||
        state != ReadinessState.ready && features.any)
      _invalid();
    return OperationalReadiness._(state, generation, workspaceId, features);
  }
  const OperationalReadiness._(
    this.state,
    this.generation,
    this.workspaceId,
    this.features,
  );
  factory OperationalReadiness.fromJson(Object? input) {
    try {
      final value = _object(input);
      requireFields(value, {
        'state',
        'reason',
        'product',
        'apiMajor',
        'apiMinor',
        'workspaceSlot',
        'workspaceId',
        'generation',
        'storageSchema',
        'features',
        'clientPlatform',
      });
      for (final entry in const <String, Object>{
        'product': 'serverdeck-next',
        'apiMajor': 1,
        'apiMinor': 1,
        'workspaceSlot': 'default',
        'storageSchema': 2,
        'clientPlatform': 'windows-x64',
      }.entries) {
        final actual = value[entry.key];
        if (actual != entry.value ||
            actual.runtimeType != entry.value.runtimeType)
          _invalid();
      }
      final state = ReadinessState.values.where(
        (s) => _state(s) == value['state'],
      );
      if (state.length != 1 || value['reason'] != _reason(state.single))
        _invalid();
      if (value['generation'] is! String ||
          value['workspaceId'] != null && value['workspaceId'] is! String)
        _invalid();
      return OperationalReadiness(
        state: state.single,
        generation: value['generation'] as String,
        workspaceId: value['workspaceId'] as String?,
        features: OperationalFeatures.fromJson(value['features']),
      );
    } catch (_) {
      _invalid();
    }
  }
  factory OperationalReadiness.decode(List<int> bytes) =>
      OperationalReadiness.fromJson(
        StrictCodec().decode(bytes, maxBytes: 8192),
      );
  final ReadinessState state;
  final String generation;
  final String? workspaceId;
  final OperationalFeatures features;
  Map<String, Object?> toJson() => {
    'state': _state(state),
    'reason': _reason(state),
    'product': 'serverdeck-next',
    'apiMajor': 1,
    'apiMinor': 1,
    'workspaceSlot': 'default',
    'workspaceId': workspaceId,
    'generation': generation,
    'storageSchema': 2,
    'features': features.toJson(),
    'clientPlatform': 'windows-x64',
  };
  List<int> encode() => encodeMcpMessage(toJson(), maxBytes: 8192);
}

/// Structural format3 readiness only; native composition supplies authority.
final class TrustedReadiness {
  factory TrustedReadiness({
    required ReadinessState state,
    required String generation,
    String? workspaceId,
    OperationalFeatures features = const OperationalFeatures(),
  }) {
    requireUuid(generation);
    if (workspaceId != null) requireUuid(workspaceId);
    if (state == ReadinessState.ready && workspaceId == null ||
        state != ReadinessState.ready && features.any)
      _invalid();
    return TrustedReadiness._(state, generation, workspaceId, features);
  }
  const TrustedReadiness._(
    this.state,
    this.generation,
    this.workspaceId,
    this.features,
  );
  factory TrustedReadiness.fromJson(Object? input) {
    try {
      final value = _object(input);
      requireFields(value, {
        'state',
        'reason',
        'product',
        'apiMajor',
        'apiMinor',
        'workspaceSlot',
        'workspaceId',
        'generation',
        'storageSchema',
        'features',
        'clientPlatform',
      });
      for (final entry in const <String, Object>{
        'product': 'serverdeck-next',
        'apiMajor': 1,
        'apiMinor': 1,
        'workspaceSlot': 'default',
        'storageSchema': 3,
        'clientPlatform': 'windows-x64',
      }.entries) {
        final actual = value[entry.key];
        if (actual != entry.value ||
            actual.runtimeType != entry.value.runtimeType)
          _invalid();
      }
      final state = ReadinessState.values.where(
        (s) => _state(s) == value['state'],
      );
      if (state.length != 1 || value['reason'] != _reason(state.single))
        _invalid();
      if (value['generation'] is! String ||
          value['workspaceId'] != null && value['workspaceId'] is! String)
        _invalid();
      return TrustedReadiness(
        state: state.single,
        generation: value['generation'] as String,
        workspaceId: value['workspaceId'] as String?,
        features: OperationalFeatures.fromJson(value['features']),
      );
    } catch (_) {
      _invalid();
    }
  }
  factory TrustedReadiness.decode(List<int> bytes) =>
      TrustedReadiness.fromJson(StrictCodec().decode(bytes, maxBytes: 8192));
  final ReadinessState state;
  final String generation;
  final String? workspaceId;
  final OperationalFeatures features;
  Map<String, Object?> toJson() => {
    'state': _state(state),
    'reason': _reason(state),
    'product': 'serverdeck-next',
    'apiMajor': 1,
    'apiMinor': 1,
    'workspaceSlot': 'default',
    'workspaceId': workspaceId,
    'generation': generation,
    'storageSchema': 3,
    'features': features.toJson(),
    'clientPlatform': 'windows-x64',
  };
  List<int> encode() => encodeMcpMessage(toJson(), maxBytes: 8192);
}
