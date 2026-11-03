import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../connections/connection_owner.dart';
import '../domain/actor.dart';
import '../domain/app_operations.dart';
import '../domain/canonical_state.dart';
import '../domain/models.dart';
import '../runtime/capability.dart';
import '../runtime/owned_work.dart';
import '../storage/domain_repository.dart';
import '../storage/records.dart';

abstract interface class GrantTransport {
  Future<void> setEnabled(bool enabled);
  Future<void> closeClient(String clientId);
  Future<void> writeGrant(
    String clientId,
    int version,
    Uint8List protectedSecret,
  );
  Future<void> deleteGrant(String clientId);
}

final class GrantInfo {
  const GrantInfo({
    required this.clientId,
    required this.name,
    required this.version,
    required this.expiresAt,
    required this.revoked,
    required this.exportPending,
    required this.cleanupRequired,
    required this.clockRollback,
  });
  final String clientId, name;
  final int version, expiresAt;
  final bool revoked, exportPending, cleanupRequired, clockRollback;
}

final class McpConfiguration {
  const McpConfiguration(this.command, this.clientId);
  final String command, clientId;
  List<String> get args => ['--mcp-stdio', '--client', clientId];
  Map<String, Object> toJson() => {
    'mcpServers': {
      'serverdeck': {'command': command, 'args': args},
    },
  };
}

final class GrantOwner
    implements CanonicalGrantAuthorization, RuntimeCapability {
  GrantOwner({
    required this.repository,
    required this.actors,
    required this.getGate,
    required this.connections,
    required this.transport,
    required this.protect,
    required this.unprotect,
    required this.newId,
    required this.utcNow,
    required this.userSid,
    required this.logonSid,
    required this.exePath,
    Uint8List Function()? randomSecret,
    ScheduleOwnedDeadline? schedule,
  }) : _random = randomSecret ?? _secret,
       _schedule = schedule ?? _timer;
  static const lifetimeMs = 90 * 24 * 60 * 60 * 1000;
  final DomainRepository repository;
  final ActorAuthority actors;
  final DomainCommandGate Function() getGate;
  final ConnectionOwner connections;
  final GrantTransport transport;
  final Future<Uint8List> Function(Uint8List, String) protect, unprotect;
  final String Function() newId;
  final int Function() utcNow;
  final String userSid, logonSid, exePath;
  final Uint8List Function() _random;
  final ScheduleOwnedDeadline _schedule;
  final _quarantine = <String>{},
      _closures = <String, Future<void>>{},
      _work = <Future<void>>{};
  bool _stopped = false, _clockFailed = false, _transportReady = false;
  void Function()? _cancelReceiptCleanup;
  void Function()? _cancelExpiry;
  final _expiredVersions = <String, int>{};
  Future<void>? _disabling;
  int _guardSerial = 0, _appliedGuard = 0;
  @override
  String get id => 'mcp-grants';
  static Uint8List _secret() {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
  }

  static void Function() _timer(Duration d, void Function() callback) {
    final t = Timer(d, callback);
    return t.cancel;
  }

  void transportReady(bool ready) => _transportReady = ready && !_stopped;
  bool get enabled => repository.read((r) => r.settings.mcpEnabled);
  String _purpose(String id) => 'mcp-grant.v1:$id';
  String _id() {
    final value = newId();
    if (!isCanonicalUuid(value))
      throw const OperationFailure(FailureCode.storageUnavailable);
    return value;
  }

  void _admit() {
    if (_stopped) throw const OperationFailure(FailureCode.shuttingDown);
  }

  int _advance(DomainTransaction r) {
    final s = r.settings;
    s.dataRevision = nextRevision(s.dataRevision);
    r.putSettings(s);
    return s.dataRevision;
  }

  GrantInfo _view(McpGrant g, SecurityState s) => GrantInfo(
    clientId: g.clientId,
    name: g.name,
    version: g.grantVersion,
    expiresAt: g.expiresAt,
    revoked: g.revokedAt != null,
    exportPending: g.exportPending,
    cleanupRequired: _quarantine.contains(g.clientId),
    clockRollback: g.authorizationEpoch != s.authorizationEpoch,
  );
  McpGrant _grant(DomainRead r, String clientId) {
    if (!isCanonicalUuid(clientId))
      throw const OperationFailure(
        FailureCode.invalidArgument,
        field: OperationField.clientId,
      );
    final g = r.grant(clientId);
    if (g == null) throw const OperationFailure(FailureCode.accessRevoked);
    if (g.grantVersion < 1 ||
        g.grantVersion > 9007199254740991 ||
        g.protectedSecret.isEmpty ||
        g.protectedSecret.length > 8192 ||
        g.ownerUserSid != userSid)
      throw const OperationFailure(FailureCode.storageUnavailable);
    return g;
  }

  Future<void> _guard() async {
    _admit();
    final serial = ++_guardSerial;
    List<String> obsolete = [];
    try {
      await repository.write((r) {
        final s = r.security, now = utcNow();
        if (s.authorizationEpoch < 1 ||
            s.authorizationEpoch >= 9007199254740991 ||
            now.abs() > 9007199254740991 - lifetimeMs)
          throw const OperationFailure(FailureCode.storageUnavailable);
        if (now < s.minimumClockUtc) {
          s.authorizationEpoch = nextRevision(s.authorizationEpoch);
          s.lastClockRollbackAt = now;
          obsolete = r
              .grants()
              .where((g) => g.authorizationEpoch != s.authorizationEpoch)
              .map((g) => g.clientId)
              .toList();
        }
        s.minimumClockUtc = now;
        s.lastAuthorizationUtc = now;
        r.putSecurity(s);
        _advance(r);
      });
      if (serial >= _appliedGuard) {
        _appliedGuard = serial;
        _clockFailed = false;
      }
      for (final id in obsolete) {
        _quarantine.add(id);
        _owned(_close(id)).catchError((Object _) {}).ignore();
      }
      _scheduleExpiry();
    } catch (_) {
      if (serial >= _appliedGuard) {
        _appliedGuard = serial;
        _clockFailed = true;
      }
      throw const OperationFailure(
        FailureCode.storageUnavailable,
        retryable: true,
      );
    }
  }

  @override
  Future<void> authorize(McpActor actor, AuthorizationPoint point) async {
    await _guard();
    isAuthorizedNow(actor);
  }

  @override
  bool isAuthorizedNow(McpActor actor) {
    _admit();
    if (actor.requestCancelled)
      throw const OperationFailure(FailureCode.conflict);
    if (!actors.owns(actor))
      throw const OperationFailure(FailureCode.authRequired);
    return repository.read((r) {
      final s = r.security, g = _grant(r, actor.clientId), now = utcNow();
      if (_clockFailed)
        throw const OperationFailure(
          FailureCode.storageUnavailable,
          retryable: true,
        );
      if (now < s.minimumClockUtc ||
          g.authorizationEpoch != s.authorizationEpoch)
        throw const OperationFailure(
          FailureCode.accessRevoked,
          reason: FailureReason.clockRollback,
        );
      if (!r.settings.mcpEnabled ||
          !_transportReady ||
          g.revokedAt != null ||
          g.grantVersion != actor.grantVersion)
        throw const OperationFailure(FailureCode.accessRevoked);
      if (g.expiresAt <= now) {
        _requestExpiry(g.clientId, g.grantVersion);
        throw const OperationFailure(FailureCode.grantExpired);
      }
      if (_quarantine.contains(g.clientId)) throw _cleanup;
      if (g.exportPending)
        throw const OperationFailure(FailureCode.authRequired);
      return true;
    });
  }

  Future<McpActor> authenticate(
    String clientId,
    int version,
    Uint8List proof, {
    required String peerUserSid,
    required String peerLogonSid,
  }) => _owned(
    _authenticate(clientId, version, proof, peerUserSid, peerLogonSid),
  );
  Future<McpActor> _authenticate(
    String clientId,
    int version,
    Uint8List proof,
    String sid,
    String logon,
  ) async {
    Uint8List? plain, cipher;
    final offered = Uint8List.fromList(proof);
    try {
      if (sid != userSid || logon != logonSid || offered.length != 32)
        throw const OperationFailure(FailureCode.authRequired);
      await _guard();
      final actor = actors.mcp(clientId: clientId, grantVersion: version);
      isAuthorizedNow(actor);
      cipher = repository.read(
        (r) => Uint8List.fromList(_grant(r, clientId).protectedSecret),
      );
      plain = await unprotect(cipher!, _purpose(clientId));
      var diff = plain.length ^ offered.length;
      for (var i = 0; i < 32; i++) {
        diff |= (i < plain.length ? plain[i] : 0) ^ offered[i];
      }
      if (diff != 0) throw const OperationFailure(FailureCode.authRequired);
      await _guard();
      isAuthorizedNow(actor);
      final same = repository.read((r) {
        final now = _grant(r, clientId).protectedSecret;
        if (now.length != cipher!.length) return false;
        var d = 0;
        for (var i = 0; i < now.length; i++) {
          d |= now[i] ^ cipher[i];
        }
        return d == 0;
      });
      if (!same) throw const OperationFailure(FailureCode.authRequired);
      return actor;
    } catch (_) {
      throw const OperationFailure(FailureCode.authRequired);
    } finally {
      offered.fillRange(0, offered.length, 0);
      plain?.fillRange(0, plain.length, 0);
      cipher?.fillRange(0, cipher.length, 0);
    }
  }

  Future<List<GrantInfo>> list(UiActor actor) => _owned(
    getGate().prepare(actor, (ctx) async {
      await _guard();
      return ctx.read(
        () => repository.read(
          (r) => r.grants().map((g) => _view(g, r.security)).toList(),
        ),
      );
    }),
  );
  int expiry(McpActor actor) {
    isAuthorizedNow(actor);
    return repository.read((r) => _grant(r, actor.clientId).expiresAt);
  }

  Future<GrantInfo> issue(
    UiActor actor,
    String name, {
    required bool confirmed,
  }) => _owned(_issue(actor, name, confirmed));
  Future<GrantInfo> _issue(UiActor actor, String name, bool confirmed) async {
    final label = name.trim();
    await getGate().prepare(actor, (ctx) {
      _admit();
      if (!confirmed ||
          !isWellFormedUnicode(label) ||
          label.isEmpty ||
          label.runes.length > 100)
        throw const OperationFailure(
          FailureCode.invalidArgument,
          field: OperationField.request,
        );
    });
    final client = _id();
    final cipher = await _protected(client);
    try {
      await getGate().prepare(actor, (ctx) async {
        await _guard();
        await repository.write(
          (r) => ctx.linearize(() {
            if (r.grant(client) != null)
              throw const OperationFailure(FailureCode.conflict);
            final g = McpGrant()
              ..clientId = client
              ..name = label
              ..ownerUserSid = userSid
              ..protectedSecret = List.of(cipher)
              ..createdAt = utcNow()
              ..expiresAt = utcNow() + lifetimeMs
              ..authorizationEpoch = r.security.authorizationEpoch
              ..exportPending = true;
            r.putGrant(g);
            _advance(r);
            return MutationValue(entityId: client, revision: 1);
          }),
        );
      });
      _scheduleExpiry();
      await _reconcile(client, actor);
      return _info(client);
    } finally {
      cipher.fillRange(0, cipher.length, 0);
    }
  }

  Future<Uint8List> _protected(String client) async {
    final secret = _random();
    Uint8List? cipher;
    try {
      if (secret.length != 32)
        throw const OperationFailure(FailureCode.protectionUnavailable);
      cipher = await protect(secret, _purpose(client));
      if (cipher.isEmpty || cipher.length > 8192)
        throw const OperationFailure(FailureCode.protectionUnavailable);
      return Uint8List.fromList(cipher);
    } catch (_) {
      throw const OperationFailure(FailureCode.protectionUnavailable);
    } finally {
      secret.fillRange(0, secret.length, 0);
      cipher?.fillRange(0, cipher.length, 0);
    }
  }

  Future<GrantInfo> rotate(
    UiActor actor,
    String clientId, {
    required bool confirmed,
  }) => _owned(_rotate(actor, clientId, confirmed));
  Future<GrantInfo> _rotate(
    UiActor actor,
    String clientId,
    bool confirmed,
  ) async {
    final before = await getGate().prepare(actor, (ctx) async {
      _admit();
      if (!confirmed) throw const OperationFailure(FailureCode.invalidArgument);
      await _guard();
      return ctx.read(
        () => repository.read((r) {
          final g = _grant(r, clientId);
          if (g.revokedAt != null)
            throw const OperationFailure(FailureCode.accessRevoked);
          return (
            g.grantVersion,
            g.exportPending || _quarantine.contains(clientId),
          );
        }),
      );
    });
    if (before.$2) {
      await _reconcile(clientId, actor);
      return _info(clientId);
    }
    final cipher = await _protected(clientId);
    try {
      await getGate().prepare(actor, (ctx) async {
        await _guard();
        await repository.write(
          (r) => ctx.linearize(() {
            final g = _grant(r, clientId);
            if (g.revokedAt != null ||
                g.grantVersion != before.$1 ||
                g.exportPending)
              throw const OperationFailure(FailureCode.conflict);
            g.grantVersion = nextRevision(g.grantVersion);
            g.authorizationEpoch = r.security.authorizationEpoch;
            g.protectedSecret = List.of(cipher);
            g.expiresAt = utcNow() + lifetimeMs;
            g.exportPending = true;
            r.putGrant(g);
            _advance(r);
            return MutationValue(entityId: clientId, revision: g.grantVersion);
          }),
        );
      });
      _quarantine.add(clientId);
      _scheduleExpiry();
      await _reconcile(clientId, actor);
      return _info(clientId);
    } finally {
      cipher.fillRange(0, cipher.length, 0);
    }
  }

  Future<GrantInfo> revoke(
    UiActor actor,
    String clientId, {
    required bool confirmed,
  }) => _owned(_revoke(actor, clientId, confirmed));
  Future<GrantInfo> _revoke(
    UiActor actor,
    String clientId,
    bool confirmed,
  ) async {
    await getGate().prepare(actor, (ctx) async {
      _admit();
      if (!confirmed) throw const OperationFailure(FailureCode.invalidArgument);
      await repository.write(
        (r) => ctx.linearize(() {
          final g = _grant(r, clientId);
          if (g.revokedAt == null) {
            g.revokedAt = utcNow();
            g.grantVersion = nextRevision(g.grantVersion);
            g.exportPending = false;
            r.putGrant(g);
            _advance(r);
          }
          return MutationValue(entityId: clientId, revision: g.grantVersion);
        }),
      );
    });
    _quarantine.add(clientId);
    _scheduleExpiry();
    await _reconcile(clientId, actor);
    return _info(clientId);
  }

  GrantInfo _info(String id) =>
      repository.read((r) => _view(_grant(r, id), r.security));
  Future<McpConfiguration> configuration(UiActor actor, String clientId) =>
      _owned(
        getGate().prepare(
          actor,
          (ctx) => ctx.read(
            () => repository.read((r) {
              final g = _grant(r, clientId);
              if (g.revokedAt != null ||
                  g.exportPending ||
                  _quarantine.contains(clientId))
                throw _cleanup;
              if (g.expiresAt <= utcNow() ||
                  g.authorizationEpoch != r.security.authorizationEpoch)
                throw const OperationFailure(FailureCode.accessRevoked);
              return McpConfiguration(exePath, clientId);
            }),
          ),
        ),
      );
  Future<void> retry(UiActor actor, String clientId) =>
      _owned(_retry(actor, clientId));
  Future<void> _retry(UiActor actor, String clientId) async {
    await getGate().prepare(
      actor,
      (ctx) => ctx.read(() => repository.read((r) => _grant(r, clientId))),
    );
    await _reconcile(clientId, actor);
  }

  static const _cleanup = OperationFailure(
    FailureCode.cleanupRequired,
    retryable: true,
    reason: FailureReason.grantCleanup,
  );
  Future<void> _bounded(Future<void> work) async {
    final result = Completer<void>();
    final cancel = _schedule(const Duration(seconds: 5), () {
      if (!result.isCompleted) result.completeError(_cleanup);
    });
    work
        .then(
          (_) {
            if (!result.isCompleted) result.complete();
          },
          onError: (Object _, StackTrace __) {
            if (!result.isCompleted) result.completeError(_cleanup);
          },
        )
        .ignore();
    try {
      await result.future;
    } finally {
      cancel();
    }
  }

  Future<void> _close(String clientId) async {
    _quarantine.add(clientId);
    final work = _closures.putIfAbsent(clientId, () {
      final job = Future.wait([
        transport.closeClient(clientId),
        connections.cancelPendingClient(clientId),
      ]).then<void>((_) {});
      job
          .then(
            (_) {
              _closures.remove(clientId);
              _quarantine.remove(clientId);
            },
            onError: (Object _, StackTrace __) {
              _closures.remove(clientId);
            },
          )
          .ignore();
      return job;
    });
    await _bounded(work);
  }

  Future<void> _reconcile(String clientId, UiActor? actor) async {
    await _close(clientId);
    final g = repository.read((r) => _grant(r, clientId));
    if (g.revokedAt != null) {
      try {
        await transport.deleteGrant(clientId);
      } catch (_) {}
      _quarantine.remove(clientId);
      return;
    }
    final cipher = Uint8List.fromList(g.protectedSecret);
    try {
      await transport.writeGrant(clientId, g.grantVersion, cipher);
    } catch (_) {
      throw const OperationFailure(
        FailureCode.storageUnavailable,
        retryable: true,
      );
    } finally {
      cipher.fillRange(0, cipher.length, 0);
    }
    void commit(DomainTransaction r) {
      final current = _grant(r, clientId);
      if (current.grantVersion != g.grantVersion || current.revokedAt != null)
        throw const OperationFailure(FailureCode.conflict);
      current.exportPending = false;
      r.putGrant(current);
      _advance(r);
    }

    if (actor == null) {
      await repository.write((r) {
        commit(r);
      });
    } else {
      await getGate().prepare(
        actor,
        (ctx) => repository.write(
          (r) => ctx.linearize(() {
            commit(r);
            return MutationValue(entityId: clientId, revision: g.grantVersion);
          }),
        ),
      );
    }
    _quarantine.remove(clientId);
  }

  Future<void> initialize() async {
    await _guard();
    for (final g in repository.read((r) => r.grants())) {
      if (g.exportPending || g.revokedAt != null)
        await _reconcile(g.clientId, null);
    }
    await repository.write((r) {
      r.pruneExpiredReceipts(utcNow());
    });
    _scheduleReceiptCleanup();
    _scheduleExpiry();
  }

  /// Grant lifetime is owned here, including after the initiating pipe has EOF.
  /// The queued denial/cleanup work never waits for resource acknowledgments in
  /// an authorization or transaction phase. Canonical time/version is rechecked.
  void _requestExpiry(String clientId, int version) {
    if (_stopped || _expiredVersions[clientId] == version) return;
    _expiredVersions[clientId] = version;
    _owned(
      Future<void>(() async {
        if (_stopped) return;
        final current = repository.read((r) => r.grant(clientId));
        if (current == null ||
            current.grantVersion != version ||
            current.expiresAt > utcNow())
          return;
        await _close(clientId);
      }),
    ).ignore();
  }

  Future<void> expireClient(String clientId, int version) async {
    if (_stopped) return;
    final current = repository.read((r) => r.grant(clientId));
    if (current == null || current.grantVersion != version) return;
    if (current.expiresAt > utcNow()) {
      _scheduleExpiry();
      return;
    }
    _requestExpiry(clientId, version);
  }

  void _scheduleExpiry() {
    _cancelExpiry?.call();
    _cancelExpiry = null;
    if (_stopped) return;
    final now = utcNow();
    int? earliest;
    for (final grant in repository.read((r) => r.grants())) {
      if (grant.revokedAt != null) continue;
      if (grant.expiresAt <= now) {
        _requestExpiry(grant.clientId, grant.grantVersion);
        continue;
      }
      if (earliest == null || grant.expiresAt < earliest)
        earliest = grant.expiresAt;
    }
    if (earliest != null)
      _cancelExpiry = _schedule(Duration(milliseconds: earliest - now), () {
        _cancelExpiry = null;
        if (!_stopped) _scheduleExpiry();
      });
  }

  void _scheduleReceiptCleanup() {
    _cancelReceiptCleanup?.call();
    if (_stopped) return;
    _cancelReceiptCleanup = _schedule(const Duration(hours: 1), () {
      if (_stopped) return;
      final work = repository
          .write((r) {
            if (!_stopped) r.pruneExpiredReceipts(utcNow());
          })
          .then<void>((_) {}, onError: (Object _, StackTrace __) {});
      _owned(
        work.whenComplete(() {
          if (!_stopped) _scheduleReceiptCleanup();
        }),
      ).ignore();
    });
  }

  Future<void> setEnabled(UiActor actor, bool value) =>
      _owned(_setEnabled(actor, value));
  Future<void> _setEnabled(UiActor actor, bool value) async {
    await getGate().prepare(
      actor,
      (ctx) => repository.write(
        (r) => ctx.linearize(() {
          final s = r.settings;
          s.mcpEnabled = value;
          s.settingsRevision = nextRevision(s.settingsRevision);
          s.dataRevision = nextRevision(s.dataRevision);
          r.putSettings(s);
          return const ConnectionView(state: ConnectionState.disconnected);
        }),
      ),
    );
    _transportReady = false;
    if (!value) {
      await _settle([
        for (final g in repository.read((r) => r.grants())) _close(g.clientId),
        _disableTransport(),
      ]);
      return;
    }
    if (_disabling != null) await _bounded(_disabling!);
    await transport.setEnabled(value);
    _transportReady = value;
  }

  Future<void> _disableTransport() {
    final work = _disabling ??= transport.setEnabled(false);
    work
        .then(
          (_) {
            if (identical(_disabling, work)) _disabling = null;
          },
          onError: (Object _, StackTrace __) {
            if (identical(_disabling, work)) _disabling = null;
          },
        )
        .ignore();
    return _bounded(work);
  }

  Future<void> _settle(List<Future<void>> work) async {
    Object? error;
    StackTrace? stack;
    await Future.wait(
      work.map((future) async {
        try {
          await future;
        } catch (e, s) {
          error ??= e;
          stack ??= s;
        }
      }),
    );
    if (error != null) Error.throwWithStackTrace(error!, stack!);
  }

  Future<T> _owned<T>(Future<T> work) {
    final done = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _work.add(done);
    done.whenComplete(() => _work.remove(done)).ignore();
    return work;
  }

  @override
  Future<void> stopAdmission() async {
    _stopped = true;
    _transportReady = false;
    _cancelReceiptCleanup?.call();
    _cancelReceiptCleanup = null;
    _cancelExpiry?.call();
    _cancelExpiry = null;
  }

  @override
  Future<void> cancelPending() async {
    await _settle([
      for (final g in repository.read((r) => r.grants())) _close(g.clientId),
    ]);
  }

  @override
  Future<void> closeSessions() async {
    await _disableTransport();
  }

  @override
  Future<void> drain() async {
    while (_work.isNotEmpty || _closures.isNotEmpty || _disabling != null) {
      await _settle([
        ..._work,
        ..._closures.values,
        if (_disabling != null) _disabling!,
      ]);
    }
  }

  @override
  Future<void> dispose() async {
    await stopAdmission();
    await cancelPending();
    await closeSessions();
    await drain();
  }
}
