import 'dart:async';

import 'package:path/path.dart' as p;

import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/grant_owner.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_windows/mcp_build_bundle.dart'
    show TrustedBuildBundle;

import '../mcp/grants.dart';
import '../storage/state_store.dart';
import 'operational_auth.dart';
import 'owner_api.dart';

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
  OperationalOwnerInvocation prepare(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    if (!request.belongsTo(sessions) ||
        request.role != OperationalRole.owner ||
        request.method != method) {
      throw StateError('FORBIDDEN');
    }
    final operation = _methods[method];
    if (operation == null) throw StateError('UNSUPPORTED');
    // Capture immutable typed fields synchronously before the native gate wait.
    final command = OwnerGrantCommand.parse(operation, params);
    return OperationalOwnerInvocation(
      request,
      () => sessions.runAuthorityMutation(() async {
        // A queued writer's former proof is not authority to start a mutation.
        try {
          final budget = request.rpcRemaining;
          await request.revalidate().timeout(budget);
        } on TimeoutException {
          throw StateError('TIMEOUT');
        }
        request.rpcRemaining;
        return store.mutateOwnerGrant(command, clock: DateTime.now);
      }, deadline: request.rpcRemaining),
    );
  }
}

/// Fixed schema3 native owner adapter.
final class TrustedGrantOwnerApi implements TrustedOwnerApi {
  TrustedGrantOwnerApi({
    required this.store,
    required this.sessions,
    this.bundle,
  }) {
    if (!sessions.hasNativePublicationGate) throw StateError('NOT_READY');
    if (!store.isTrustedSnapshotLoaded) throw StateError('STORAGE_BLOCKED');
  }
  final StateStore store;
  final TrustedSessions sessions;
  final TrustedBuildBundle? bundle;
  static const _methods = {
    'grants.create': 'grant.create',
    'grants.replace': 'grant.replace',
    'grants.revoke': 'grant.revoke',
  };

  @override
  bool supports(String method) => grantOwnerMethods.contains(method);

  @override
  TrustedOwnerInvocation prepare(
    TrustedSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    if (!request.belongsTo(sessions) ||
        request.role != OperationalRole.owner ||
        request.method != method) {
      throw StateError('FORBIDDEN');
    }
    if (const {
      'grants.list',
      'grants.get',
      'grants.configuration',
    }.contains(method)) {
      final input = StrictCodec().decode(
        StrictCodec().encode(params, maxBytes: 4096),
        maxBytes: 4096,
      );
      requireFields(
        input,
        method == 'grants.list' ? {} : {'grantId'},
        method == 'grants.list' ? {'serverId'} : {},
      );
      for (final value in input.values) {
        requireUuid(value);
      }
      return TrustedOwnerInvocation(
        request,
        () => sessions.runAuthorityMutation(() async {
          await request.revalidate().timeout(request.rpcRemaining);
          request.rpcRemaining;
          final values = store.trustedOperational.automation.grants;
          final Map<String, Object?> result;
          if (method == 'grants.list') {
            final selected =
                values.values
                    .where(
                      (row) =>
                          input['serverId'] == null ||
                          row.policy.serverIds.contains(input['serverId']),
                    )
                    .toList()
                  ..sort((a, b) => a.id.compareTo(b.id));
            result = {
              'items': [for (final row in selected) row.toPublicJson()],
            };
          } else {
            final row = values[input['grantId']];
            if (row == null) throw StateError('NOT_FOUND');
            if (method == 'grants.get') {
              result = {'grant': row.toPublicJson()};
            } else {
              if (!row.isCurrentAt(DateTime.now().toUtc()))
                throw StateError('FORBIDDEN');
              final verified = bundle;
              if (verified == null) throw StateError('NOT_READY');
              final actualRoot = await request.verifiedOwnerBundleRoot();
              if (actualRoot !=
                      p.windows
                          .normalize(verified.manifest.appRoot)
                          .toLowerCase() ||
                  request.hello.buildId != verified.manifest.buildId)
                throw StateError('INCOMPATIBLE');
              result = verified.mcpConfiguration(row.id);
            }
          }
          final captured = captureGrantOwnerResult(method, result);
          await request.revalidate().timeout(request.rpcRemaining);
          request.rpcRemaining;
          if (method == 'grants.configuration' &&
              !values[input['grantId']]!.isCurrentAt(DateTime.now().toUtc()))
            throw StateError('FORBIDDEN');
          return captured;
        }, deadline: request.rpcRemaining),
      );
    }
    final operation = _methods[method];
    if (operation == null) throw StateError('UNSUPPORTED');
    // Capture immutable typed fields synchronously before the native gate wait.
    final command = OwnerGrantCommand.parse(operation, params);
    return TrustedOwnerInvocation(
      request,
      () => sessions.runAuthorityMutation(() async {
        // A queued writer's former proof is not authority to start a mutation.
        try {
          final budget = request.rpcRemaining;
          await request.revalidate().timeout(budget);
        } on TimeoutException {
          throw StateError('TIMEOUT');
        }
        request.rpcRemaining;
        return store.mutateTrustedOwnerGrant(command, clock: DateTime.now);
      }, deadline: request.rpcRemaining),
    );
  }
}
