import 'dart:async';
import 'dart:math';

import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/host_trust.dart'
    show SshTransportFailure, SshTransportCode;
import 'package:serverdeck_protocol/connections.dart';
import 'package:serverdeck_protocol/executor.dart';
import 'package:serverdeck_protocol/executor_enrollment.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_windows/mcp_build_bundle.dart';

import '../api/operational_auth.dart';
import '../storage/state_store.dart';
import 'connections.dart';

/// Shared enrolled executor facade. No caller-supplied binding is accepted.
final class RemoteExecutorService {
  RemoteExecutorService(this.connections, {this.release}) {
    _unsubscribe = connections.sessions.onSessionDetached((session) {
      _inspections.removeWhere((_, value) => value.session == session);
    });
  }
  final TrustedConnectionService connections;
  final VerifiedExecutorRelease? release;
  final _operations = <RemoteExecutorOperation>{};
  bool _closed = false;
  final _inspections = <String, _ExecutorInspection>{};
  final _clock = Stopwatch()..start();
  final _enrollmentListeners = <void Function(String)>{};
  late final void Function() _unsubscribe;

  void Function() onEnrollmentChanged(void Function(String) listener) {
    _enrollmentListeners.add(listener);
    return () => _enrollmentListeners.remove(listener);
  }

  void enrollmentChanged(String server) {
    requireUuid(server);
    for (final listener in _enrollmentListeners.toList()) {
      listener(server);
    }
  }

  RemoteExecutorOperation inspectOwner(
    TrustedOwnerReadContext context,
    String server,
  ) {
    if (!context.belongsTo(connections.sessions)) throw StateError('FORBIDDEN');
    context.remaining;
    if (release == null) throw StateError('EXECUTOR_UNAVAILABLE');
    release!.revalidate();
    return _start(
      RemoteExecutorOperation._(
        this,
        server,
        null,
        context,
        McpScope.read,
        true,
      ),
    );
  }

  Map<String, Object?> inspection(
    TrustedOwnerReadContext context,
    RemoteExecutorSession session,
  ) {
    if (_closed) throw StateError('SERVICE_UNAVAILABLE');
    if (!context.belongsTo(connections.sessions) ||
        !identical(session._work.principal, context.connectionInterest))
      throw StateError('FORBIDDEN');
    context.remaining;
    release?.revalidate();
    _inspections.removeWhere((_, value) => _clock.elapsed >= value.expires);
    if (_inspections.length >= 16) throw StateError('RESOURCE_LIMIT');
    final id = executorRequestId();
    _inspections[id] = _ExecutorInspection(
      context.connectionInterest,
      context.sessionId,
      session.enrollment,
      _clock.elapsed + const Duration(seconds: 60),
    );
    final until = DateTime.now().toUtc().add(const Duration(seconds: 60));
    return {
      'serverId': session.enrollment.serverId,
      'challengeId': id,
      'expiresAt': DateTime.fromMillisecondsSinceEpoch(
        until.millisecondsSinceEpoch,
        isUtc: true,
      ).toIso8601String(),
      'enrollment': session.enrollment.toJson(),
    };
  }

  ExecutorEnrollment confirmedInput(
    TrustedSessionRequest request,
    String challenge,
    String server,
    String host,
  ) {
    if (!request.belongsTo(connections.sessions) ||
        request.role != OperationalRole.owner ||
        request.method != 'executor.confirm' ||
        !request.initialAdmissionProved)
      throw StateError('FORBIDDEN');
    request.rpcRemaining;
    release?.revalidate();
    final value = _inspections[requireUuid(challenge)];
    if (value == null ||
        _clock.elapsed >= value.expires ||
        !identical(value.principal, request.connectionInterest))
      throw StateError('NOT_FOUND');
    if (value.enrollment.serverId != server || value.enrollment.hostId != host)
      throw StateError('TRUST_CHANGED');
    return value.enrollment;
  }

  RemoteExecutorOperation startMcp(
    TrustedMcpContext context,
    String server, {
    McpScope scope = McpScope.read,
  }) {
    if (!context.belongsTo(connections.sessions, connections.authority))
      throw StateError('FORBIDDEN');
    context.authorize(scope: scope, serverId: server);
    return _start(
      RemoteExecutorOperation._(this, server, context, null, scope),
    );
  }

  RemoteExecutorOperation startOwner(
    TrustedOwnerReadContext context,
    String server,
  ) {
    if (!context.belongsTo(connections.sessions)) throw StateError('FORBIDDEN');
    context.remaining;
    return _start(
      RemoteExecutorOperation._(this, server, null, context, McpScope.read),
    );
  }

  RemoteExecutorOperation _start(RemoteExecutorOperation operation) {
    if (_closed) throw StateError('SERVICE_UNAVAILABLE');
    if (_operations.length >= 48) throw StateError('RESOURCE_LIMIT');
    _operations.add(operation);
    operation._run().ignore();
    return operation;
  }

  RemoteExecutorOperation startAutomationOwner(
    TrustedOwnerAutomationContext context,
    String server, {
    required McpScope scope,
  }) {
    if (!context.belongsTo(connections.sessions)) throw StateError('FORBIDDEN');
    context.authorizeExecutorScope(scope);
    return _start(
      RemoteExecutorOperation._(
        this,
        server,
        null,
        null,
        scope,
        false,
        context,
      ),
    );
  }

  Future<void> close() async {
    _closed = true;
    _unsubscribe();
    _inspections.clear();
    _enrollmentListeners.clear();
    await Future.wait([
      for (final operation in _operations.toList()) operation.close(),
    ]);
  }

  Future<void> retireServer(String server) async {
    requireUuid(server);
    await Future.wait([
      for (final operation in _operations.toList())
        if (operation.server == server) operation.close(),
    ]);
    _inspections.removeWhere(
      (_, value) =>
          value.enrollment.serverId == server &&
          _clock.elapsed >= value.expires,
    );
  }

  Future<ExecutorEnrollment> _enrollment(String server) async {
    requireUuid(server);
    final values = await connections.store.readExecutorEnrollments();
    final enrollment = values[server];
    if (enrollment == null) throw StateError('EXECUTOR_UNAVAILABLE');
    return enrollment;
  }

  Future<RemoteExecutorSession> _open(
    ConnectionExecutorWork work,
    ExecutorEnrollment? enrollment,
  ) async {
    try {
      await work.ready;
      final current = work.identity;
      if (enrollment != null && !_same(current, enrollment.connection))
        throw StateError('TRUST_CHANGED');
      final state = connections.store.trustedOperational.foundation.foundation;
      final profile = state.profiles[current.profileId];
      if (profile == null ||
          enrollment != null && enrollment.workspaceId != state.workspaceId)
        throw StateError('TRUST_CHANGED');
      final target = <String, Object?>{
        'workspaceId': state.workspaceId,
        'serverId': profile.id,
        'targetRevision': profile.revision,
        'connectionRevision': current.connectionRevision,
        'accessRevision': current.credentialRevision,
        'trustRevision': current.trustRevision,
      };
      // A workspace is one persistent controller, shared by owner UI/MCP clients.
      final hello = await work.request(
        ExecutorRequest.capture('hello', {
          'controllerId': state.workspaceId,
          'workspaceId': state.workspaceId,
        }, requestId: executorRequestId()),
      );
      requireFields(hello, {
        'hostId',
        'runtimeVersion',
        'lockDigest',
        'registryDigest',
        'compilerDigest',
        'bridgeDigest',
        'bootIdHash',
        'capabilities',
      });
      if (enrollment != null && hello['hostId'] != enrollment.hostId)
        throw StateError('TRUST_CHANGED');
      final descriptor = release?.descriptor;
      if (descriptor == null || !descriptor.matches(hello))
        throw StateError('RUNTIME_INCOMPATIBLE');
      for (final field in [
        'runtimeVersion',
        'lockDigest',
        'registryDigest',
        'compilerDigest',
        'bridgeDigest',
      ]) {
        if (enrollment != null && hello[field] != enrollment.toJson()[field])
          throw StateError('RUNTIME_INCOMPATIBLE');
      }
      if (hello['bootIdHash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hello['bootIdHash'] as String) ||
          hello['capabilities'] is! Map<String, Object?>)
        throw StateError('RUNTIME_INCOMPATIBLE');
      enrollment ??= ExecutorEnrollment.fromJson({
        'format': 1,
        'workspaceId': state.workspaceId,
        'serverId': current.profileId,
        'connection': current.toJson(),
        'hostId': hello['hostId'],
        'runtimeVersion': hello['runtimeVersion'],
        'lockDigest': hello['lockDigest'],
        'registryDigest': hello['registryDigest'],
        'compilerDigest': hello['compilerDigest'],
        'bridgeDigest': hello['bridgeDigest'],
        'createdAt': DateTime.fromMillisecondsSinceEpoch(
          DateTime.now().toUtc().millisecondsSinceEpoch,
          isUtc: true,
        ).toIso8601String(),
      });
      return RemoteExecutorSession._(
        work,
        enrollment,
        Map.unmodifiable(target),
        Map.unmodifiable(hello),
      );
    } catch (error) {
      await work.close();
      if (error is ExecutorRemoteError)
        throw StateError(executorDomainCode(error.code));
      if (error is SshTransportFailure) throw StateError(_transportCode(error));
      rethrow;
    }
  }
}

/// Owns pending protected-file/native/SSH work independently of response interest.
final class RemoteExecutorOperation {
  RemoteExecutorOperation._(
    this.service,
    this.server,
    this.mcp,
    this.owner,
    this.scope, [
    this.inspect = false,
    this.automationOwner,
  ]) {
    _result.future.ignore();
  }
  final RemoteExecutorService service;
  final String server;
  final TrustedMcpContext? mcp;
  final TrustedOwnerReadContext? owner;
  final TrustedOwnerAutomationContext? automationOwner;
  final McpScope scope;
  final bool inspect;
  final _result = Completer<RemoteExecutorSession>(), _done = Completer<void>();
  ConnectionExecutorWork? _connection;
  bool _stopped = false;
  Future<RemoteExecutorSession> get result => _result.future;
  Future<void> get done => _done.future;
  Future<void> close() {
    _stopped = true;
    if (!_result.isCompleted) _result.completeError(StateError('CANCELLED'));
    _connection?.close().ignore();
    return done;
  }

  void _live() {
    if (_stopped || service._closed) throw StateError('CANCELLED');
    if (owner != null) owner!.remaining;
    automationOwner?.authorizeExecutorScope(scope);
    mcp?.authorize(scope: scope, serverId: server);
  }

  Future<void> _run() async {
    Timer? timer;
    try {
      timer = Timer(
        owner?.remaining ??
            automationOwner?.remaining ??
            (scope == McpScope.apply
                ? const Duration(hours: 2)
                : const Duration(seconds: 30)),
        () => close().ignore(),
      );
      _live();
      final enrollment = inspect ? null : await service._enrollment(server);
      _live();
      final work = _connection = owner != null
          ? service.connections.openExecutorOwner(owner!, server)
          : automationOwner != null
          ? service.connections.openExecutorAutomationOwner(
              automationOwner!,
              server,
              scope: scope,
            )
          : service.connections.openExecutorMcp(mcp!, server, scope: scope);
      final session = await service._open(work, enrollment);
      _live();
      _result.complete(session);
      await work.done;
    } catch (error) {
      if (!_result.isCompleted) _result.completeError(error);
    } finally {
      timer?.cancel();
      _stopped = true;
      await _connection?.close();
      service._operations.remove(this);
      _done.complete();
    }
  }
}

final class _ExecutorInspection {
  _ExecutorInspection(
    this.principal,
    this.session,
    this.enrollment,
    this.expires,
  );
  final Object principal;
  final String session;
  final ExecutorEnrollment enrollment;
  final Duration expires;
}

bool _same(ConnectionIdentity a, ConnectionIdentity b) =>
    a.profileId == b.profileId &&
    a.connectionRevision == b.connectionRevision &&
    a.credentialRevision == b.credentialRevision &&
    a.trustRevision == b.trustRevision &&
    a.key == b.key;

final class RemoteExecutorSession {
  RemoteExecutorSession._(this._work, this.enrollment, this.target, this.hello);
  final ConnectionExecutorWork _work;
  final ExecutorEnrollment enrollment;
  final Map<String, Object?> target, hello;
  Future<void> get done => _work.done;
  Future<void> close() => _work.close();
  Future<Map<String, Object?>> request(
    String method,
    Map<String, Object?> params,
  ) async {
    try {
      return await _work.request(
        ExecutorRequest.capture(method, params, requestId: executorRequestId()),
      );
    } on ExecutorRemoteError catch (error) {
      throw StateError(executorDomainCode(error.code));
    } on SshTransportFailure catch (error) {
      throw StateError(_transportCode(error));
    }
  }

  Future<ManagedResourceObservationRecord> observe(String resource) async {
    final result = await request('observe', {
      'resourceId': resource,
      'target': target,
      'expectedHostId': enrollment.hostId,
    });
    requireFields(result, {'observation'});
    final value = result['observation'];
    if (value is! Map<String, Object?>)
      throw const FormatException('VALIDATION');
    final observation = ManagedResourceObservationRecord.fromTrustedJson(value);
    for (final field in target.keys) {
      if (value[field] != target[field]) throw StateError('TRUST_CHANGED');
    }
    if (observation.hostId != enrollment.hostId ||
        observation.resourceRegistryDigest != enrollment.registryDigest ||
        observation.resourceId != resource ||
        observation.status != 'known')
      throw StateError('RUNTIME_INCOMPATIBLE');
    final now = DateTime.now().toUtc(), at = observation.observedAt;
    if (at.isAfter(now) || now.difference(at) > const Duration(seconds: 15))
      throw StateError('PLAN_STALE');
    return observation;
  }
}

String executorDomainCode(String code) => switch (code) {
  'CONFLICT' => 'PLAN_STALE',
  'QUALIFICATION_REQUIRED' || 'INCOMPATIBLE' => 'RUNTIME_INCOMPATIBLE',
  'RECOVERY_REQUIRED' => 'UNKNOWN_OUTCOME',
  'PREFLIGHT_FAILED' ||
  'HEALTH_CHECK_FAILED' ||
  'POSTCHECK_FAILED' ||
  'STEP_FAILED' => 'UNSUPPORTED',
  'INVALID_FRAME' => 'RUNTIME_INCOMPATIBLE',
  'VALIDATION' ||
  'FORBIDDEN' ||
  'RESOURCE_LIMIT' ||
  'TIMEOUT' ||
  'TRUST_CHANGED' ||
  'HOST_BUSY' ||
  'EXECUTOR_UNAVAILABLE' ||
  'UNKNOWN_OUTCOME' ||
  'NOT_FOUND' ||
  'UNSUPPORTED' ||
  'INTERNAL' => code,
  _ => 'INTERNAL',
};

String _transportCode(SshTransportFailure error) => switch (error.code) {
  SshTransportCode.TIMEOUT => 'TIMEOUT',
  SshTransportCode.RESOURCE_LIMIT => 'RESOURCE_LIMIT',
  SshTransportCode.TRUST_CHANGED => 'TRUST_CHANGED',
  _ => 'EXECUTOR_UNAVAILABLE',
};

String executorRequestId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final text = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${text.substring(0, 8)}-${text.substring(8, 12)}-${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
}
