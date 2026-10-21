import 'dart:async';

import 'package:serverdeck_protocol/mcp/handshake.dart';

import '../mcp/grants.dart';
import '../storage/state_store.dart';
import 'operational_auth.dart';
import 'operational_server.dart';

/// Actual owner-role Local API adapter. Credential custody and durable receipt
/// semantics remain in StateStore; no input can supply a role or a gate.
final class OperationalGrantOwnerApi implements OperationalOwnerApi {
  OperationalGrantOwnerApi({required this.store, required this.sessions}) {
    if (!sessions.hasNativePublicationGate) throw StateError('NOT_READY');
    if (!store.isAutomationReady) throw StateError('STORAGE_BLOCKED');
  }
  final StateStore store;
  final OperationalSessions sessions;
  static const _methods = {
    'grants.create': 'grant.create',
    'grants.replace': 'grant.replace',
    'grants.revoke': 'grant.revoke',
  };

  @override
  bool supports(String method) => _methods.containsKey(method);

  @override
  Future<Map<String, Object?>> dispatch(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params,
  ) async {
    if (!request.belongsTo(sessions) ||
        request.role != OperationalRole.owner ||
        request.method != method) {
      throw StateError('FORBIDDEN');
    }
    final operation = _methods[method];
    if (operation == null) throw StateError('UNSUPPORTED');
    // Capture immutable typed fields synchronously before the native gate wait.
    final command = OwnerGrantCommand.parse(operation, params);
    final budget = request.rpcRemaining;
    return sessions.runAuthorityMutation(() async {
      // A queued writer's former proof is not authority to start a mutation.
      try {
        await request.revalidate().timeout(request.rpcRemaining);
      } on TimeoutException {
        throw StateError('TIMEOUT');
      }
      request.rpcRemaining;
      return store.mutateOwnerGrant(command, clock: DateTime.now);
    }, deadline: budget);
  }
}
