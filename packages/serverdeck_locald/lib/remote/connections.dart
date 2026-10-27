import 'dart:async';

import 'package:serverdeck_protocol/connections.dart';
import 'package:serverdeck_protocol/executor.dart';
import 'package:serverdeck_protocol/automation/models.dart' show McpScope;
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../api/operational_auth.dart';
import '../storage/host_trust_models.dart';
import '../storage/key_custody.dart';
import '../storage/models.dart';
import '../storage/state_store.dart';
import 'ssh_transport.dart';

part 'executor_connections.dart';

final class ConnectionServiceFailure extends StateError {
  factory ConnectionServiceFailure(String code, {String boundary = 'local'}) {
    if (!TrustedLocalError.codes.contains(code) ||
        !const {'local', 'remote'}.contains(boundary))
      throw const FormatException('VALIDATION');
    return ConnectionServiceFailure._(code, boundary);
  }
  ConnectionServiceFailure._(super.message, this.boundary);
  final String boundary;
}

ConnectionServiceFailure _failure(Object error) {
  if (error is ConnectionServiceFailure) return error;
  if (error is SshTransportFailure) {
    return ConnectionServiceFailure(switch (error.code) {
      SshTransportCode.VALIDATION_ERROR => 'VALIDATION',
      SshTransportCode.AUTHENTICATION_FAILED => 'FORBIDDEN',
      SshTransportCode.CONNECTION_FAILED => 'SERVICE_UNAVAILABLE',
      _ => error.code.name,
    }, boundary: 'remote');
  }
  if (error is TimeoutException) return ConnectionServiceFailure('TIMEOUT');
  if (error is FormatException) return ConnectionServiceFailure('VALIDATION');
  if (error is StateError && TrustedLocalError.codes.contains(error.message))
    return ConnectionServiceFailure(error.message);
  return ConnectionServiceFailure('INTERNAL');
}

/// The single owner/MCP connection registry. Credentials and SSH remain local.
final class TrustedConnectionService {
  TrustedConnectionService({
    required this.store,
    required this.custody,
    required this.sessions,
    required this.authority,
    required this.transports,
  }) {
    if (!sessions.hasNativePublicationGate) throw StateError('NOT_READY');
    store.trustedOperational;
    _unsubscribe = sessions.onSessionDetached(_detach);
  }
  final StateStore store;
  final KeyCustody custody;
  final TrustedSessions sessions;
  final TrustedMcpAuthority authority;
  final SshTransportPool transports;
  final _watch = Stopwatch()..start();
  final _entries = <String, _ConnectionEntry>{};
  final _works = <ConnectionWork>{};
  final _readWorks = <ConnectionReadWork>{};
  final _executorWorks = <ConnectionExecutorWork>{};
  final _owners = <String, _OwnerConnect>{};
  final _retired = <void Function(String)>{};
  late final void Function() _unsubscribe;
  bool _closed = false, _poisoned = false;
  Future<void>? _closing;

  void _ready() {
    if (_closed || _poisoned) throw StateError('SERVICE_UNAVAILABLE');
    store.trustedOperational;
  }

  void requireOwner(
    TrustedSessionRequest request,
    String method, {
    bool admitted = true,
  }) {
    if (!request.belongsTo(sessions) ||
        request.role != OperationalRole.owner ||
        request.method != method ||
        admitted && !request.initialAdmissionProved)
      throw StateError('FORBIDDEN');
    _ready();
  }

  Future<void> _ownerProof(TrustedSessionRequest request) async {
    await request.revalidate().timeout(request.rpcRemaining);
    request.rpcRemaining;
    _ready();
  }

  void Function() onRetired(void Function(String) listener) {
    _retired.add(listener);
    return () => _retired.remove(listener);
  }

  void _notify(String profile) {
    for (final listener in _retired.toList()) {
      try {
        listener(profile);
      } catch (_) {
        _poisoned = true;
      }
    }
  }

  _ConnectionActor _mcp(TrustedMcpContext context, String profile) {
    if (!context.belongsTo(sessions, authority)) throw StateError('FORBIDDEN');
    context.authorize(scope: McpScope.read, serverId: profile);
    _ready();
    return _ConnectionActor.mcp(context, profile);
  }

  ConnectionWork connectMcp(TrustedMcpContext context, String profile) =>
      _connect(_mcp(context, requireUuid(profile)));
  ConnectionWork disconnectMcp(TrustedMcpContext context, String profile) {
    _ready();
    if (_works.length + _readWorks.length + _executorWorks.length >= 48)
      throw StateError('RESOURCE_LIMIT');
    final work = ConnectionWork._(
      this,
      _mcp(context, requireUuid(profile)),
      disconnect: true,
    );
    _works.add(work);
    work._run().ignore();
    return work;
  }

  ConnectionWork _connect(_ConnectionActor actor) {
    _ready();
    if (_works.length + _readWorks.length + _executorWorks.length >= 48)
      throw StateError('RESOURCE_LIMIT');
    final work = ConnectionWork._(this, actor);
    _works.add(work);
    work._run().ignore();
    return work;
  }

  Future<Map<String, Object?>> viewMcp(
    TrustedMcpContext context,
    String profile, {
    bool disconnect = false,
  }) async {
    final actor = _mcp(context, requireUuid(profile));
    try {
      await actor.proof();
      actor.authorize();
      _profile(profile, mcp: true);
      if (disconnect) _disconnect(actor.token, profile);
      final entry = _entries[profile];
      if (entry != null && entry.state != 'closing') _current(entry);
      return snapshot(profile, actor.token);
    } finally {
      await actor.settled;
    }
  }

  ConnectionReadWork readMcp(
    TrustedMcpContext context,
    String profile,
    SshReadRequest request,
  ) {
    final actor = _mcp(context, requireUuid(profile));
    if (request.source == SshReadSource.journal)
      context.authorize(scope: McpScope.logs, serverId: profile);
    if (_works.length + _readWorks.length + _executorWorks.length >= 48)
      throw StateError('RESOURCE_LIMIT');
    final readActor = _ConnectionActor.read(
      context,
      profile,
      request.source == SshReadSource.journal ? McpScope.logs : McpScope.read,
    );
    final work = ConnectionReadWork._(this, readActor, request);
    // actor creation performs current scope checks before any target lookup.
    actor.authorize();
    _readWorks.add(work);
    work._run().ignore();
    return work;
  }

  ConnectionReadWork readOwner(
    TrustedOwnerReadContext context,
    String profile,
    SshReadRequest request,
  ) {
    if (!context.belongsTo(sessions)) throw StateError('FORBIDDEN');
    _ready();
    requireUuid(profile);
    context.remaining;
    if (_works.length + _readWorks.length + _executorWorks.length >= 48)
      throw StateError('RESOURCE_LIMIT');
    final work = ConnectionReadWork._(
      this,
      _ConnectionActor.readOwner(context, profile),
      request,
    );
    _readWorks.add(work);
    work._run().ignore();
    return work;
  }

  ConnectionExecutorWork openExecutorMcp(
    TrustedMcpContext context,
    String profile, {
    McpScope scope = McpScope.read,
  }) {
    if (!context.belongsTo(sessions, authority) ||
        !const {McpScope.read, McpScope.plan, McpScope.apply}.contains(scope))
      throw StateError('FORBIDDEN');
    requireUuid(profile);
    context.authorize(scope: scope, serverId: profile);
    return _openExecutor(_ConnectionActor.executor(context, profile, scope));
  }

  ConnectionExecutorWork openExecutorOwner(
    TrustedOwnerReadContext context,
    String profile,
  ) {
    if (!context.belongsTo(sessions)) throw StateError('FORBIDDEN');
    requireUuid(profile);
    context.remaining;
    return _openExecutor(_ConnectionActor.readOwner(context, profile));
  }

  ConnectionExecutorWork openExecutorAutomationOwner(
    TrustedOwnerAutomationContext context,
    String profile, {
    required McpScope scope,
  }) {
    if (!context.belongsTo(sessions)) throw StateError('FORBIDDEN');
    requireUuid(profile);
    context.authorizeExecutorScope(scope);
    return _openExecutor(_ConnectionActor.automation(context, profile, scope));
  }

  ConnectionExecutorWork _openExecutor(_ConnectionActor actor) {
    _ready();
    if (_works.length + _readWorks.length + _executorWorks.length >= 48)
      throw StateError('RESOURCE_LIMIT');
    final work = ConnectionExecutorWork._(this, actor);
    _executorWorks.add(work);
    work._run().ignore();
    return work;
  }

  Future<Map<String, Object?>> viewOwner(
    TrustedSessionRequest request,
    String profile, {
    bool disconnect = false,
  }) async {
    requireOwner(
      request,
      disconnect ? 'servers.disconnect' : 'servers.connection',
    );
    await _ownerProof(request);
    _profile(requireUuid(profile));
    if (disconnect) _disconnect(request.connectionInterest, profile);
    final entry = _entries[profile];
    if (entry != null && entry.state != 'closing') _current(entry);
    return snapshot(profile, request.connectionInterest);
  }

  Map<String, Object?> snapshot(String profile, Object token) {
    final entry = _entries[profile];
    return ConnectionSnapshot.fromJson({
      'profileId': profile,
      'state': entry?.state ?? 'disconnected',
      'interested':
          entry != null &&
          entry.state != 'closing' &&
          (entry.attached.containsKey(token) ||
              entry.pending.any(
                (w) => identical(w.actor.token, token) && !w._stopped,
              )),
      'identity': entry?.identity.toJson(),
    }).toJson();
  }

  ProfileRecord _profile(String profile, {bool mcp = false}) {
    _ready();
    final value =
        store.trustedOperational.foundation.foundation.profiles[profile];
    if (value == null) throw StateError(mcp ? 'FORBIDDEN' : 'NOT_FOUND');
    return value;
  }

  ConnectionIdentity _identity(ProfileRecord profile) {
    final trust = store.trustedOperational.foundation.trust[profile.id];
    if (trust == null ||
        trust.status != HostTrustStatus.trusted ||
        trust.connectionRevision != profile.connectionRevision ||
        trust.revision != profile.trustRevision)
      throw StateError('TRUST_REQUIRED');
    if (profile.credentialRef == null) throw StateError('NOT_READY');
    return ConnectionIdentity.fromJson({
      'profileId': profile.id,
      'connectionRevision': profile.connectionRevision,
      'credentialRevision': profile.credentialRevision,
      'trustRevision': profile.trustRevision,
      'key': trust.key.toJson(),
    });
  }

  static bool _same(ConnectionIdentity a, ConnectionIdentity b) =>
      a.profileId == b.profileId &&
      a.connectionRevision == b.connectionRevision &&
      a.credentialRevision == b.credentialRevision &&
      a.trustRevision == b.trustRevision &&
      a.key == b.key;
  void _current(_ConnectionEntry entry) {
    _ready();
    if (entry.state == 'closing' ||
        !identical(_entries[entry.profile.id], entry) ||
        !_same(entry.identity, _identity(_profile(entry.profile.id))))
      throw StateError('TRUST_CHANGED');
  }

  /// Current target comparison only; the owner/job adapter owns native proof.
  void requireCurrentIdentity(ConnectionIdentity identity) {
    _ready();
    if (!_same(identity, _identity(_profile(identity.profileId))))
      throw StateError('TRUST_CHANGED');
  }

  _ConnectionEntry _join(ConnectionWork work) {
    final actor = work.actor;
    actor.authorize();
    final profile = _profile(actor.profile, mcp: actor.mcp != null);
    final identity = _identity(profile);
    var entry = _entries[profile.id];
    if (entry != null) {
      if (entry.state == 'closing' || !_same(entry.identity, identity))
        throw StateError('RESOURCE_LIMIT');
    } else {
      final fields = profile.toJson();
      SshEndpoint endpoint;
      try {
        endpoint = SshEndpoint(
          fields['address'] as String,
          fields['port'] as int,
          fields['sshUser'] as String,
        );
      } on SshTransportFailure {
        throw StateError('UNSUPPORTED');
      }
      final reservation = transports.reserve();
      entry = _ConnectionEntry(
        this,
        profile,
        identity,
        endpoint,
        reservation,
        actor.remaining,
      );
      _entries[profile.id] = entry;
    }
    entry.pending.add(work);
    work._entry = entry;
    entry.start();
    return entry;
  }

  void _disconnect(Object token, String profile) {
    final entry = _entries[profile];
    if (entry == null) return;
    entry.attached.remove(token);
    for (final work in entry.reads.toList())
      if (identical(work.actor.token, token)) work.stop('CANCELLED');
    for (final work in entry.executors.toList())
      if (identical(work.actor.token, token)) work.stop('CANCELLED');
    for (final work in entry.pending.toList()) {
      if (identical(work.actor.token, token)) work.stop('CANCELLED');
    }
    entry.unused();
  }

  void _detach(String session) {
    for (final op in _owners.values.toList()) {
      if (op.session == session) {
        op.retired = true;
        op.work?.stop('CANCELLED');
      }
    }
    for (final work in _works.toList()) {
      if (work.actor.session == session) work.stop('CANCELLED');
    }
    for (final work in _readWorks.toList())
      if (work.actor.session == session) work.stop('CANCELLED');
    for (final work in _executorWorks.toList())
      if (work.actor.session == session) work.stop('CANCELLED');
    for (final entry in _entries.values.toList()) {
      entry.attached.removeWhere((_, id) => id == session);
      entry.unused();
    }
    _sweep();
  }

  void _sweep() {
    _owners.removeWhere(
      (_, op) =>
          op.settled &&
          (op.retired || op.expires != null && _watch.elapsed >= op.expires!),
    );
  }

  ConnectionReservation reserve(
    TrustedSessionRequest request,
    Map<String, Object?> params,
    String id,
  ) {
    requireOwner(request, 'servers.connect', admitted: false);
    requireUuid(id);
    final input = captureConnectionParams('servers.connect', params);
    _sweep();
    var op = _owners[id];
    if (op != null) {
      if (!identical(op.token, request.connectionInterest) || op.retired)
        throw StateError('NOT_FOUND');
      if (op.profile != input['profileId'])
        throw StateError('IDEMPOTENCY_CONFLICT');
    } else {
      if (_owners.length >= 16) throw StateError('RESOURCE_LIMIT');
      op = _OwnerConnect(
        id,
        request.sessionId,
        request.connectionInterest,
        input['profileId'] as String,
      );
      _owners[id] = op;
    }
    final interest = Object();
    op.reservations.add(interest);
    return ConnectionReservation._(this, op, interest);
  }

  Map<String, Object?> startOwner(
    TrustedSessionRequest request,
    ConnectionReservation reservation,
  ) {
    requireOwner(request, 'servers.connect');
    final op = reservation._operation;
    if (!identical(reservation._service, this) ||
        !identical(request.connectionInterest, op.token))
      throw StateError('FORBIDDEN');
    if (!identical(_owners[op.id], op) ||
        op.retired ||
        !op.reservations.contains(reservation._interest))
      throw StateError('NOT_FOUND');
    if (op.work == null) {
      final actor = _ConnectionActor.owner(
        request.ownerConnectionContext(),
        op.profile,
      );
      final work = op.work = _connect(actor);
      work.result
          .then<void>(
            (value) {
              if (!op.retired) op.result = value;
            },
            onError: (Object error, StackTrace _) {
              if (!op.retired) op.code = _failure(error).message;
            },
          )
          .whenComplete(() {
            op.expires = _watch.elapsed + const Duration(seconds: 60);
          })
          .ignore();
      work.done.then<void>((_) {
        op.settled = true;
        _sweep();
      }).ignore();
    }
    return {'operationId': op.id, 'state': 'running'};
  }

  void release(ConnectionReservation reservation) {
    if (!identical(reservation._service, this)) return;
    final op = reservation._operation;
    op.reservations.remove(reservation._interest);
    if (op.work == null && op.reservations.isEmpty) _owners.remove(op.id);
  }

  Future<Map<String, Object?>> ownerStatus(
    TrustedSessionRequest request,
    String id, {
    bool cancel = false,
  }) async {
    requireOwner(
      request,
      cancel ? 'servers.connectCancel' : 'servers.connectStatus',
    );
    await _ownerProof(request);
    _sweep();
    final op = _owners[requireUuid(id)];
    if (op == null ||
        op.retired ||
        !identical(op.token, request.connectionInterest)) {
      if (cancel) return {'operationId': id, 'cancelled': false};
      throw StateError('NOT_FOUND');
    }
    if (cancel) {
      final pending = op.result == null && op.code == null && op.work != null;
      if (pending) op.work!.stop('CANCELLED');
      return {'operationId': id, 'cancelled': pending};
    }
    if (op.result != null) {
      final entry = _entries[op.profile];
      if (entry == null || entry.state != 'connected')
        throw StateError('NOT_FOUND');
      _current(entry);
      final current = snapshot(op.profile, op.token);
      if (current['state'] != 'connected' || current['interested'] != true)
        throw StateError('NOT_FOUND');
      return {'operationId': id, 'state': 'succeeded', 'connection': current};
    }
    if (op.code != null)
      return {'operationId': id, 'state': 'failed', 'code': op.code};
    return {'operationId': id, 'state': 'running'};
  }

  /// Called under the actual reconciled target lease, outside the store queue.
  Future<T> runOwnerMutation<T>(
    TrustedSessionRequest request,
    Future<T> Function() effect,
  ) async {
    if (!const {
      'profiles.create',
      'profiles.update',
      'profiles.delete',
      'settings.update',
      'servers.trust.confirm',
      'servers.trust.revoke',
    }.contains(request.method))
      throw StateError('FORBIDDEN');
    requireOwner(request, request.method);
    final lease = await sessions.beginReconciledTargetChange(
      deadline: request.rpcRemaining,
    );
    HostTrustState? before;
    var needsReconciliation = false;
    try {
      await _ownerProof(request);
      before = store.trustedOperational.foundation;
      needsReconciliation = true;
      return await effect();
    } catch (error) {
      if (error is StateError && error.message == 'STORAGE_BLOCKED')
        needsReconciliation = true;
      rethrow;
    } finally {
      try {
        if (needsReconciliation) await reconcile(before, lease);
      } finally {
        await lease.close();
      }
    }
  }

  /// Called under the actual reconciled target lease, outside the store queue.
  Future<void> reconcile(
    HostTrustState? before,
    TrustedReconciledTargetChangeLease lease,
  ) async {
    final changed = <String>{};
    var failed = false;
    try {
      final after = store.trustedOperational.foundation;
      if (before == null) throw StateError('STORAGE_BLOCKED');
      final old = before.foundation.profiles, next = after.foundation.profiles;
      for (final id in {...old.keys, ...next.keys}) {
        final a = old[id], b = next[id];
        if (a == null ||
            b == null ||
            a.connectionRevision != b.connectionRevision ||
            a.credentialRevision != b.credentialRevision ||
            a.trustRevision != b.trustRevision)
          changed.add(id);
      }
      lease.retireAffected(changed);
    } catch (_) {
      try {
        lease.retireAll();
      } catch (_) {
        failed = true;
      }
      changed.addAll(_entries.keys);
    }
    final pending = <Future<void>>[];
    for (final work in _executorWorks.toList()) {
      if (changed.contains(work.actor.profile)) {
        work.stop('TRUST_CHANGED');
        pending.add(work.done);
      }
    }
    for (final work in _readWorks.toList()) {
      if (changed.contains(work.actor.profile)) {
        work.stop('TRUST_CHANGED');
        pending.add(work.done);
      }
    }
    for (final work in _works.toList()) {
      if (changed.contains(work.actor.profile)) {
        work.stop('TRUST_CHANGED');
        pending.add(work.done);
      }
    }
    for (final id in changed) {
      final entry = _entries[id];
      if (entry != null) {
        entry.stop();
        pending.add(entry.done);
      }
    }
    await Future.wait(pending);
    if (_poisoned || failed) throw StateError('SERVICE_UNAVAILABLE');
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    final completion = Completer<void>();
    _closing = completion.future;
    completion.future.ignore();
    _closed = true;
    _unsubscribe();
    for (final op in _owners.values) op.retired = true;
    for (final work in _works.toList()) work.stop('SERVICE_UNAVAILABLE');
    for (final work in _readWorks.toList()) work.stop('SERVICE_UNAVAILABLE');
    for (final work in _executorWorks.toList())
      work.stop('SERVICE_UNAVAILABLE');
    for (final entry in _entries.values.toList()) entry.stop();
    Future.wait<void>([
          for (final work in _readWorks.toList()) work.done,
          for (final work in _executorWorks.toList()) work.done,
          for (final work in _works.toList()) work.done,
          for (final entry in _entries.values.toList()) entry.done,
        ])
        .then<void>((_) {
          _owners.clear();
          if (_poisoned) throw StateError('SERVICE_UNAVAILABLE');
        })
        .then(
          completion.complete,
          onError: (Object _, StackTrace __) =>
              completion.completeError(StateError('SERVICE_UNAVAILABLE')),
        );
    return completion.future;
  }
}

final class ConnectionReservation {
  ConnectionReservation._(this._service, this._operation, this._interest);
  final TrustedConnectionService _service;
  final _OwnerConnect _operation;
  final Object _interest;
}

final class _OwnerConnect {
  _OwnerConnect(this.id, this.session, this.token, this.profile);
  final String id, session, profile;
  final Object token;
  final reservations = <Object>{};
  ConnectionWork? work;
  Map<String, Object?>? result;
  String? code;
  Duration? expires;
  bool retired = false, settled = false;
}

final class _ConnectionActor {
  _ConnectionActor.owner(this.owner, this.profile)
    : mcp = null,
      automationOwner = null,
      readOwner = null,
      budget = const Duration(seconds: 15),
      scope = McpScope.read;
  _ConnectionActor.mcp(this.mcp, this.profile)
    : owner = null,
      automationOwner = null,
      readOwner = null,
      budget = const Duration(seconds: 15),
      scope = McpScope.read;
  _ConnectionActor.read(this.mcp, this.profile, this.scope)
    : owner = null,
      automationOwner = null,
      readOwner = null,
      budget = const Duration(seconds: 30);
  _ConnectionActor.readOwner(this.readOwner, this.profile)
    : owner = null,
      automationOwner = null,
      mcp = null,
      scope = McpScope.read,
      budget = const Duration(seconds: 30);
  _ConnectionActor.executor(this.mcp, this.profile, this.scope)
    : owner = null,
      automationOwner = null,
      readOwner = null,
      budget = scope == McpScope.apply
          ? const Duration(hours: 2)
          : const Duration(seconds: 30);
  _ConnectionActor.automation(this.automationOwner, this.profile, this.scope)
    : owner = null,
      readOwner = null,
      mcp = null,
      budget = const Duration(hours: 2);
  final TrustedOwnerConnectionContext? owner;
  final TrustedOwnerReadContext? readOwner;
  final TrustedOwnerAutomationContext? automationOwner;
  final TrustedMcpContext? mcp;
  final String profile;
  final Duration budget;
  final McpScope scope;
  final watch = Stopwatch()..start();
  final proofs = <Future<void>>{};
  Object get token =>
      owner?.connectionInterest ??
      readOwner?.connectionInterest ??
      automationOwner?.connectionInterest ??
      mcp!.connectionInterest;
  String get session =>
      owner?.sessionId ??
      readOwner?.sessionId ??
      automationOwner?.sessionId ??
      mcp!.sessionId;
  Duration get remaining {
    final left =
        owner?.remaining ??
        readOwner?.remaining ??
        automationOwner?.remaining ??
        budget - watch.elapsed;
    if (left <= Duration.zero) throw StateError('TIMEOUT');
    return left;
  }

  void authorize() {
    remaining;
    mcp?.authorize(scope: scope, serverId: profile);
    automationOwner?.authorizeExecutorScope(scope);
  }

  Future<void> proof() async {
    authorize();
    if (owner != null) {
      await owner!.revalidate();
    } else if (readOwner != null) {
      await readOwner!.revalidate();
    } else if (automationOwner != null) {
      await automationOwner!.revalidate();
    } else {
      final left = remaining;
      await mcp!.revalidate(
        deadline: left < const Duration(seconds: 5)
            ? left
            : const Duration(seconds: 5),
        observeNativeCompletion: (actual) {
          final tracked = actual.then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {},
          );
          proofs.add(tracked);
          tracked.whenComplete(() => proofs.remove(tracked)).ignore();
        },
      );
    }
    authorize();
  }

  Future<void> get settled => Future.wait<void>([
    if (owner != null) owner!.settled,
    if (readOwner != null) readOwner!.settled,
    if (automationOwner != null) automationOwner!.settled,
    ...proofs,
  ]);
}

final class ConnectionWork {
  ConnectionWork._(this._service, this.actor, {this.disconnect = false}) {
    _result.future.ignore();
  }
  final TrustedConnectionService _service;
  final _ConnectionActor actor;
  final bool disconnect;
  final _result = Completer<Map<String, Object?>>(), _done = Completer<void>();
  _ConnectionEntry? _entry;
  bool _stopped = false;
  Future<Map<String, Object?>> get result => _result.future;
  Future<void> get done => _done.future;
  void _live() {
    if (_stopped) throw StateError('CANCELLED');
    actor.authorize();
    _service._ready();
  }

  void stop(String code, {String boundary = 'local'}) {
    if (_result.isCompleted) return;
    _stopped = true;
    _result.completeError(
      ConnectionServiceFailure(
        code,
        boundary: code == 'TIMEOUT' && _entry?.attempt != null
            ? 'remote'
            : boundary,
      ),
    );
    _entry?.pending.remove(this);
    _entry?.unused();
  }

  Future<void> cancelInterest() {
    stop('CANCELLED');
    return done;
  }

  Future<void> _run() async {
    Timer? timer;
    try {
      timer = Timer(actor.remaining, () => stop('TIMEOUT'));
      await actor.proof();
      _live();
      if (disconnect) {
        _service._profile(actor.profile, mcp: actor.mcp != null);
        _service._disconnect(actor.token, actor.profile);
        _result.complete(_service.snapshot(actor.profile, actor.token));
        return;
      }
      final entry = _service._join(this);
      await entry.ready.timeout(actor.remaining);
      _live();
      await actor.proof();
      _live();
      _service._current(entry);
      entry.attached[actor.token] = actor.session;
      entry.pending.remove(this);
      _result.complete(_service.snapshot(actor.profile, actor.token));
    } catch (error) {
      if (!_result.isCompleted) _result.completeError(_failure(error));
    } finally {
      timer?.cancel();
      final entry = _entry;
      entry?.pending.remove(this);
      entry?.unused();
      if (entry != null) {
        await entry.setupDone;
        if (entry.state == 'closing') await entry.done;
      }
      await actor.settled;
      _service._works.remove(this);
      _done.complete();
    }
  }
}

final class _ConnectionEntry {
  _ConnectionEntry(
    this.service,
    this.profile,
    this.identity,
    this.endpoint,
    this.reservation,
    this.budget,
  ) {
    _ready.future.ignore();
  }
  final TrustedConnectionService service;
  final ProfileRecord profile;
  final ConnectionIdentity identity;
  final SshEndpoint endpoint;
  final SshTransportReservation reservation;
  final Duration budget;
  final watch = Stopwatch()..start();
  final pending = <ConnectionWork>{};
  final reads = <ConnectionReadWork>{};
  final executors = <ConnectionExecutorWork>{};
  final attached = <Object, String>{};
  final _ready = Completer<void>(),
      _setup = Completer<void>(),
      _done = Completer<void>();
  Future<void> get ready => _ready.future;
  Future<void> get setupDone => _setup.future;
  Future<void> get done => _done.future;
  SshAttempt<SshLease>? attempt;
  SshLease? lease;
  String state = 'connecting';
  bool _started = false;
  Future<void>? _closing;
  Duration get remaining {
    final left = budget - watch.elapsed;
    if (left <= Duration.zero) throw StateError('TIMEOUT');
    return left;
  }

  ConnectionWork get active {
    service._current(this);
    return pending.firstWhere(
      (w) => !w._stopped,
      orElse: () => throw StateError('CANCELLED'),
    );
  }

  void start() {
    if (!_started) {
      _started = true;
      _run().ignore();
    }
  }

  void unused() {
    if (pending.isEmpty && attached.isEmpty) stop();
  }

  void stop({String code = 'CANCELLED', String boundary = 'local'}) {
    if (state == 'closing') return;
    state = 'closing';
    attached.clear();
    for (final work in reads.toList()) work.stop(code);
    for (final work in executors.toList()) work.stop(code);
    for (final work in pending.toList()) work.stop(code, boundary: boundary);
    if (!_ready.isCompleted) _ready.completeError(StateError('CANCELLED'));
    attempt?.cancel();
    service._notify(profile.id);
    _closing = _close();
    _closing!.ignore();
  }

  Future<void> _run() async {
    Map<String, Object?>? clear;
    try {
      await _proveActive();
      active;
      final state = service.store.trustedOperational.foundation.foundation;
      final credential = state.credentials[profile.credentialRef];
      if (credential == null) throw StateError('NOT_READY');
      clear = await service.custody.openCredential(
        credential.protectedBlob,
        state.workspaceId,
        profile.id,
        credential.id,
      );
      await _proveActive();
      active;
      remaining;
      final secret = clear['kind'] == 'password'
          ? SshCredential.password(clear['password'] as String)
          : SshCredential.privateKey(
              clear['privateKey'] as String,
              passphrase: clear['passphrase'] as String?,
            );
      clear.clear();
      clear = null;
      final connecting = attempt = reservation.connect(
        endpoint,
        identity.key,
        secret,
        deadline: remaining,
      );
      lease = await connecting.result;
      active;
      service._current(this);
      remaining;
      this.state = 'connected';
      _ready.complete();
      lease!.done.then<void>((_) => stop()).ignore();
    } catch (error) {
      if (!_ready.isCompleted) _ready.completeError(_failure(error));
      final failure = _failure(error);
      stop(code: failure.message, boundary: failure.boundary);
    } finally {
      clear?.clear();
      _setup.complete();
    }
  }

  Future<void> _proveActive() async {
    while (true) {
      remaining;
      final work = active;
      try {
        await work.actor.proof();
        if (!work._stopped) {
          active;
          return;
        }
      } catch (error) {
        work.stop(_failure(error).message);
      }
    }
  }

  Future<void> _close() async {
    try {
      await setupDone;
      await lease?.close();
      await attempt?.settled;
      await Future.wait([for (final read in reads.toList()) read.done]);
      await Future.wait([
        for (final executor in executors.toList()) executor.done,
      ]);
    } catch (_) {
      service._poisoned = true;
    } finally {
      reservation.close();
      if (identical(service._entries[profile.id], this))
        service._entries.remove(profile.id);
      _done.complete();
    }
  }
}

final class ConnectionReadValue {
  ConnectionReadValue._(this.identity, this.output);
  final ConnectionIdentity identity;
  final SshReadOutput output;
}

/// A bounded typed read owned by the actual client/target, never a raw channel.
final class ConnectionReadWork {
  ConnectionReadWork._(this.service, this.actor, this.request) {
    _result.future.ignore();
  }
  final TrustedConnectionService service;
  final _ConnectionActor actor;
  final SshReadRequest request;
  final _result = Completer<ConnectionReadValue>(), _done = Completer<void>();
  _ConnectionEntry? _entry;
  SshAttempt<SshReadOutput>? _attempt;
  bool _stopped = false;
  Future<ConnectionReadValue> get result => _result.future;
  Future<void> get done => _done.future;
  void stop(String code) {
    if (_result.isCompleted) return;
    _stopped = true;
    _attempt?.cancel();
    _result.completeError(
      ConnectionServiceFailure(
        code,
        boundary: _attempt == null ? 'local' : 'remote',
      ),
    );
  }

  Future<void> cancelInterest() {
    stop('CANCELLED');
    return done;
  }

  void _live() {
    if (_stopped) throw StateError('CANCELLED');
    actor.authorize();
    service._ready();
  }

  Future<void> _run() async {
    Timer? timer;
    try {
      timer = Timer(actor.remaining, () => stop('TIMEOUT'));
      await actor.proof();
      _live();
      service._profile(actor.profile, mcp: actor.mcp != null);
      final entry = _entry = service._entries[actor.profile];
      if (entry == null ||
          entry.state != 'connected' ||
          !entry.attached.containsKey(actor.token))
        throw StateError('NOT_READY');
      service._current(entry);
      entry.reads.add(this);
      final attempt = _attempt = entry.lease!.read(
        request,
        deadline: actor.remaining,
      );
      final output = await attempt.result;
      await actor.proof();
      _live();
      service._current(entry);
      if (!entry.attached.containsKey(actor.token))
        throw StateError('NOT_READY');
      _result.complete(ConnectionReadValue._(entry.identity, output));
    } catch (error) {
      if (!_result.isCompleted) _result.completeError(_failure(error));
    } finally {
      timer?.cancel();
      _attempt?.cancel();
      await _attempt?.settled;
      await actor.settled;
      _entry?.reads.remove(this);
      service._readWorks.remove(this);
      _done.complete();
    }
  }
}
