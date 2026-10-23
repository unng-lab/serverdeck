import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../remote/executor.dart';
import '../storage/state_store.dart';
import 'operational_auth.dart';
import 'owner_api.dart';

/// No MCP route can enter confirmation/revoke. Prepared input is bounded before
/// admission, but owner proof and the common native target fence own effects.
final class ExecutorOwnerApi implements TrustedOwnerApi {
  ExecutorOwnerApi(this.service);
  final RemoteExecutorService service;
  static const methods = {
    'executor.enrollment',
    'executor.confirm',
    'executor.revoke',
  };
  @override
  bool supports(String method) => methods.contains(method);

  @override
  TrustedOwnerInvocation prepare(
    TrustedSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    final connections = service.connections;
    connections.requireOwner(request, method, admitted: false);
    if (!supports(method)) throw StateError('UNSUPPORTED');
    requireUuid(requestId);
    final input = StrictCodec().decode(
      StrictCodec().encode(params, maxBytes: 4096),
      maxBytes: 4096,
    );
    requireFields(
      input,
      method == 'executor.confirm'
          ? {'profileId', 'challengeId', 'hostId'}
          : {'profileId'},
    );
    for (final value in input.values) {
      requireUuid(value);
    }
    final server = input['profileId'] as String;
    return TrustedOwnerInvocation(request, () async {
      connections.requireOwner(request, method);
      await request.revalidate().timeout(request.rpcRemaining);
      request.rpcRemaining;
      if (method == 'executor.enrollment') {
        final values = await connections.store.readExecutorEnrollments();
        await request.revalidate().timeout(request.rpcRemaining);
        request.rpcRemaining;
        return {'profileId': server, 'enrollment': values[server]?.toJson()};
      }
      final lease = await connections.sessions.beginReconciledTargetChange(
        deadline: request.rpcRemaining,
      );
      try {
        await request.revalidate().timeout(request.rpcRemaining);
        request.rpcRemaining;
        final replay = await connections.store.readExecutorEnrollmentReceipt(
          requestId: requestId,
          method: method,
          input: input,
        );
        await request.revalidate().timeout(request.rpcRemaining);
        request.rpcRemaining;
        if (replay != null) return replay;
        final before = (await connections.store
            .readExecutorEnrollments())[server];
        if (method == 'executor.revoke') {
          if (before != null) {
            lease.retireAffected({server});
            await service.retireServer(server);
          }
          final result = await connections.store.mutateExecutorEnrollment(
            requestId: requestId,
            method: method,
            input: input,
            enrollment: null,
            revalidate: () async {
              await request.revalidate().timeout(request.rpcRemaining);
              request.rpcRemaining;
            },
          );
          if (before != null) service.enrollmentChanged(server);
          await request.revalidate().timeout(request.rpcRemaining);
          request.rpcRemaining;
          return result;
        }
        final enrollment = service.confirmedInput(
          request,
          input['challengeId'] as String,
          server,
          input['hostId'] as String,
        );
        connections.requireCurrentIdentity(enrollment.connection);
        final proposed = {...enrollment.toJson()}..remove('createdAt');
        final previous = before == null
            ? null
            : ({...before.toJson()}..remove('createdAt'));
        final unchanged =
            previous != null &&
            StrictCodec().canonical(previous).toString() ==
                StrictCodec().canonical(proposed).toString();
        if (!unchanged) {
          lease.retireAffected({server});
          await service.retireServer(server);
        }
        final result = await connections.store.mutateExecutorEnrollment(
          requestId: requestId,
          method: method,
          input: input,
          enrollment: enrollment,
          revalidate: () async {
            await request.revalidate().timeout(request.rpcRemaining);
            request.rpcRemaining;
            service.confirmedInput(
              request,
              input['challengeId'] as String,
              server,
              input['hostId'] as String,
            );
            connections.requireCurrentIdentity(enrollment.connection);
          },
        );
        if (!unchanged) service.enrollmentChanged(server);
        await request.revalidate().timeout(request.rpcRemaining);
        request.rpcRemaining;
        connections.requireCurrentIdentity(enrollment.connection);
        return result;
      } finally {
        await lease.close();
      }
    });
  }
}
