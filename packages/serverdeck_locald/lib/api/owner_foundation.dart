import 'dart:async';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_protocol/wire.dart';

import '../profiles/mutation_coordinator.dart';
import '../storage/state_store.dart';
import 'operational_auth.dart';
import 'operational_server.dart';
import 'owner_service_probe.dart';

/// Same owner foundation service for UI requests in the operational generation.
/// Wire callers cannot supply a role, coordinator, reservation or native gate.
final class OperationalFoundationOwnerApi implements OperationalOwnerApi {
  OperationalFoundationOwnerApi({
    required this.store,
    required this.coordinator,
    required this.sessions,
  }) {
    if (!identical(coordinator.store, store))
      throw ArgumentError('INVALID_CHANNEL_CONFIGURATION');
    if (!coordinator.isOperational || !sessions.hasNativePublicationGate)
      throw StateError('NOT_READY');
    store.operational;
    _unsubscribe = sessions.onSessionDetached(_detachSession);
  }
  final StateStore store;
  final MutationCoordinator coordinator;
  final OperationalSessions sessions;
  late final void Function() _unsubscribe;
  final _interests = <String, Set<String>>{};
  int _nextInterest = 0;
  bool _closed = false;
  Future<void>? _closing;
  static const _methods = {
    ApiMethod.profilesList,
    ApiMethod.profilesGet,
    ApiMethod.profilesCreate,
    ApiMethod.profilesUpdate,
    ApiMethod.profilesDelete,
    ApiMethod.settingsGet,
    ApiMethod.settingsUpdate,
    ApiMethod.mutationsGet,
    ApiMethod.mutationsRecent,
  };

  @override
  bool supports(String method) => _methods.any((m) => m.wireName == method);

  void _ready() {
    if (_closed) throw StateError('NOT_READY');
    store.operational;
  }

  @override
  OperationalOwnerInvocation prepare(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    if (!request.belongsTo(sessions) ||
        request.role != OperationalRole.owner ||
        request.method != method)
      throw StateError('FORBIDDEN');
    final methods = _methods.where((m) => m.wireName == method);
    if (methods.isEmpty) throw StateError('UNSUPPORTED');
    _ready();
    requireUuid(requestId);
    final operation = methods.single;
    if (!operation.isMutation) {
      final codec = StrictCodec();
      final captured = codec.decode(
        codec.encode(params, maxBytes: 256 * 1024),
        maxBytes: 256 * 1024,
      );
      validateMethodShape(method, captured);
      if (operation == ApiMethod.profilesGet)
        requireUuid(captured['profileId']);
      if (operation == ApiMethod.mutationsGet) {
        requireUuid(captured['requestId']);
        if (captured['requestId'] == requestId)
          throw const FormatException('VALIDATION');
      }
      final limit = captured['limit'] ?? 20;
      if (operation == ApiMethod.mutationsRecent &&
          (limit is! int || limit < 1 || limit > 100))
        throw const FormatException('VALIDATION');
      return OperationalOwnerInvocation(request, () async {
        await _proof(request);
        _ready();
        final result = switch (operation) {
          ApiMethod.profilesList => coordinator.listProfiles().toJson(),
          ApiMethod.profilesGet =>
            coordinator.getProfile(captured['profileId'] as String).toJson(),
          ApiMethod.settingsGet => coordinator.getSettings().toJson(),
          ApiMethod.mutationsGet =>
            coordinator.status(captured['requestId'] as String).toJson(),
          ApiMethod.mutationsRecent =>
            coordinator.recent(limit: limit as int).toJson(),
          _ => throw StateError('UNSUPPORTED'),
        };
        validateMethodResult(method, result);
        return result;
      });
    }
    if (_interests.values.fold<int>(0, (n, ids) => n + ids.length) >= 128)
      throw StateError('RESOURCE_LIMIT');
    final session = request.sessionId;
    final interest = 'owner-foundation/$session/${_nextInterest++}';
    final reservation = coordinator.reserve(
      requestId,
      operation,
      params,
      requester: interest,
    );
    (_interests[session] ??= {}).add(interest);
    return OperationalOwnerInvocation(request, () async {
      _ready();
      Future<Map<String, Object?>> effect() async {
        _ready();
        await _proof(request);
        _ready();
        request.rpcRemaining;
        final result = (await coordinator.activate(reservation)).toJson();
        if (ownerServiceProbesEnabled)
          await OwnerServiceProbe.hit(
            OwnerServiceBoundary.afterFoundationCommit,
            method,
          );
        validateMethodResult(method, result);
        return result;
      }

      if (operation == ApiMethod.settingsUpdate)
        return sessions.runAuthorityMutation(
          effect,
          deadline: request.rpcRemaining,
        );
      final lease = await sessions.beginTargetChange(
        deadline: request.rpcRemaining,
      );
      try {
        return await effect();
      } finally {
        await lease.close();
      }
    }, onClose: () => _release(session, interest));
  }

  Future<void> _proof(OperationalSessionRequest request) async {
    try {
      final budget = request.rpcRemaining;
      await request.revalidate().timeout(budget);
    } on TimeoutException {
      throw StateError('TIMEOUT');
    }
    request.rpcRemaining;
  }

  void _release(String session, String interest) {
    final ids = _interests[session];
    if (ids == null || !ids.remove(interest)) return;
    if (ids.isEmpty) _interests.remove(session);
    coordinator.detach(interest);
  }

  void _detachSession(String session) {
    final ids = _interests.remove(session);
    if (ids != null)
      for (final id in ids) {
        coordinator.detach(id);
      }
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _unsubscribe();
    for (final session in _interests.keys.toList()) {
      _detachSession(session);
    }
    return _closing = coordinator.close();
  }
}
