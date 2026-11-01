import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/executor_recipes.dart';
import 'package:serverdeck_protocol/mcp/operations.dart' show mcpDomainCodes;
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_engine/platform/verified_release.dart';
import 'package:serverdeck_engine/platform/ports.dart'
    show EngineClock, SystemEngineClock;

import '../hosting/sessions.dart';

import 'package:serverdeck_engine/automation/configuration.dart';

import 'connections.dart';
import 'executor.dart';
import 'direct_ssh.dart';
import 'direct_ssh_observations.dart';
import 'owned_drain.dart';

import 'package:serverdeck_engine/remote/observations.dart';
import 'package:serverdeck_engine/remote/ssh_transport.dart';

const remoteReadTools = {
  'serverdeck_servers_list',
  'serverdeck_server_get',
  'serverdeck_state_get',
  'serverdeck_configuration_get',
  'serverdeck_logs_read',
  'serverdeck_recipes_list',
};

/// Shared private observations and bounded journals. No raw logs enter Isar.
final class RemoteReadService {
  RemoteReadService(
    this.connections, {
    VerifiedExecutorRelease? executorRelease,
    EngineClock? clock,
  }) : clock = clock ?? SystemEngineClock(),
       executors = RemoteExecutorService(
         connections,
         release: executorRelease,
       ) {
    _unsubscribe = connections.onRetired(_retireTarget);
    _unsubscribeSession = connections.sessions.onSessionDetached(_detach);
  }
  final TrustedConnectionService connections;
  final RemoteExecutorService executors;
  final _managed = <String, ManagedResourceObservationRecord>{};
  final _managedStale = <String>{};
  final EngineClock clock;
  final _codec = StrictCodec();
  final _key = SecretKeyData(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    overwriteWhenDestroyed: true,
  );
  final _cursors = <String, _ReadCursor>{};
  final _cache = <String, _ServerCache>{};
  final _rings = <String, _JournalRing>{};
  final _work = <RemoteReadWork>{};
  final _refreshes = <String, _SharedRefresh>{};
  late final void Function() _unsubscribe, _unsubscribeSession;
  bool _closed = false, _paused = false, _pauseDrained = false;
  Future<void>? _closing, _pausing;
  void _ready() {
    if (_closed || _paused) throw StateError('SERVICE_UNAVAILABLE');
    connections.store.snapshot;
  }

  RemoteReadWork startMcp(
    TrustedMcpContext context,
    String tool,
    Map<String, Object?> args,
  ) {
    if (!context.belongsTo(connections.sessions, connections.authority))
      throw StateError('FORBIDDEN');
    final actor = _ReadActor.mcp(context);
    actor.authorize(tool, args['serverId']);
    return _start(actor, tool, args);
  }

  RemoteReadWork startOwner(
    TrustedOwnerReadContext context,
    String tool,
    Map<String, Object?> args,
  ) {
    if (!context.belongsTo(connections.sessions)) throw StateError('FORBIDDEN');
    if (!const {
      'serverdeck_state_get',
      'serverdeck_configuration_get',
      'serverdeck_logs_read',
      'owner_executor_inspect',
      'serverdeck_recipes_list',
    }.contains(tool))
      throw StateError('FORBIDDEN');
    return _start(_ReadActor.owner(context), tool, args);
  }

  RemoteReadWork _start(
    _ReadActor actor,
    String tool,
    Map<String, Object?> args,
  ) {
    _ready();
    if (!remoteReadTools.contains(tool) &&
        !(actor.owner != null && tool == 'owner_executor_inspect'))
      throw StateError('UNSUPPORTED');
    if (_work.length >= 48 ||
        _work.where((w) => identical(w.actor.token, actor.token)).length >= 16)
      throw StateError('RESOURCE_LIMIT');
    final captured = _codec.decode(
      _codec.encode(args, maxBytes: 8192),
      maxBytes: 8192,
    );
    final work = RemoteReadWork._(this, actor, tool, captured);
    _work.add(work);
    work._run().ignore();
    return work;
  }

  void _retireTarget(String profile) {
    // Cache invalidation needs only committed foundation presence, never grant
    // authority. A queued job-state write may temporarily hide the automation
    // snapshot while this synchronous retirement notification is delivered.
    final current = connections.store.state.profiles;
    if (!current.containsKey(profile)) {
      _managed.removeWhere((_, value) => value.serverId == profile);
      _managedStale.removeWhere((key) => key.startsWith('$profile/'));
      _cache.remove(profile);
      _rings.remove(profile);
    } else {
      _cache[profile]?.stale = true;
      _rings[profile]?.stale = true;
      _managedStale.addAll(
        _managed.entries
            .where((entry) => entry.value.serverId == profile)
            .map((entry) => entry.key),
      );
    }
    _cursors.removeWhere((_, c) => c.profile == profile);
    for (final work in _work.toList())
      if (work.args['serverId'] == profile) work.stop('TRUST_CHANGED');
  }

  void _detach(String session) {
    _cursors.removeWhere((_, cursor) => cursor.session == session);
    for (final work in _work.toList())
      if (work.actor.session == session) work.stop('CANCELLED');
  }

  void _sweep() => _cursors.removeWhere((_, c) => clock.elapsed >= c.expires);
  String _cursor(_ReadCursor value) {
    _sweep();
    if (_cursors.length >= 128) throw StateError('RESOURCE_LIMIT');
    final total = _cursors.values.fold<int>(0, (n, c) => n + c.bytes);
    if (total + value.bytes > 8 * 1024 * 1024)
      throw StateError('RESOURCE_LIMIT');
    final id = base64Url
        .encode(List<int>.generate(32, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
    final mac = DartHmac.sha256()
        .calculateMacSync(utf8.encode(id), secretKeyData: _key, nonce: const [])
        .bytes;
    _cursors[id] = value;
    return '$id.${base64Url.encode(mac).replaceAll('=', '')}';
  }

  _ReadCursor _decodeCursor(Object? token, RemoteReadWork work, String filter) {
    _sweep();
    if (token is! String || token.length > 512)
      throw StateError('CURSOR_EXPIRED');
    final parts = token.split('.');
    if (parts.length != 2) throw StateError('CURSOR_EXPIRED');
    try {
      final supplied = base64Url.decode('${parts[1]}='),
          expected = DartHmac.sha256()
              .calculateMacSync(
                utf8.encode(parts[0]),
                secretKeyData: _key,
                nonce: const [],
              )
              .bytes;
      if (supplied.length != 32) throw const FormatException();
      var difference = 0;
      for (var i = 0; i < 32; i++) difference |= supplied[i] ^ expected[i];
      if (difference != 0) throw const FormatException();
    } catch (_) {
      throw StateError('CURSOR_EXPIRED');
    }
    final cursor = _cursors[parts[0]];
    if (cursor == null ||
        !identical(cursor.principal, work.actor.token) ||
        cursor.filter != filter ||
        cursor.kind != work.tool)
      throw StateError('CURSOR_EXPIRED');
    return cursor;
  }

  Future<Map<String, Object?>> _execute(RemoteReadWork work) async {
    final tool = work.tool, args = work.args;
    if (tool == 'serverdeck_servers_list') return _list(work);
    final profile = requireUuid(args['serverId']);
    work.actor.authorize(tool, profile);
    final state = connections.store.snapshot.foundation.foundation;
    final record = state.profiles[profile];
    if (record == null)
      throw StateError(work.actor.owner == null ? 'FORBIDDEN' : 'NOT_FOUND');
    if (tool == 'serverdeck_server_get') {
      requireFields(args, {'serverId'});
      return {
        'profile': record
            .view(state.credentials[record.credentialRef])
            .toJson(),
        'connection': connections.snapshot(profile, work.actor.token),
        'capabilities': {
          'state': true,
          'logs': true,
          'configuration': true,
          'executor': false,
        },
      };
    }
    if (tool == 'owner_executor_inspect') {
      requireFields(args, {'serverId'});
      final opening = executors.inspectOwner(work.actor.owner!, profile);
      work.executors.add(opening);
      try {
        final session = await opening.result;
        work.check();
        return executors.inspection(work.actor.owner!, session);
      } finally {
        await opening.close();
        work.executors.remove(opening);
      }
    }
    if (tool == 'serverdeck_logs_read') return _logs(work, profile);
    if (tool == 'serverdeck_recipes_list') return _recipes(work, profile);
    if (tool == 'serverdeck_configuration_get') {
      return _configuration(work, profile);
    }
    requireFields(args, {'serverId'}, {'refresh'});
    if (args.containsKey('refresh') && args['refresh'] is! bool)
      throw const FormatException('VALIDATION');
    if (args['refresh'] == true) await _refresh(work, profile);
    return _stateView(profile, work.actor.token);
  }

  Future<Map<String, Object?>> _recipes(
    RemoteReadWork work,
    String profile,
  ) async {
    requireFields(work.args, {'serverId'});
    final opening = work.actor.owner != null
        ? executors.startOwner(work.actor.owner!, profile)
        : executors.startMcp(work.actor.mcp!, profile, scope: McpScope.plan);
    work.executors.add(opening);
    try {
      final session = await opening.result;
      work.check();
      final catalog = captureExecutorRecipes(
        await session.request('recipes', {
          'target': session.target,
          'expectedHostId': session.enrollment.hostId,
        }),
      );
      work.check();
      if (catalog['hostId'] != session.enrollment.hostId ||
          catalog['runtimeVersion'] != session.enrollment.runtimeVersion ||
          catalog['registryDigest'] != session.enrollment.registryDigest ||
          catalog['installEnabled'] !=
              (session.hello['capabilities'] as Map)['install'])
        throw StateError('RUNTIME_INCOMPATIBLE');
      return {'serverId': profile, 'catalog': catalog};
    } on FormatException {
      throw StateError('RUNTIME_INCOMPATIBLE');
    } finally {
      await opening.close();
      work.executors.remove(opening);
    }
  }

  DateTime _directObservedAt() => DateTime.fromMillisecondsSinceEpoch(
    clock.utcNow.toUtc().millisecondsSinceEpoch,
    isUtc: true,
  );

  Future<DirectSshOutput> _directRead(
    RemoteReadWork work,
    DirectObservationTarget target,
    DirectSshCommand command,
  ) async {
    void current() {
      work.check();
      if (!target.matches(connections.store.snapshot.foundation.foundation)) {
        throw StateError('TRUST_CHANGED');
      }
    }

    current();
    final direct = work.actor.owner != null
        ? connections.executeDirectOwner(
            work.actor.owner!,
            target.serverId,
            command,
            beforeDispatch: current,
          )
        : connections.executeDirectMcp(
            work.actor.mcp!,
            target.serverId,
            command,
            beforeDispatch: current,
          );
    work.directs.add(direct);
    try {
      final value = await direct.result;
      await direct.done;
      current();
      final identity = value.identity, fields = target.toJson();
      if (identity.profileId != target.serverId ||
          identity.connectionRevision != fields['connectionRevision'] ||
          identity.credentialRevision != fields['accessRevision'] ||
          identity.trustRevision != fields['trustRevision'])
        throw StateError('TRUST_CHANGED');
      return value.output;
    } finally {
      direct.done.then<void>((_) => work.directs.remove(direct)).ignore();
    }
  }

  Future<ManagedResourceObservationRecord> _observeDirect(
    RemoteReadWork work,
    DirectObservationTarget target,
    String resource,
  ) async {
    final began = _directObservedAt();
    final inspect = await _directRead(work, target, DirectSshCommand.inspect());
    final DirectSshIdentity identity;
    try {
      identity = DirectSshIdentity.capture(
        inspect.textRows(DirectSshIdentity.fields),
      );
    } on DirectSshFailure catch (error) {
      return target.unavailable(
        resource,
        directObservationFailureStatus(error.code),
        began,
      );
    }
    // Capture time before the actual resource read, never freshen a delayed
    // response by assigning its completion time to an older observation.
    final observedAt = _directObservedAt();
    final output = await _directRead(
      work,
      target,
      DirectSshCommand.observation(resource),
    );
    return target.parse(resource, identity, output, observedAt);
  }

  Future<Map<String, Object?>> _configuration(
    RemoteReadWork work,
    String profile,
  ) async {
    requireFields(work.args, {'serverId', 'resourceId'}, {'refresh'});
    final resource = work.args['resourceId'];
    if (resource is! String ||
        !managedResourceIds.contains(resource) ||
        work.args.containsKey('refresh') && work.args['refresh'] is! bool)
      throw const FormatException('VALIDATION');
    final key = '$profile/$resource';
    final target = work.configurationTarget = DirectObservationTarget.capture(
      connections.store.snapshot.foundation.foundation,
      profile,
    );
    if (work.args['refresh'] == true) {
      final observation = await _observeDirect(work, target, resource);
      work.check();
      _managed.remove(key);
      _managed[key] = observation;
      _managedStale.remove(key);
      var bytes = _managed.values.fold<int>(
        0,
        (sum, value) => sum + utf8.encode(jsonEncode(value.toJson())).length,
      );
      while (bytes > 64 * 1024 * 1024) {
        final first = _managed.keys.first;
        _managedStale.remove(first);
        bytes -= utf8
            .encode(jsonEncode(_managed.remove(first)!.toJson()))
            .length;
      }
    }
    return _configurationResult(work, profile, resource);
  }

  Map<String, Object?> _configurationResult(
    RemoteReadWork work,
    String profile,
    String resource,
  ) {
    work.check();
    final key = '$profile/$resource';
    final foundation = connections.store.snapshot.foundation.foundation;
    final record = foundation.profiles[profile]!;
    final previous = _managed[key];
    final rawNow = clock.utcNow.toUtc();
    final now = DateTime.fromMillisecondsSinceEpoch(
      rawNow.millisecondsSinceEpoch,
      isUtc: true,
    );
    final current = previous == null
        ? {
            'workspaceId': foundation.workspaceId,
            'serverId': profile,
            'resourceId': resource,
            'targetRevision': record.revision,
            'connectionRevision': record.connectionRevision,
            'accessRevision': record.credentialRevision,
            'trustRevision': record.trustRevision,
            'hostId': null,
            'resourceRegistryDigest': null,
            'observedAt': DateTime.fromMillisecondsSinceEpoch(
              now.millisecondsSinceEpoch,
              isUtc: true,
            ).toIso8601String(),
            'status': 'unknown',
            'value': null,
          }
        : previous.toJson();
    if (previous != null &&
        const {'known', 'stale'}.contains(previous.status) &&
        (_managedStale.contains(key) ||
            previous.targetRevision != record.revision ||
            previous.connectionRevision != record.connectionRevision ||
            previous.accessRevision != record.credentialRevision ||
            previous.trustRevision != record.trustRevision ||
            now.isBefore(previous.observedAt) ||
            now.difference(previous.observedAt) > const Duration(seconds: 15)))
      current['status'] = 'stale';
    return configurationView(
      graph: connections.store.snapshot.automation,
      observation: ManagedResourceObservationRecord.fromTrustedJson(current),
      at: now,
    );
  }

  Map<String, Object?> _list(RemoteReadWork work) {
    requireFields(work.args, {}, {'limit', 'cursor'});
    final limit = work.args['limit'] ?? 50;
    if (limit is! int || limit < 1 || limit > 100)
      throw const FormatException('VALIDATION');
    final filter = 'limit:$limit';
    final cursor = work.args['cursor'] == null
        ? null
        : _decodeCursor(work.args['cursor'], work, filter);
    final state = connections.store.snapshot.foundation.foundation;
    final items =
        cursor?.items ??
              [
                for (final record in state.profiles.values)
                  if (work.actor.allows(record.id))
                    record
                        .view(state.credentials[record.credentialRef])
                        .toJson(),
              ]
          ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final start = cursor?.offset ?? 0, end = min(start + limit, items.length);
    final page = items.sublist(start, end);
    for (final item in page)
      if (!work.actor.allows(item['id'] as String))
        throw StateError('FORBIDDEN');
    final next = end < items.length
        ? _cursor(
            _ReadCursor(
              work,
              filter,
              clock.elapsed + const Duration(minutes: 5),
              items: items,
              offset: end,
            ),
          )
        : null;
    return {'items': page, if (next != null) 'nextCursor': next};
  }

  Future<ConnectionReadValue> _read(
    RemoteReadWork work,
    String profile,
    SshReadRequest request, {
    _SharedRefresh? group,
  }) async {
    if (group == null) {
      work.check();
    } else {
      group.check();
    }
    final read = work.actor.owner != null
        ? connections.readOwner(work.actor.owner!, profile, request)
        : connections.readMcp(work.actor.mcp!, profile, request);
    final owned = group?.reads ?? work.reads;
    owned.add(read);
    try {
      final value = await read.result;
      if (group == null) {
        work.check();
      } else {
        group.check();
      }
      return value;
    } finally {
      read.done.then<void>((_) => owned.remove(read)).ignore();
    }
  }

  Future<void> _refresh(RemoteReadWork work, String profile) async {
    work.check();
    final connection = connections.snapshot(profile, work.actor.token);
    if (connection['state'] != 'connected' || connection['interested'] != true)
      throw StateError('NOT_READY');
    final cache = _cache[profile];
    if (cache != null &&
        !cache.stale &&
        jsonEncode(cache.identity) == jsonEncode(connection['identity']) &&
        clock.elapsed - cache.received < const Duration(seconds: 5))
      return;
    var group = _refreshes[profile];
    if (group != null && group.stopped) throw StateError('RESOURCE_LIMIT');
    if (group == null) {
      if (_refreshes.length >= 2) throw StateError('RESOURCE_LIMIT');
      group = _SharedRefresh(
        this,
        profile,
        Map<String, Object?>.from(connection['identity'] as Map),
        work.actor.remaining,
      );
      _refreshes[profile] = group;
    }
    group.waiters.add(work);
    work.refreshes.add(group);
    group.start();
    try {
      await group.result;
      work.check();
    } finally {
      group.detach(work);
      work.refreshes.remove(group);
    }
  }

  Future<void> _buildRefresh(_SharedRefresh group) async {
    final profile = group.profile;
    final old = _cache[profile];
    final parts = <String, Map<String, Object?>>{};
    final times = <String, Duration>{};
    final identity = group.identity;
    final sameOld =
        old != null && jsonEncode(old.identity) == jsonEncode(identity);
    CpuSample? cpu;
    const sources = ['system', 'metrics', 'packages', 'units'];
    var index = 0;
    while (index < sources.length) {
      final source = sources[index];
      final work = group.active;
      if (sameOld &&
          const {'packages', 'units'}.contains(source) &&
          old.parts[source]?['quality'] == 'known' &&
          clock.elapsed - (old.partReceived[source] ?? old.received) <
              const Duration(minutes: 5)) {
        parts[source] = _codec.decode(
          _codec.encode(old.parts[source]!, maxBytes: 2 * 1024 * 1024),
          maxBytes: 2 * 1024 * 1024,
        );
        times[source] = old.partReceived[source] ?? old.received;
        index++;
        continue;
      }
      try {
        final request = switch (source) {
          'system' => const SshReadRequest.system(),
          'metrics' => const SshReadRequest.metrics(),
          'packages' => const SshReadRequest.packages(),
          _ => const SshReadRequest.units(),
        };
        final result = await _read(work, profile, request, group: group);
        final captured = result.identity.toJson();
        if (jsonEncode(identity) != jsonEncode(captured))
          throw StateError('TRUST_CHANGED');
        if (source == 'metrics') {
          final parsed = parseMetrics(
            result.output,
            sameOld ? old.cpu : null,
            receivedAt: clock.utcNow,
          );
          parts[source] = parsed.value;
          cpu = parsed.cpu;
        } else {
          parts[source] = switch (source) {
            'system' => parseSystem(result.output, receivedAt: clock.utcNow),
            'packages' => parsePackages(
              result.output,
              receivedAt: clock.utcNow,
            ),
            _ => parseUnits(result.output, receivedAt: clock.utcNow),
          };
        }
        times[source] = clock.elapsed;
      } catch (error) {
        group.check();
        if (work._stopped) continue;
        if (error is StateError &&
            const {
              'UNAUTHORIZED',
              'FORBIDDEN',
              'TRUST_REQUIRED',
              'TRUST_CHANGED',
              'NOT_READY',
            }.contains(error.message))
          rethrow;
        parts[source] = _failedObservation(
          source,
          sameOld ? old.parts[source] : null,
          error,
        );
        times[source] = sameOld
            ? old.partReceived[source] ?? old.received
            : clock.elapsed;
      }
      index++;
    }
    group.check();
    await group.active.actor.proof();
    group.check();
    final cache = _ServerCache(identity, parts, clock.elapsed, cpu);
    cache.partReceived.addAll(times);
    final metrics = parts['metrics']?['value'];
    if (metrics is Map) {
      final history =
          old != null && jsonEncode(old.identity) == jsonEncode(identity)
          ? old.history.toList()
          : <Map<String, Object?>>[];
      if (parts['metrics']?['quality'] == 'known' ||
          parts['metrics']?['quality'] == 'incomplete')
        history.add({
          'timestamp': parts['metrics']!['observedAt'],
          'receivedAt': parts['metrics']!['receivedAt'],
          'cpuPercent': metrics['cpuPercent'],
          'memoryUsedPercent': (metrics['memory'] as Map?)?['usedPercent'],
          'rootDiskUsedPercent': (metrics['rootDisk'] as Map?)?['usedPercent'],
        });
      final cutoff = clock.utcNow.toUtc().subtract(const Duration(minutes: 10));
      history.removeWhere(
        (point) =>
            DateTime.tryParse('${point['receivedAt']}')?.isBefore(cutoff) ??
            true,
      );
      cache.history.addAll(history.skip(max(0, history.length - 120)));
    }
    _fit(cache);
    group.check();
    _cache[profile] = cache;
    _limitCaches();
  }

  Map<String, Object?> _failedObservation(
    String source,
    Map<String, Object?>? previous,
    Object error,
  ) {
    final code =
        error is StateError && TrustedLocalError.codes.contains(error.message)
        ? error.message
        : error is TimeoutException
        ? 'TIMEOUT'
        : 'SERVICE_UNAVAILABLE';
    return previous == null
        ? observation(
            'ssh:$source',
            null,
            receivedAt: clock.utcNow,
            quality: 'unknown',
            code: code,
          )
        : {
            ..._codec.decode(
              _codec.encode(previous, maxBytes: 2 * 1024 * 1024),
              maxBytes: 2 * 1024 * 1024,
            ),
            'quality': 'stale',
            'code': code,
          };
  }

  void _fit(_ServerCache cache) {
    while (utf8.encode(jsonEncode(cache.parts)).length > 1536 * 1024) {
      var removed = false;
      for (final key in ['packages', 'units']) {
        final part = cache.parts[key], rows = part?['value'];
        if (rows is List && rows.isNotEmpty) {
          rows.removeRange(
            max(0, rows.length - max(1, rows.length ~/ 4)),
            rows.length,
          );
          part!['quality'] = 'incomplete';
          part['truncated'] = true;
          removed = true;
        }
      }
      if (!removed) throw StateError('RESOURCE_LIMIT');
    }
  }

  void _limitCaches() {
    var bytes = _cache.values.fold<int>(
      0,
      (n, c) => n + utf8.encode(jsonEncode(c.parts)).length,
    );
    final oldest = _cache.values.toList()
      ..sort((a, b) => a.received.compareTo(b.received));
    for (final cache in oldest) {
      if (bytes <= 64 * 1024 * 1024) break;
      bytes -= utf8.encode(jsonEncode(cache.parts)).length;
      cache.parts.clear();
      cache.history.clear();
      cache.stale = true;
      cache.evicted = true;
    }
  }

  Map<String, Object?> _stateView(String profile, Object principal) {
    final cache = _cache[profile], parts = <String, Object?>{};
    for (final source in ['system', 'metrics', 'packages', 'units']) {
      final value = cache?.parts[source];
      if (value == null) {
        parts[source] = observation(
          'ssh:$source',
          null,
          receivedAt: clock.utcNow,
          quality: 'unknown',
          code: cache?.evicted == true ? 'RESOURCE_LIMIT' : 'NOT_READY',
        );
        continue;
      }
      final age =
          clock.elapsed - (cache!.partReceived[source] ?? cache.received);
      final stale =
          cache.stale ||
          age >= Duration(seconds: source == 'metrics' ? 15 : 300);
      parts[source] = {
        ...value,
        'stale': stale || value['quality'] == 'stale',
        if (stale && value['quality'] == 'known') 'quality': 'stale',
      };
    }
    final cutoff = clock.utcNow.toUtc().subtract(const Duration(minutes: 10));
    final history =
        cache?.history
            .where(
              (p) =>
                  !(DateTime.tryParse('${p['receivedAt']}')?.isBefore(cutoff) ??
                      true),
            )
            .toList() ??
        [];
    return {
      'serverId': profile,
      'identity': cache?.identity,
      'connection': connections.snapshot(profile, principal),
      ...parts,
      'history': history,
      'cacheDropped': cache?.evicted ?? false,
    };
  }

  Future<Map<String, Object?>> _logs(
    RemoteReadWork work,
    String profile,
  ) async {
    requireFields(
      work.args,
      {'serverId'},
      {'unit', 'since', 'until', 'priority', 'text', 'limit', 'cursor'},
    );
    final args = work.args, limit = args['limit'] ?? 100;
    if (limit is! int ||
        limit < 1 ||
        limit > 1000 ||
        args['text'] != null &&
            (args['text'] is! String ||
                (args['text'] as String).runes.length > 256))
      throw const FormatException('VALIDATION');
    final priority = args['priority'];
    if (priority != null && (priority is! int || priority < 0 || priority > 7))
      throw const FormatException('VALIDATION');
    final since = _date(args['since']), until = _date(args['until']);
    if (since != null && until != null && since.isAfter(until))
      throw const FormatException('VALIDATION');
    final filter = utf8.decode(
      _codec.canonical({
        'serverId': profile,
        'unit': args['unit'],
        'since': since?.toUtc().toIso8601String(),
        'until': until?.toUtc().toIso8601String(),
        'priority': priority,
        'text': args['text'],
        'limit': limit,
      }),
    );
    final cursor = args['cursor'] == null
        ? null
        : _decodeCursor(args['cursor'], work, filter);
    final currentIdentity = connections.snapshot(
      profile,
      work.actor.token,
    )['identity'];
    if (cursor != null &&
        (cursor.profile != profile ||
            cursor.identity != jsonEncode(currentIdentity)))
      throw StateError('CURSOR_EXPIRED');
    String? unit;
    if (args['unit'] != null) {
      if (args['unit'] is! String) throw const FormatException('VALIDATION');
      unit = work.actor.owner != null
          ? args['unit'] as String
          : switch (args['unit']) {
              'postgresql.service' => 'postgresql@16-main.service',
              'clickhouse.service' => 'clickhouse-server.service',
              _ => throw StateError('UNSUPPORTED'),
            };
    }
    final result = await _read(
      work,
      profile,
      SshReadRequest.journal(
        unit: unit,
        since: since,
        until: until,
        priority: priority as int?,
        limit: limit,
        cursor: cursor?.journal,
      ),
    );
    final parsed = parseJournal(
      result.output,
      skipCursor: cursor?.journal,
      text: args['text'] as String?,
      limit: limit,
    );
    work.check();
    final identity = result.identity.toJson();
    var ring = _rings[profile];
    if (ring == null || jsonEncode(ring.identity) != jsonEncode(identity)) {
      ring = _JournalRing(identity);
      _rings[profile] = ring;
    }
    var duplicates = parsed.duplicates;
    for (final record in parsed.records) {
      if (ring.records.any((r) => r['cursor'] == record['cursor'])) {
        duplicates++;
        continue;
      }
      ring.records.add(record);
      if (ring.records.length > 500) {
        ring.records.removeAt(0);
        ring.dropped++;
      }
    }
    ring.stale = false;
    _limitLogs();
    final next =
        parsed.truncated &&
            parsed.oldestCursor != null &&
            parsed.oldestCursor != cursor?.journal
        ? _cursor(
            _ReadCursor(
              work,
              filter,
              clock.elapsed + const Duration(minutes: 5),
              profile: profile,
              identity: jsonEncode(identity),
              journal: parsed.oldestCursor,
            ),
          )
        : null;
    return {
      'serverId': profile,
      'identity': identity,
      'source': 'journald',
      'timezone': 'UTC',
      'observedAt': clock.utcNow.toUtc().toIso8601String(),
      'quality':
          sourceQuality(result.output) == 'known' && parsed.parseErrors > 0
          ? 'incomplete'
          : sourceQuality(result.output),
      'records': parsed.records,
      'gaps':
          parsed.parseErrors > 0 || result.output.truncated || ring.dropped > 0,
      'dropped': ring.dropped,
      'duplicates': duplicates,
      'parseErrors': parsed.parseErrors,
      'truncated': parsed.truncated,
      if (next != null) 'nextCursor': next,
    };
  }

  DateTime? _date(Object? value) {
    if (value == null) return null;
    if (value is! String || value.length > 64 || !value.endsWith('Z'))
      throw const FormatException('VALIDATION');
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !parsed.isUtc)
      throw const FormatException('VALIDATION');
    return parsed;
  }

  void _limitLogs() {
    var total = _rings.values.fold<int>(
      0,
      (n, r) => n + utf8.encode(jsonEncode(r.records)).length,
    );
    while (total > 64 * 1024 * 1024) {
      final rings = _rings.values.where((r) => r.records.isNotEmpty).toList();
      if (rings.isEmpty) break;
      rings.sort(
        (a, b) => ('${a.records.first['timestamp']}').compareTo(
          '${b.records.first['timestamp']}',
        ),
      );
      final ring = rings.first, removed = ring.records.removeAt(0);
      total -= utf8.encode(jsonEncode(removed)).length;
      ring.dropped++;
    }
  }

  Future<void> suspend() {
    if (_closed) return Future.error(StateError('SERVICE_UNAVAILABLE'));
    if (_pausing != null) return _pausing!;
    _paused = true;
    final done = Completer<void>();
    _pausing = done.future;
    done.future.ignore();
    _cursors.clear();
    for (final work in _work.toList()) work.stop('SERVICE_UNAVAILABLE');
    for (final group in _refreshes.values.toList())
      group.stop('SERVICE_UNAVAILABLE');
    Future.wait([
      executors.suspend(),
      for (final work in _work.toList()) work.done,
      for (final group in _refreshes.values.toList()) group.done,
    ]).then<void>(
      (_) {
        _cache.clear();
        _rings.clear();
        _managedStale.addAll(_managed.keys);
        _pauseDrained = true;
        done.complete();
      },
      onError: (Object _, StackTrace __) =>
          done.completeError(StateError('SERVICE_UNAVAILABLE')),
    );
    return done.future;
  }

  void resume() {
    if (_closed || !_paused || !_pauseDrained)
      throw StateError('SERVICE_UNAVAILABLE');
    executors.resume();
    _paused = _pauseDrained = false;
    _pausing = null;
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _unsubscribe();
    _unsubscribeSession();
    for (final work in _work.toList()) work.stop('SERVICE_UNAVAILABLE');
    for (final group in _refreshes.values.toList())
      group.stop('SERVICE_UNAVAILABLE');
    return _closing =
        Future.wait([
          executors.close(),
          for (final work in _work.toList()) work.done,
          for (final group in _refreshes.values.toList()) group.done,
        ]).then<void>((_) {
          _cache.clear();
          _managed.clear();
          _managedStale.clear();
          _rings.clear();
          _cursors.clear();
          _key.destroy();
        });
  }
}

/// One sampler per connected target shared by all authorized callers.
final class _SharedRefresh {
  _SharedRefresh(this.service, this.profile, this.identity, this.budget) {
    _result.future.ignore();
    _done.future.ignore();
  }
  final RemoteReadService service;
  final String profile;
  final Map<String, Object?> identity;
  final Duration budget;
  final watch = Stopwatch()..start();
  final waiters = <RemoteReadWork>{}, reads = <ConnectionReadWork>{};
  final actors = <_ReadActor>{};
  final _result = Completer<void>(), _done = Completer<void>();
  bool stopped = false, _started = false;
  String _code = 'CANCELLED';
  Future<void> get result => _result.future;
  Future<void> get done => _done.future;
  void start() {
    if (!_started) {
      _started = true;
      _run().ignore();
    }
  }

  RemoteReadWork get active {
    for (final work in waiters.toList()) {
      try {
        work.check();
        final view = service.connections.snapshot(profile, work.actor.token);
        if (view['state'] != 'connected' || view['interested'] != true)
          throw StateError('NOT_READY');
        actors.add(work.actor);
        return work;
      } catch (error) {
        work.stop(
          error is StateError && mcpDomainCodes.contains(error.message)
              ? error.message
              : 'CANCELLED',
        );
      }
    }
    throw StateError(stopped ? _code : 'CANCELLED');
  }

  void check() {
    if (stopped) throw StateError(_code);
    if (watch.elapsed >= budget) throw StateError('TIMEOUT');
    active;
  }

  void detach(RemoteReadWork work) {
    waiters.remove(work);
    if (waiters.isEmpty) stop('CANCELLED');
  }

  void stop(String code) {
    if (stopped) return;
    stopped = true;
    _code = code;
    if (!_result.isCompleted) _result.completeError(StateError(code));
    for (final read in reads.toList()) read.cancelInterest().ignore();
  }

  Future<void> _run() async {
    final timer = Timer(budget, () => stop('TIMEOUT'));
    try {
      await service._buildRefresh(this);
      check();
      if (!_result.isCompleted) _result.complete();
    } catch (error) {
      if (!_result.isCompleted)
        _result.completeError(
          error is StateError ? error : StateError('INTERNAL'),
        );
    } finally {
      timer.cancel();
      try {
        await drainOwned([
          for (final read in reads.toList()) read.cancelInterest,
          for (final actor in actors) () => actor.settled,
        ]);
        if (identical(service._refreshes[profile], this))
          service._refreshes.remove(profile);
        _done.complete();
      } catch (_) {
        _done.completeError(StateError('SERVICE_UNAVAILABLE'));
      }
    }
  }
}

final class _ServerCache {
  _ServerCache(this.identity, this.parts, this.received, this.cpu);
  final Map<String, Object?> identity;
  final Map<String, Map<String, Object?>> parts;
  final Duration received;
  final CpuSample? cpu;
  final history = <Map<String, Object?>>[];
  final partReceived = <String, Duration>{};
  bool stale = false;
  bool evicted = false;
}

final class _JournalRing {
  _JournalRing(this.identity);
  final Map<String, Object?> identity;
  final records = <Map<String, Object?>>[];
  int dropped = 0;
  bool stale = false;
}

final class _ReadCursor {
  _ReadCursor(
    RemoteReadWork work,
    this.filter,
    this.expires, {
    this.items = const [],
    this.offset = 0,
    this.profile,
    this.identity,
    this.journal,
  }) : kind = work.tool,
       principal = work.actor.token,
       session = work.actor.session;
  final String kind, filter, session;
  final Object principal;
  final Duration expires;
  final List<Map<String, Object?>> items;
  final int offset;
  final String? profile, identity, journal;
  int get bytes =>
      utf8.encode(jsonEncode(items)).length + (journal?.length ?? 0);
}

final class _ReadActor {
  _ReadActor.owner(this.owner) : mcp = null;
  _ReadActor.mcp(this.mcp) : owner = null;
  final TrustedOwnerReadContext? owner;
  final TrustedMcpContext? mcp;
  final watch = Stopwatch()..start();
  final proofs = <Future<void>>{};
  Object get token => owner?.connectionInterest ?? mcp!.connectionInterest;
  String get session => owner?.sessionId ?? mcp!.sessionId;
  Duration get remaining {
    final left =
        owner?.remaining ?? const Duration(seconds: 30) - watch.elapsed;
    if (left <= Duration.zero) throw StateError('TIMEOUT');
    return left;
  }

  void authorize(String tool, Object? server) {
    remaining;
    if (mcp != null) {
      mcp!.authorize(
        scope: switch (tool) {
          'serverdeck_logs_read' => McpScope.logs,
          'serverdeck_recipes_list' => McpScope.plan,
          _ => McpScope.read,
        },
        serverId: server == null ? null : requireUuid(server),
      );
    }
  }

  bool allows(String profile) {
    if (mcp == null) return true;
    try {
      mcp!.authorize(scope: McpScope.read, serverId: profile);
      return true;
    } on StateError catch (e) {
      if (e.message == 'FORBIDDEN') return false;
      rethrow;
    }
  }

  Future<void> proof() async {
    if (owner != null) {
      await owner!.revalidate();
      return;
    }
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

  Future<void> get settled =>
      Future.wait<void>([if (owner != null) owner!.settled, ...proofs]);
}

final class RemoteReadWork {
  RemoteReadWork._(this.service, this.actor, this.tool, this.args) {
    _result.future.ignore();
    _done.future.ignore();
  }
  final RemoteReadService service;
  final _ReadActor actor;
  final String tool;
  final Map<String, Object?> args;
  final reads = <ConnectionReadWork>{};
  final directs = <ConnectionDirectWork>{};
  final executors = <RemoteExecutorOperation>{};
  final refreshes = <_SharedRefresh>{};
  final _result = Completer<Map<String, Object?>>(), _done = Completer<void>();
  DirectObservationTarget? configurationTarget;
  bool _stopped = false;
  Future<Map<String, Object?>> get result => _result.future;
  Future<void> get done => _done.future;
  void check() {
    if (_stopped) throw StateError('CANCELLED');
    actor.authorize(tool, args['serverId']);
    service._ready();
    final target = configurationTarget;
    if (target != null &&
        !target.matches(
          service.connections.store.snapshot.foundation.foundation,
        )) {
      throw StateError('TRUST_CHANGED');
    }
  }

  void stop(String code) {
    if (_result.isCompleted) return;
    _stopped = true;
    _result.completeError(StateError(code));
    for (final group in refreshes.toList()) group.detach(this);
    for (final read in reads.toList()) read.cancelInterest().ignore();
    for (final direct in directs.toList()) direct.cancelInterest().ignore();
    for (final executor in executors.toList()) executor.close().ignore();
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
      check();
      var value = await service._execute(this);
      check();
      await actor.proof();
      check();
      if (tool == 'serverdeck_configuration_get') {
        value = service._configurationResult(
          this,
          args['serverId'] as String,
          args['resourceId'] as String,
        );
      }
      // Two MCP encodings (text plus structuredContent) fit the8MiB envelope.
      service._codec.encode(value, maxBytes: 2 * 1024 * 1024);
      _result.complete(value);
    } catch (error) {
      final code = error is StateError && mcpDomainCodes.contains(error.message)
          ? error.message
          : error is TimeoutException
          ? 'TIMEOUT'
          : error is FormatException
          ? 'VALIDATION'
          : 'INTERNAL';
      if (!_result.isCompleted) _result.completeError(StateError(code));
    } finally {
      timer?.cancel();
      try {
        await drainOwned([
          for (final read in reads.toList()) read.cancelInterest,
          for (final direct in directs.toList()) direct.cancelInterest,
          for (final executor in executors.toList()) executor.close,
          () => actor.settled,
        ]);
        service._work.remove(this);
        _done.complete();
      } catch (_) {
        _done.completeError(StateError('SERVICE_UNAVAILABLE'));
      }
    }
  }
}
