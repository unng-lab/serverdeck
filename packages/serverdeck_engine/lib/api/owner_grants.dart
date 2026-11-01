import 'dart:async';

import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/grant_owner.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_engine/platform/ports.dart'
    show VerifiedAppConfiguration;

import 'package:serverdeck_engine/mcp/grants.dart';
import 'package:serverdeck_engine/storage/state_store.dart';

import '../hosting/sessions.dart';
import 'owner_api.dart';

/// Fixed schema3 native owner adapter.
final class TrustedGrantOwnerApi implements TrustedOwnerApi {
  TrustedGrantOwnerApi({
    required this.store,
    required this.sessions,
    this.bundle,
  }) {
    if (!sessions.hasPublicationGate) throw StateError('NOT_READY');
    if (!store.isReady) throw StateError('STORAGE_BLOCKED');
  }
  final StateStore store;
  final EngineSessions sessions;
  final VerifiedAppConfiguration? bundle;
  static const _methods = {
    'grants.create': 'grant.create',
    'grants.replace': 'grant.replace',
    'grants.revoke': 'grant.revoke',
  };

  @override
  bool supports(String method) => grantOwnerMethods.contains(method);

  @override
  TrustedOwnerInvocation prepare(
    SessionRequest request,
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
          final values = store.snapshot.automation.grants;
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
              if (actualRoot != verified.appRoot ||
                  request.hello.buildId != verified.buildId)
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
        return store.mutateOwnerGrant(command, clock: DateTime.now);
      }, deadline: request.rpcRemaining),
    );
  }
}
