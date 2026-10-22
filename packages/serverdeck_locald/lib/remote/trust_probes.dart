import 'dart:async';
import 'dart:math';

import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../api/operational_auth.dart';
import '../storage/models.dart';
import '../storage/state_store.dart';
import 'ssh_transport.dart';

/// Shared format3 owner service. A probe never loads credentials or writes trust.
/// The caller owns the shared transport pool and closes it after this service.
final class HostTrustProbeService {
  HostTrustProbeService({
    required this.store,
    required this.sessions,
    required this.transports,
    Duration Function()? elapsed,
    DateTime Function()? clock,
  }) : _elapsed = elapsed,
       _wall = clock ?? DateTime.now {
    if (!sessions.hasNativePublicationGate) throw StateError('NOT_READY');
    store.trustedOperational;
    _watch.start();
    _unsubscribe = sessions.onSessionDetached(_detach);
  }
  final StateStore store;
  final TrustedSessions sessions;
  final SshTransportPool transports;
  final Duration Function()? _elapsed;
  final DateTime Function() _wall;
  final _watch = Stopwatch();
  Duration get _now => _elapsed?.call() ?? _watch.elapsed;
  late final void Function() _unsubscribe;
  final _operations = <String, _TrustProbe>{};
  int _interest = 0;
  bool _closed = false;
  Future<void>? _closing;
  int get retainedProbes {
    _sweep();
    return _operations.length;
  }

  void _ready() {
    if (_closed) throw StateError('SERVICE_UNAVAILABLE');
    store.trustedOperational;
  }

  void requireOwner(
    TrustedSessionRequest request,
    String method, {
    bool admitted = true,
  }) {
    if (!request.belongsTo(sessions) ||
        request.role != OperationalRole.owner ||
        request.method != method)
      throw StateError('FORBIDDEN');
    if (admitted && !request.initialAdmissionProved)
      throw StateError('FORBIDDEN');
    _ready();
  }

  TrustProbeReservation reserve(
    TrustedSessionRequest request,
    Map<String, Object?> params,
    String requestId,
  ) {
    requireOwner(request, 'servers.trust.probe', admitted: false);
    requireUuid(requestId);
    final input = captureHostTrustParams('servers.trust.probe', params);
    _sweep();
    var operation = _operations[requestId];
    if (operation != null) {
      if (operation.session != request.sessionId || operation.retired)
        throw StateError('NOT_FOUND');
      if (operation.profile != input['profileId'] ||
          operation.revision != input['expectedRevision'])
        throw StateError('IDEMPOTENCY_CONFLICT');
      if (operation.started && operation.completed && operation.result == null)
        throw StateError('NOT_FOUND');
    } else {
      if (_operations.length >= 16) throw StateError('RESOURCE_LIMIT');
      operation = _TrustProbe(
        requestId,
        request.sessionId,
        input['profileId'] as String,
        input['expectedRevision'] as String,
      );
      _operations[requestId] = operation;
    }
    final interest = ++_interest;
    operation.interests.add(interest);
    return TrustProbeReservation._(this, operation, interest);
  }

  Map<String, Object?> start(
    TrustedSessionRequest request,
    TrustProbeReservation reservation,
  ) {
    requireOwner(request, 'servers.trust.probe');
    _sweep();
    request.rpcRemaining;
    final operation = reservation._operation;
    if (!identical(reservation._service, this) ||
        operation.session != request.sessionId)
      throw StateError('FORBIDDEN');
    if (!identical(_operations[operation.id], operation) ||
        operation.retired ||
        !operation.interests.contains(reservation._interest))
      throw StateError('NOT_FOUND');
    if (operation.completed && operation.result == null)
      throw StateError('NOT_FOUND');
    if (!operation.started && !operation.completed) {
      final profile = _profile(operation.profile);
      if (profile.revision != operation.revision)
        throw StateError('REVISION_CONFLICT');
      final context = request.ownerProbeContext();
      final budget = context.remaining;
      request.rpcRemaining;
      operation.context = context;
      operation.captured = profile;
      operation.budget = Timer(budget, () => _cancel(operation, 'TIMEOUT'));
      operation.started = operation.running = true;
      _run(operation).ignore();
    }
    return {'operationId': operation.id, 'state': 'running'};
  }

  void release(TrustProbeReservation reservation) {
    if (!identical(reservation._service, this)) return;
    final operation = reservation._operation;
    operation.interests.remove(reservation._interest);
    if (!operation.started &&
        !operation.completed &&
        operation.interests.isEmpty)
      _retire(operation);
  }

  ProfileRecord _profile(String id) {
    _ready();
    final value = store.trustedOperational.foundation.foundation.profiles[id];
    if (value == null) throw StateError('NOT_FOUND');
    return value;
  }

  Map<String, Object?> get(
    TrustedSessionRequest request,
    Map<String, Object?> params,
  ) {
    requireOwner(request, 'servers.trust.get');
    final input = captureHostTrustParams(request.method, params);
    final profile = _profile(input['profileId'] as String);
    return captureHostTrustResult(request.method, {
      'profileId': profile.id,
      'profileRevision': profile.revision,
      'connectionRevision': profile.connectionRevision,
      'credentialRevision': profile.credentialRevision,
      'trustRevision': profile.trustRevision,
      'trust': store.trustedOperational.foundation.trust[profile.id]
          ?.toPublicJson(),
    });
  }

  _TrustProbe _find(
    TrustedSessionRequest request,
    Map<String, Object?> params,
  ) {
    requireOwner(request, request.method);
    final input = captureHostTrustParams(request.method, params);
    _sweep();
    final operation = _operations[input['operationId']];
    if (operation == null ||
        operation.retired ||
        operation.session != request.sessionId ||
        (operation.completed && operation.result == null))
      throw StateError('NOT_FOUND');
    return operation;
  }

  Map<String, Object?> status(
    TrustedSessionRequest request,
    Map<String, Object?> params,
  ) {
    requireOwner(request, 'servers.trust.probeStatus');
    final operation = _find(request, params);
    return captureHostTrustResult(
      request.method,
      operation.result ?? {'operationId': operation.id, 'state': 'running'},
    );
  }

  Map<String, Object?> cancel(
    TrustedSessionRequest request,
    Map<String, Object?> params,
  ) {
    requireOwner(request, 'servers.trust.probeCancel');
    final operation = _find(request, params);
    final changed =
        !operation.cancelled &&
        (!operation.completed || operation.challenge != null);
    if (changed) _cancel(operation, 'CANCELLED');
    return {'operationId': operation.id, 'cancelled': changed};
  }

  void _check(_TrustProbe operation) {
    _ready();
    if (operation.retired || operation.cancelled) throw StateError('CANCELLED');
    operation.context!.remaining;
    final captured = operation.captured!, current = _profile(operation.profile);
    if (current.revision != captured.revision ||
        current.connectionRevision != captured.connectionRevision ||
        current.credentialRevision != captured.credentialRevision ||
        current.trustRevision != captured.trustRevision)
      throw StateError('REVISION_CONFLICT');
  }

  Future<void> _run(_TrustProbe operation) async {
    final context = operation.context!;
    try {
      await context.revalidate();
      _check(operation);
      final value = operation.captured!.toJson();
      SshEndpoint endpoint;
      try {
        endpoint = SshEndpoint(
          value['address'] as String,
          value['port'] as int,
          value['sshUser'] as String,
        );
      } on SshTransportFailure {
        throw StateError('UNSUPPORTED');
      }
      final attempt = operation.attempt = transports.probe(endpoint);
      final key = await attempt.result;
      await attempt.settled;
      _check(operation);
      await context.revalidate();
      _check(operation);
      final expires = DateTime.fromMillisecondsSinceEpoch(
        _wall().toUtc().millisecondsSinceEpoch,
        isUtc: true,
      ).add(const Duration(seconds: 300));
      final challenge = HostTrustChallenge.fromJson({
        'challengeId': _uuid(),
        'profileId': operation.profile,
        'expectedRevision': operation.revision,
        'connectionRevision': operation.captured!.connectionRevision,
        'credentialRevision': operation.captured!.credentialRevision,
        'trustRevision': operation.captured!.trustRevision,
        'key': key.toJson(),
        'expiresAt': expires.toIso8601String(),
      });
      _check(operation);
      operation.challenge = challenge;
      operation.challengeExpiry = _now + const Duration(seconds: 300);
      _terminal(operation, {
        'operationId': operation.id,
        'state': 'succeeded',
        'challenge': challenge.toJson(),
      });
    } catch (error) {
      if (!operation.retired && operation.result == null)
        _failure(operation, _code(error));
    } finally {
      operation.budget?.cancel();
      await operation.attempt?.settled;
      await context.settled;
      operation.running = false;
      if (!operation.done.isCompleted) operation.done.complete();
      _sweep();
    }
  }

  String _code(Object error) => error is SshTransportFailure
      ? TrustedLocalError.fromTransport(error.code).code
      : error is StateError && TrustedLocalError.codes.contains(error.message)
      ? error.message
      : 'INTERNAL';
  void _terminal(_TrustProbe operation, Map<String, Object?> value) {
    operation.completed = true;
    operation.result = captureHostTrustResult(
      'servers.trust.probeStatus',
      value,
    );
    operation.resultExpiry = _now + const Duration(seconds: 60);
    _sweep();
  }

  void _failure(_TrustProbe operation, String code) => _terminal(operation, {
    'operationId': operation.id,
    'state': 'failed',
    'code': code,
  });
  void _cancel(_TrustProbe operation, String code) {
    operation.cancelled = true;
    operation.challenge = null;
    operation.challengeExpiry = null;
    operation.attempt?.cancel();
    if (!operation.retired && operation.result == null)
      _failure(operation, code);
    _sweep();
  }

  void _retire(_TrustProbe operation) {
    operation.retired = true;
    operation.challenge = null;
    operation.result = null;
    operation.resultExpiry = operation.challengeExpiry = null;
    operation.timer?.cancel();
    operation.budget?.cancel();
    operation.attempt?.cancel();
    if (!operation.running && identical(_operations[operation.id], operation))
      _operations.remove(operation.id);
  }

  void _detach(String session) {
    for (final operation in _operations.values.toList()) {
      if (operation.session == session) _retire(operation);
    }
  }

  void _sweep() {
    final now = _now;
    for (final operation in _operations.values.toList()) {
      operation.timer?.cancel();
      if (operation.retired) {
        if (!operation.running) _operations.remove(operation.id);
        continue;
      }
      if (operation.resultExpiry != null && now >= operation.resultExpiry!) {
        operation.result = null;
        operation.resultExpiry = null;
      }
      if (operation.challengeExpiry != null &&
          now >= operation.challengeExpiry!) {
        operation.challenge = null;
        operation.challengeExpiry = null;
      }
      if (operation.completed &&
          !operation.running &&
          operation.result == null &&
          operation.challenge == null) {
        _operations.remove(operation.id);
        continue;
      }
      final deadlines = [
        if (operation.resultExpiry != null) operation.resultExpiry!,
        if (operation.challengeExpiry != null) operation.challengeExpiry!,
      ];
      if (deadlines.isNotEmpty) {
        final next = deadlines.reduce((a, b) => a < b ? a : b);
        operation.timer = Timer(next - now, _sweep);
      }
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _unsubscribe();
    final operations = _operations.values.toList();
    for (final operation in operations) {
      _retire(operation);
    }
    await Future.wait<void>([
      for (final operation in operations)
        if (operation.running) operation.done.future,
    ]);
    _operations.clear();
    _watch.stop();
  }

  String _uuid() {
    final random = Random.secure(), bytes = List<int>.generate(16, (_) => 0);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    bytes[6] = (bytes[6] & 15) | 0x40;
    bytes[8] = (bytes[8] & 63) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

final class TrustProbeReservation {
  TrustProbeReservation._(this._service, this._operation, this._interest);
  final HostTrustProbeService _service;
  final _TrustProbe _operation;
  final int _interest;
}

final class _TrustProbe {
  _TrustProbe(this.id, this.session, this.profile, this.revision);
  final String id, session, profile, revision;
  final interests = <int>{};
  final done = Completer<void>();
  bool started = false,
      running = false,
      completed = false,
      cancelled = false,
      retired = false;
  TrustedOwnerProbeContext? context;
  ProfileRecord? captured;
  SshAttempt<SshHostPin>? attempt;
  HostTrustChallenge? challenge;
  Duration? resultExpiry, challengeExpiry;
  Map<String, Object?>? result;
  Timer? timer, budget;
}
