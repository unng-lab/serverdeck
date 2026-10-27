import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/validation.dart';

/// Owner-isolate registry. The transport supplies its own stable channel identity.
class SessionRegistry {
  SessionRegistry({
    required this.generation,
    Duration Function()? elapsed,
    void Function(String)? onDetached,
    void Function(String)? onExpiredChannel,
    void Function()? onChanged,
  }) : _onDetached = onDetached,
       _onExpiredChannel = onExpiredChannel,
       _onChanged = onChanged {
    requireUuid(generation);
    _clock = elapsed ?? () => _watch.elapsed;
  }
  final String generation;
  final _watch = Stopwatch()..start();
  late final Duration Function() _clock;
  final void Function(String)? _onDetached;
  final void Function(String)? _onExpiredChannel;
  final void Function()? _onChanged;
  final _sessions = <String, _Session>{};
  bool _stopping = false;
  Duration? _emptyAt;
  int get count => _sessions.length;
  Duration? get emptyAt => _emptyAt;
  Duration? get nextExpiry => _sessions.isEmpty
      ? null
      : _sessions.values.map((s) => s.expires).reduce((a, b) => a < b ? a : b);

  void register(String channel, String id, Set<Capability> grants) {
    if (_stopping) throw StateError('NOT_READY');
    requireNonce(id);
    if (channel.isEmpty) throw ArgumentError('INVALID_CHANNEL');
    expire();
    if (_stopping) throw StateError('NOT_READY');
    if (_sessions.containsKey(channel) ||
        _sessions.values.any((s) => s.id == id))
      throw StateError('UNAUTHORIZED');
    if (_sessions.length >= maxSessions) throw StateError('RESOURCE_LIMIT');
    _sessions[channel] = _Session(
      id,
      Set.unmodifiable(grants),
      _clock() + sessionLease,
    );
    _emptyAt = null;
    _onChanged?.call();
    if (_stopping) throw StateError('NOT_READY');
  }

  SessionRequest begin(String channel, String id, Capability? capability) {
    if (_stopping) throw StateError('NOT_READY');
    expire();
    if (_stopping) throw StateError('NOT_READY');
    final session = _sessions[channel];
    if (session == null || session.id != id) throw StateError('UNAUTHORIZED');
    session.expires = _clock() + sessionLease;
    _onChanged?.call();
    if (_stopping) throw StateError('NOT_READY');
    if (capability != null && !session.grants.contains(capability))
      throw StateError('FORBIDDEN');
    if (session.pending >= maxPendingPerSession)
      throw StateError('RESOURCE_LIMIT');
    session.pending++;
    return SessionRequest._(() => session.pending--);
  }

  void disconnect(String channel) {
    _remove(channel, _clock());
  }

  void _remove(String channel, Duration detachedAt) {
    final session = _sessions.remove(channel);
    if (session != null) {
      if (_sessions.isEmpty) _emptyAt = detachedAt;
      _onDetached?.call(session.id);
      _onChanged?.call();
    }
  }

  void expire() {
    final now = _clock();
    final due = _sessions.entries.where((e) => now >= e.value.expires).toList()
      ..sort((a, b) => a.value.expires.compareTo(b.value.expires));
    for (final entry in due) {
      _remove(entry.key, entry.value.expires);
      _onExpiredChannel?.call(entry.key);
    }
  }

  void stop() {
    if (_stopping) return;
    _stopping = true;
    for (final channel in _sessions.keys.toList()) disconnect(channel);
    _watch.stop();
  }
}

class _Session {
  _Session(this.id, this.grants, this.expires);
  final String id;
  final Set<Capability> grants;
  Duration expires;
  int pending = 0;
}

class SessionRequest {
  SessionRequest._(this._finish);
  final void Function() _finish;
  bool _completed = false;
  void complete() {
    if (_completed) return;
    _completed = true;
    _finish();
  }
}
