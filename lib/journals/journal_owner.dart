import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/actor.dart';
import '../domain/models.dart';
import '../runtime/capability.dart';
import '../runtime/owned_work.dart';
import '../storage/domain_repository.dart';
import '../storage/records.dart';
import 'journal_models.dart';
import 'journal_port.dart';
import 'journal_protocol.dart';

/// Sole journal scheduler/storage owner. UI receives detached local projections.
final class JournalsOwner implements Listenable, RuntimeCapability {
  JournalsOwner({
    required this.repository,
    required this.actor,
    required this.connections,
    required this.newId,
    required this.utcNow,
    Duration Function()? monotonicNow,
    ScheduleOwnedDeadline? schedule,
  }) : _monotonic = monotonicNow,
       _schedule = schedule ?? _timer;
  final DomainRepository repository;
  final UiActor actor;
  final JournalConnectionPort connections;
  final String Function() newId;
  final int Function() utcNow;
  final Duration Function()? _monotonic;
  final ScheduleOwnedDeadline _schedule;
  final _clock = Stopwatch()..start(), _notifier = _JournalNotifier();
  final _status = <String, JournalStatus>{}, _epoch = <String, int>{};
  final _jobs = <String, (_JournalWork, String)>{};
  final _discovery = <String, _JournalWork>{};
  final _sessions = <String, String>{};
  final _due = <String, Duration>{}, _discoveryDue = <String, Duration>{};
  final _resetCursor = <String>{}, _metadataRecovery = <String>{};
  final _pending = <Future<void>>{};
  final _services = <String, List<String>>{},
      _serviceStates = <String, JournalStatus>{};
  final _serviceRevisions = <String, int>{};
  Map<String, List<String>> get services => _currentDiscovery(_services);
  Map<String, JournalStatus> get serviceStates =>
      _currentDiscovery(_serviceStates);
  Map<String, T> _currentDiscovery<T>(Map<String, T> projection) {
    try {
      return repository.read(
        (r) => Map<String, T>.unmodifiable({
          for (final entry in projection.entries)
            if (r.profile(entry.key) != null &&
                r.profile(entry.key)?.connectionRevision ==
                    _serviceRevisions[entry.key])
              entry.key: entry.value,
        }),
      );
    } catch (_) {
      error = JournalStatus.storageError;
      return {};
    }
  }

  StreamSubscription<void>? _subscription;
  void Function()? _cancelTick;
  void Function()? _cancelExpiry;
  Future<void>? _refresh, _disposal;
  int _highWater = 0, _round = 0;
  Duration _highWaterMono = Duration.zero;
  String? _retrySource;
  bool _started = false, _stopped = false, _disposed = false;
  JournalStatus? error;
  int get retainedSourceStates => {
    ..._status.keys,
    ..._epoch.keys,
    ..._sessions.keys,
    ..._due.keys,
    ..._resetCursor,
    ..._metadataRecovery,
  }.length;
  @override
  String get id => 'journals';
  Duration get _now => _monotonic?.call() ?? _clock.elapsed;
  int get now {
    final mono = _now, elapsed = (mono - _highWaterMono).inMilliseconds;
    final floor = _highWater + (elapsed > 0 ? elapsed : 0);
    final current = utcNow();
    if (current > floor) {
      _highWater = current;
      _highWaterMono = mono;
      return current;
    }
    return floor;
  }

  void _observeUtc(int value) {
    final elapsed = (_now - _highWaterMono).inMilliseconds;
    if (value > _highWater + (elapsed > 0 ? elapsed : 0)) {
      _highWater = value;
      _highWaterMono = _now;
    }
  }

  static void Function() _timer(Duration d, void Function() f) {
    final t = Timer(d, f);
    return t.cancel;
  }

  @override
  void addListener(VoidCallback f) => _notifier.addListener(f);
  @override
  void removeListener(VoidCallback f) => _notifier.removeListener(f);
  void _notify() {
    if (!_disposed) _notifier.changed();
  }

  void _track(Future<void> work) {
    _pending.add(work);
    work
        .then(
          (_) => _pending.remove(work),
          onError: (Object _, StackTrace __) => _pending.remove(work),
        )
        .ignore();
  }

  Future<void> start() async {
    if (_started || _stopped) return;
    _started = true;
    _subscription = connections.changes.listen((_) {
      if (_stopped) return;
      try {
        for (final pair in List.of(_jobs.entries)) {
          final source = _source(pair.key);
          final c = source == null ? null : _connection(source.profileId);
          if (source == null ||
              c?.sessionId != pair.value.$2 ||
              c?.state != ConnectionState.connected)
            _invalidate(pair.key);
        }
      } catch (_) {
        error = JournalStatus.storageError;
      }
      _notify();
    });
    await _prune();
    _arm();
  }

  void _arm() {
    if (_stopped || _cancelTick != null) return;
    _cancelTick = _schedule(const Duration(seconds: 5), () {
      _cancelTick = null;
      unawaited(reconcile());
      _arm();
    });
  }

  /// Notify at the nearest expiry outside the retained tail or file fragment.
  /// UI reads filter before asynchronous physical pruning completes.
  void _armExpiry() {
    _cancelExpiry?.call();
    _cancelExpiry = null;
    if (_stopped) return;
    try {
      final at = now;
      int? nearest;
      repository.read((r) {
        for (final source in r.journalSources()) {
          if (r.profile(source.profileId)?.connectionRevision !=
              source.connectionRevision)
            continue;
          JournalPayload p;
          try {
            p = JournalPayload.decode(source.payload);
          } catch (_) {
            continue;
          }
          for (final receipt in [
            for (final e in (List<JournalEntry>.of(
              p.entries,
            )..sort(compareJournalEntries)).skip(journalTailLines))
              e.receivedAt,
            if (p.checkpoint['fragmentAt'] is int)
              p.checkpoint['fragmentAt'] as int,
          ]) {
            final expiry = receipt + 3600000;
            if (expiry > at && (nearest == null || expiry < nearest!))
              nearest = expiry;
          }
        }
      });
      if (nearest == null) return;
      _cancelExpiry = _schedule(Duration(milliseconds: nearest! - at), () {
        _cancelExpiry = null;
        if (_stopped) return;
        _notify();
        final work = _prune().then((_) => _notify());
        _track(work);
      });
    } catch (_) {
      error = JournalStatus.storageError;
    }
  }

  JournalSource? _source(String id) =>
      repository.read((r) => r.journalSource(id));
  List<JournalSource> sources(String profileId) {
    try {
      return repository.read((r) {
        final revision = r.profile(profileId)?.connectionRevision;
        return r
            .journalSources()
            .where(
              (s) =>
                  s.profileId == profileId && s.connectionRevision == revision,
            )
            .toList();
      });
    } catch (_) {
      error = JournalStatus.storageError;
      return [];
    }
  }

  JournalPayload payload(String id) {
    final source = _source(id);
    if (source == null) return JournalPayload();
    final p = JournalPayload.decode(source.payload);
    for (final e in p.entries) {
      _observeUtc(e.receivedAt);
    }
    return p;
  }

  List<JournalEntry> entries(String id) {
    try {
      final p = payload(id), at = now;
      return retainedJournalEntries(p.entries, at);
    } catch (_) {
      _status[id] = JournalStatus.storageError;
      return [];
    }
  }

  ConnectionView _connection(String id) {
    try {
      return connections.connection(id);
    } catch (_) {
      return const ConnectionView(state: ConnectionState.disconnected);
    }
  }

  JournalStatus status(JournalSource source) {
    if (error == JournalStatus.storageError) return error!;
    if (!source.enabled || _stopped) return JournalStatus.paused;
    if (_connection(source.profileId).state != ConnectionState.connected)
      return JournalStatus.disconnected;
    if (!_jobs.containsKey(source.sourceId) &&
        _now >= (_due[source.sourceId] ?? Duration.zero))
      return JournalStatus.waiting;
    return _status[source.sourceId] ?? JournalStatus.waiting;
  }

  void _ensureOpen() {
    if (_stopped) throw StateError('Сбор журналов завершён');
  }

  Future<String> add(
    String profileId,
    JournalKind kind,
    String target,
    String name,
  ) => _add(profileId, kind, target, name);

  Future<String> ensureService(
    String profileId,
    String unit, {
    required int connectionRevision,
  }) => _add(
    profileId,
    JournalKind.journal,
    unit,
    String.fromCharCodes(unit.runes.take(80)),
    expectedRevision: connectionRevision,
    reuse: true,
  );

  Future<String> _add(
    String profileId,
    JournalKind kind,
    String target,
    String name, {
    int? expectedRevision,
    bool reuse = false,
  }) async {
    _ensureOpen();
    validateJournalTarget(kind, target);
    final label = validateJournalName(name);
    late String id;
    await repository.write((r) {
      _ensureOpen();
      final profile = r.profile(profileId);
      if (profile == null) throw StateError('Сервер больше не существует');
      if (expectedRevision != null &&
          profile.connectionRevision != expectedRevision) {
        throw StateError('Контекст сервера изменился');
      }
      final all = r.journalSources();
      if (reuse) {
        for (final source in all) {
          if (source.profileId == profileId &&
              source.kind == kind.name &&
              source.target == target) {
            id = source.sourceId;
            return;
          }
        }
      }
      if (all.length >= 1024 ||
          all.where((s) => s.profileId == profileId).length >= 16)
        throw StateError('Достигнут предел источников журналов');
      if (all.any(
        (s) =>
            s.profileId == profileId &&
            s.kind == kind.name &&
            s.target == target,
      ))
        throw ArgumentError('Источник уже добавлен');
      id = newId();
      r.putJournalSource(
        JournalSource()
          ..sourceId = id
          ..profileId = profileId
          ..connectionRevision = profile.connectionRevision
          ..kind = kind.name
          ..target = target
          ..name = label,
      );
    });
    _notify();
    return id;
  }

  void _invalidate(String id) {
    _epoch[id] = (_epoch[id] ?? 0) + 1;
    final work = _jobs[id]?.$1;
    if (work != null) _status[id] = JournalStatus.waiting;
    work?.cancellation.cancel();
    work?.job.cancel();
  }

  void _forget(String id) {
    if (_retrySource == id) _retrySource = null;
    _status.remove(id);
    _epoch.remove(id);
    _sessions.remove(id);
    _due.remove(id);
    _resetCursor.remove(id);
    _metadataRecovery.remove(id);
  }

  Future<void> _change(
    String id,
    void Function(JournalSource) effect, {
    bool remove = false,
    bool resetSession = false,
  }) async {
    _ensureOpen();
    _invalidate(id);
    await repository.write((r) {
      _ensureOpen();
      final source = r.journalSource(id);
      if (source == null) throw StateError('Источник больше не существует');
      if (remove) {
        r.deleteJournalSource(id);
      } else {
        effect(source);
        r.putJournalSource(source);
      }
    });
    if (resetSession || remove) {
      _sessions.remove(id);
      _resetCursor.remove(id);
      _metadataRecovery.remove(id);
    }
    if (remove) {
      _forget(id);
    }
    _armExpiry();
    _notify();
  }

  Future<void> rename(String id, String name) {
    final label = validateJournalName(name);
    return _change(id, (s) => s.name = label);
  }

  Future<void> setEnabled(String id, bool enabled) =>
      _change(id, (s) => s.enabled = enabled, resetSession: true);
  Future<void> deleteSource(String id) => _change(id, (_) {}, remove: true);
  Future<void> retry(String id) async {
    _ensureOpen(); // cooldown also applies to manual retry
    if (_source(id) == null) throw StateError('Источник больше не существует');
    _retrySource = id;
    await reconcile();
  }

  Future<void> discover(String profileId) async {
    _ensureOpen();
    if (_discovery.containsKey(profileId) ||
        _jobs.values.any(
          (w) => _source(w.$1.sourceId)?.profileId == profileId,
        ) ||
        _now < (_discoveryDue[profileId] ?? Duration.zero))
      return;
    final profile = repository.read((r) => r.profile(profileId)),
        c = _connection(profileId);
    if (profile != null) {
      if (_serviceRevisions[profileId] != profile.connectionRevision) {
        _services.remove(profileId);
        _serviceStates.remove(profileId);
      }
      _serviceRevisions[profileId] = profile.connectionRevision;
    }
    if (profile == null ||
        c.state != ConnectionState.connected ||
        c.sessionId == null) {
      _serviceStates[profileId] = JournalStatus.disconnected;
      _notify();
      return;
    }
    _discoveryDue[profileId] = _now + const Duration(seconds: 5);
    _serviceStates[profileId] = JournalStatus.loading;
    _notify();
    final cancellation = WorkCancellation();
    final job = connections.beginJournal(
      actor,
      profileId,
      c.sessionId!,
      expectedConnectionRevision: profile.connectionRevision,
      request: const JournalRequest.discover(),
      cancellation: cancellation,
    );
    final work = _JournalWork('', job, cancellation);
    _discovery[profileId] = work;
    Future<void> run() async {
      try {
        final reply = await job.result;
        if (_stopped ||
            cancellation.isCancelled ||
            _connection(profileId).sessionId != c.sessionId ||
            repository.read((r) => r.profile(profileId)?.connectionRevision) !=
                profile.connectionRevision)
          return;
        if (reply.failure == null)
          _services[profileId] = List.unmodifiable(reply.units);
        _serviceStates[profileId] =
            reply.failure ??
            (reply.partial
                ? JournalStatus.partial
                : reply.units.isEmpty
                ? JournalStatus.empty
                : JournalStatus.ready);
      } catch (_) {
        if (!_stopped) _serviceStates[profileId] = JournalStatus.unavailable;
      } finally {
        _discovery.remove(profileId);
        _notify();
      }
    }

    final future = run();
    _track(future);
    await future;
  }

  Future<void> reconcile() {
    if (!_started || _stopped) return Future.value();
    if (_refresh != null) return _refresh!;
    final work = _reconcile()
        .catchError((Object _) {
          error = JournalStatus.storageError;
          _notify();
        })
        .whenComplete(() => _refresh = null);
    _refresh = work;
    _track(work);
    return work;
  }

  Future<void> _reconcile() async {
    await _prune();
    if (_stopped) return;
    final all = repository.read((r) => r.journalSources());
    if (all.isEmpty) return;
    final busyProfiles = <String>{..._discovery.keys};
    for (final work in _jobs.values) {
      final s = _source(work.$1.sourceId);
      if (s != null) busyProfiles.add(s.profileId);
    }
    final ordered = [
      ...all.skip(_round % all.length),
      ...all.take(_round % all.length),
    ];
    final retry = _retrySource;
    if (retry != null) {
      final i = ordered.indexWhere((s) => s.sourceId == retry);
      if (i > 0) ordered.insert(0, ordered.removeAt(i));
    }
    _round = (_round + 1) % all.length;
    final started = <Future<void>>[];
    for (final source in ordered) {
      if (_stopped || _jobs.length + _discovery.length >= 4) break;
      if (!source.enabled ||
          _jobs.containsKey(source.sourceId) ||
          busyProfiles.contains(source.profileId) ||
          _now < (_due[source.sourceId] ?? Duration.zero))
        continue;
      final c = _connection(source.profileId);
      if (c.state != ConnectionState.connected || c.sessionId == null) continue;
      busyProfiles.add(source.profileId);
      if (_retrySource == source.sourceId) _retrySource = null;
      started.add(_collect(source, c.sessionId!));
    }
    await Future.wait(started);
    _notify();
  }

  Future<void> _collect(JournalSource source, String session) async {
    final id = source.sourceId, epoch = _epoch[source.sourceId] ?? 0;
    _due[id] = _now + const Duration(seconds: 5);
    _status[id] = JournalStatus.loading;
    _notify();
    try {
      final payload = JournalPayload.decode(source.payload),
          fresh = _sessions[id] != session;
      final isFile = source.kind == 'file';
      final request = isFile
          ? JournalRequest.file(
              source.target,
              identity: fresh
                  ? null
                  : payload.checkpoint['identity'] as String?,
              offset: fresh ? 0 : payload.checkpoint['offset'] as int? ?? 0,
            )
          : JournalRequest.journal(
              source.target,
              cursor: fresh || _resetCursor.contains(id)
                  ? null
                  : payload.checkpoint['cursor'] as String?,
              metadataRecovery: _metadataRecovery.contains(id),
            );
      final cancellation = WorkCancellation();
      final job = connections.beginJournal(
        actor,
        source.profileId,
        session,
        expectedConnectionRevision: source.connectionRevision,
        request: request,
        cancellation: cancellation,
      );
      final work = _JournalWork(id, job, cancellation);
      _jobs[id] = (work, session);
      final reply = await job.result;
      bool current() =>
          !_stopped &&
          !cancellation.isCancelled &&
          (_epoch[id] ?? 0) == epoch &&
          _connection(source.profileId).state == ConnectionState.connected &&
          _connection(source.profileId).sessionId == session;
      if (!current()) return;
      if (reply.failure != null) {
        _status[id] = reply.failure!;
        if (reply.cursorRejected) _resetCursor.add(id);
        if (reply.failure == JournalStatus.outputLimit && !isFile)
          _metadataRecovery.add(id);
        return;
      }
      final at = now;
      final committed = await repository.write((r) {
        final saved = r.journalSource(id),
            profile = r.profile(source.profileId);
        if (!current() ||
            saved == null ||
            !saved.enabled ||
            saved.connectionRevision != source.connectionRevision ||
            profile?.connectionRevision != source.connectionRevision)
          return false;
        final endpoint = r.endpoint(profile!.endpointId);
        if (endpoint?.acceptedKeyBytes == null || endpoint!.changed)
          return false;
        final p = JournalPayload.decode(saved.payload);
        p.partial =
            p.partial || reply.partial || fresh || _resetCursor.contains(id);
        if (isFile) {
          if (fresh) {
            final seq = p.checkpoint['sequence'];
            p.checkpoint.clear();
            if (seq != null) p.checkpoint['sequence'] = seq;
          }
          applyFileReply(p, reply, id, at);
        } else {
          final known = p.entries.map((e) => e.id).toSet();
          for (final event in reply.events) {
            if (known.add(event.id)) p.entries.add(event.received(at));
          }
          p.checkpoint['cursor'] = reply.cursor ?? p.checkpoint['cursor'];
          if (reply.cursor == null &&
              (_resetCursor.contains(id) || _metadataRecovery.contains(id)))
            p.checkpoint.remove('cursor');
        }
        saved.payload = p.encode();
        r.putJournalSource(saved);
        _pruneRecords(r, pending: {id: p});
        return true;
      });
      if (!current() || !committed) return;
      _sessions[id] = session;
      _resetCursor.remove(id);
      _metadataRecovery.remove(id);
      final p = this.payload(id);
      _status[id] = p.partial
          ? JournalStatus.partial
          : p.entries.isEmpty
          ? JournalStatus.empty
          : JournalStatus.ready;
    } catch (_) {
      if (!_stopped) _status[id] = JournalStatus.storageError;
    } finally {
      _jobs.remove(id);
      try {
        if (_source(id) == null) _forget(id);
      } catch (_) {}
      _armExpiry();
      _notify();
    }
  }

  void _pruneRecords(
    DomainTransaction r, {
    Map<String, JournalPayload> pending = const {},
  }) {
    final values = <String, (JournalSource, JournalPayload)>{};
    final sources = r.journalSources();
    final ids = sources
        .where((s) => r.profile(s.profileId) != null)
        .map((s) => s.sourceId)
        .toSet();
    for (final id in {
      ..._status.keys,
      ..._epoch.keys,
      ..._sessions.keys,
      ..._due.keys,
      ..._resetCursor,
      ..._metadataRecovery,
    }) {
      if (!ids.contains(id)) {
        _invalidate(id);
        _forget(id);
      }
    }
    for (final id in {
      ..._services.keys,
      ..._serviceStates.keys,
      ..._discoveryDue.keys,
      ..._serviceRevisions.keys,
    }) {
      if (r.profile(id) == null ||
          r.profile(id)?.connectionRevision != _serviceRevisions[id]) {
        _services.remove(id);
        _serviceStates.remove(id);
        _serviceRevisions.remove(id);
        _discoveryDue.remove(id);
        _discovery[id]?.cancellation.cancel();
        _discovery[id]?.job.cancel();
      }
    }
    for (final source in sources) {
      final profile = r.profile(source.profileId);
      if (profile == null) {
        r.deleteJournalSource(source.sourceId);
        continue;
      }
      if (profile.connectionRevision != source.connectionRevision) continue;
      try {
        final p =
            pending[source.sourceId] ?? JournalPayload.decode(source.payload);
        final fragmentAt = p.checkpoint['fragmentAt'] as int?;
        if (fragmentAt != null) _observeUtc(fragmentAt);
        for (final e in p.entries) {
          _observeUtc(e.receivedAt);
        }
        values[source.sourceId] = (source, p);
      } catch (_) {
        _status[source.sourceId] = JournalStatus.storageError;
      }
    }
    final at = now, all = <_PruneEntry>[];
    for (final item in values.values) {
      final fragmentAt = item.$2.checkpoint['fragmentAt'] as int?;
      if (fragmentAt != null && fragmentAt <= at - 3600000) {
        item.$2.checkpoint.remove('fragment');
        item.$2.checkpoint.remove('fragmentAt');
        item.$2.checkpoint['discard'] = true;
        item.$2.partial = true;
      }
      final retained = retainedJournalEntries(item.$2.entries, at);
      item.$2.entries
        ..clear()
        ..addAll(retained);
      for (final event in item.$2.entries) {
        all.add(
          _PruneEntry(item.$1, item.$2, event, utf8.encode(event.text).length),
        );
      }
    }
    all.sort((a, b) {
      final c = a.event.receivedAt.compareTo(b.event.receivedAt);
      return c != 0 ? c : a.event.id.compareTo(b.event.id);
    });
    final counts = <String, int>{}, sizes = <String, int>{};
    for (final e in all) {
      counts.update(e.source.profileId, (n) => n + 1, ifAbsent: () => 1);
      sizes.update(
        e.source.profileId,
        (n) => n + e.bytes,
        ifAbsent: () => e.bytes,
      );
    }
    final remaining = <_PruneEntry>[];
    for (final e in all) {
      final id = e.source.profileId;
      if (counts[id]! > 10000 || sizes[id]! > 8 * 1024 * 1024) {
        e.payload.entries.remove(e.event);
        e.payload.partial = true;
        counts[id] = counts[id]! - 1;
        sizes[id] = sizes[id]! - e.bytes;
      } else {
        remaining.add(e);
      }
    }
    var total = remaining.fold<int>(0, (n, e) => n + e.bytes),
        count = remaining.length;
    for (final e in remaining) {
      if (count <= 50000 && total <= 32 * 1024 * 1024) break;
      e.payload.entries.remove(e.event);
      e.payload.partial = true;
      count--;
      total -= e.bytes;
    }
    for (final value in values.values) {
      final encoded = value.$2.encode();
      if (encoded != value.$1.payload) {
        value.$1.payload = encoded;
        r.putJournalSource(value.$1);
      }
    }
  }

  Future<void> _prune() async {
    if (_stopped) return;
    try {
      await repository.write((r) {
        if (!_stopped) _pruneRecords(r);
      });
      error = null;
      _armExpiry();
    } catch (_) {
      error = JournalStatus.storageError;
    }
  }

  @override
  Future<void> stopAdmission() async {
    _stopped = true;
    _cancelTick?.call();
    _cancelTick = null;
    _cancelExpiry?.call();
    _cancelExpiry = null;
    for (final key in List.of(_jobs.keys)) {
      _invalidate(key);
    }
    for (final w in _discovery.values) {
      w.cancellation.cancel();
      w.job.cancel();
    }
  }

  @override
  Future<void> cancelPending() => stopAdmission();
  @override
  Future<void> closeSessions() => stopAdmission();
  @override
  Future<void> drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(List.of(_pending));
    }
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    await stopAdmission();
    await _subscription?.cancel();
    await drain();
    _status.clear();
    _epoch.clear();
    _sessions.clear();
    _due.clear();
    _resetCursor.clear();
    _metadataRecovery.clear();
    _services.clear();
    _serviceStates.clear();
    _serviceRevisions.clear();
    _discoveryDue.clear();
    _disposed = true;
    _clock.stop();
    _notifier.dispose();
  }
}

final class _JournalWork {
  const _JournalWork(this.sourceId, this.job, this.cancellation);
  final String sourceId;
  final JournalJob job;
  final WorkCancellation cancellation;
}

final class _PruneEntry {
  const _PruneEntry(this.source, this.payload, this.event, this.bytes);
  final JournalSource source;
  final JournalPayload payload;
  final JournalEntry event;
  final int bytes;
}

final class _JournalNotifier extends ChangeNotifier {
  void changed() => notifyListeners();
}
