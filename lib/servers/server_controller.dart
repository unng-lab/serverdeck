import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:serverdeck_protocol/connections.dart';
import 'package:serverdeck_protocol/executor_enrollment.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

import '../bootstrap/local_api_client.dart' show newRequestId;

/// The UI borrows one genuine format3 owner client; no SSH or secret is held.
class ServerController extends ChangeNotifier {
  ServerController({required this.client, required this.profileId}) {
    client.done.then<void>((_) {
      if (_disposed) return;
      _epoch++;
      busy = false;
      _operation = _cancelMethod = null;
      error = 'SERVICE_UNAVAILABLE';
      trustChallenge = null;
      executorInspection = null;
      notifyListeners();
    }).ignore();
    _scheduleSample();
  }
  final TrustedApiClient client;
  final String profileId;
  HostTrustSnapshot? trust;
  HostTrustChallenge? trustChallenge;
  ConnectionSnapshot? connection;
  ExecutorEnrollment? executor;
  Map<String, Object?>? state, logs, executorInspection, configuration;
  bool busy = false, _disposed = false, _cancelled = false;
  String? error;
  int _epoch = 0;
  String? _operation, _cancelMethod;
  Timer? _sampler;

  void _scheduleSample() {
    _sampler = Timer(const Duration(seconds: 5), () async {
      if (_disposed || client.isClosed) return;
      if (!busy &&
          connection?.state == 'connected' &&
          connection?.interested == true)
        await refreshState();
      if (!_disposed && !client.isClosed) _scheduleSample();
    });
  }

  Future<void> _action(Future<void> Function(int) action) async {
    if (_disposed || busy) return;
    busy = true;
    _cancelled = false;
    error = null;
    final epoch = _epoch;
    notifyListeners();
    try {
      await action(epoch);
    } catch (failure) {
      if (!_disposed && epoch == _epoch)
        error = switch (failure) {
          TrustedRpcException() => failure.code,
          StateError() => failure.message,
          _ => 'SERVICE_UNAVAILABLE',
        };
    } finally {
      if (!_disposed && epoch == _epoch) {
        busy = false;
        _operation = _cancelMethod = null;
        notifyListeners();
      }
    }
  }

  void _live(int epoch) {
    if (_disposed || _cancelled || epoch != _epoch || client.isClosed)
      throw StateError('CANCELLED');
  }

  Future<Map<String, Object?>> _poll(
    Map<String, Object?> initial,
    String status,
    String cancel,
    int epoch, {
    Duration budget = const Duration(seconds: 30),
  }) async {
    final id = initial['operationId'] as String;
    _operation = id;
    _cancelMethod = cancel;
    final clock = Stopwatch()..start();
    while (clock.elapsed < budget) {
      _live(epoch);
      final value = await client.call(status, {'operationId': id});
      _live(epoch);
      if (value['state'] == 'succeeded') return value;
      if (value['state'] == 'failed') throw StateError(value['code'] as String);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await client.call(cancel, {'operationId': id});
    throw StateError('TIMEOUT');
  }

  Future<Map<String, Object?>> _begin(
    String method,
    Map<String, Object?> args,
    String cancel,
    int epoch,
  ) async {
    final id = newRequestId();
    _operation = id;
    _cancelMethod = cancel;
    final result = await client.call(method, args, requestId: id);
    if (_disposed || _cancelled || epoch != _epoch || client.isClosed) {
      if (!client.isClosed) {
        try {
          await client.call(cancel, {'operationId': id});
        } catch (_) {}
      }
      throw StateError('CANCELLED');
    }
    return result;
  }

  Future<void> refresh() => _action((epoch) async {
    final currentTrust = await client.call('servers.trust.get', {
      'profileId': profileId,
    });
    _live(epoch);
    trust = HostTrustSnapshot.fromJson(currentTrust);
    final connectionValue = await client.call('servers.connection', {
      'profileId': profileId,
    });
    _live(epoch);
    connection = ConnectionSnapshot.fromJson(connectionValue);
    final binding = await client.call('executor.enrollment', {
      'profileId': profileId,
    });
    _live(epoch);
    executor = binding['enrollment'] == null
        ? null
        : ExecutorEnrollment.fromJson(
            binding['enrollment'] as Map<String, Object?>,
          );
  });

  Future<void> probeTrust() => _action((epoch) async {
    trustChallenge = null;
    final snapshot = HostTrustSnapshot.fromJson(
      await client.call('servers.trust.get', {'profileId': profileId}),
    );
    _live(epoch);
    trust = snapshot;
    final start = await _begin(
      'servers.trust.probe',
      {'profileId': profileId, 'expectedRevision': snapshot.profileRevision},
      'servers.trust.probeCancel',
      epoch,
    );
    _live(epoch);
    final result = await _poll(
      start,
      'servers.trust.probeStatus',
      'servers.trust.probeCancel',
      epoch,
    );
    _live(epoch);
    trustChallenge = HostTrustChallenge.fromJson(
      result['challenge'] as Map<String, Object?>,
    );
  });

  Future<void> confirmTrust() => _action((epoch) async {
    final challenge = trustChallenge;
    if (challenge == null) throw StateError('NOT_READY');
    await client.call('servers.trust.confirm', {
      'profileId': profileId,
      'expectedRevision': challenge.expectedRevision,
      'challengeId': challenge.challengeId,
      'key': challenge.key.toJson(),
    });
    _live(epoch);
    trustChallenge = null;
    final next = await client.call('servers.trust.get', {
      'profileId': profileId,
    });
    _live(epoch);
    trust = HostTrustSnapshot.fromJson(next);
  });

  Future<void> revokeTrust() => _action((epoch) async {
    final snapshot = HostTrustSnapshot.fromJson(
      await client.call('servers.trust.get', {'profileId': profileId}),
    );
    _live(epoch);
    await client.call('servers.trust.revoke', {
      'profileId': profileId,
      'expectedRevision': snapshot.profileRevision,
    });
    _live(epoch);
    trustChallenge = null;
    executorInspection = null;
    final nextConnection = await client.call('servers.connection', {
      'profileId': profileId,
    });
    _live(epoch);
    connection = ConnectionSnapshot.fromJson(nextConnection);
    final nextTrust = await client.call('servers.trust.get', {
      'profileId': profileId,
    });
    _live(epoch);
    trust = HostTrustSnapshot.fromJson(nextTrust);
  });

  Future<void> connect() => _action((epoch) async {
    final initial = await _begin(
      'servers.connect',
      {'profileId': profileId},
      'servers.connectCancel',
      epoch,
    );
    _live(epoch);
    final result = await _poll(
      initial,
      'servers.connectStatus',
      'servers.connectCancel',
      epoch,
      budget: const Duration(seconds: 15),
    );
    _live(epoch);
    connection = ConnectionSnapshot.fromJson(
      result['connection'] as Map<String, Object?>,
    );
  });
  Future<void> disconnect() => _action((epoch) async {
    final result = await client.call('servers.disconnect', {
      'profileId': profileId,
    });
    _live(epoch);
    connection = ConnectionSnapshot.fromJson(result);
  });

  Future<Map<String, Object?>> _read(
    String method,
    Map<String, Object?> args,
    int epoch,
  ) async {
    final initial = await _begin(
      method,
      {'profileId': profileId, ...args},
      'servers.readCancel',
      epoch,
    );
    _live(epoch);
    final result = await _poll(
      initial,
      'servers.readStatus',
      'servers.readCancel',
      epoch,
    );
    return result['result'] as Map<String, Object?>;
  }

  Future<void> refreshState() => _action((epoch) async {
    final result = await _read('servers.state', {'refresh': true}, epoch);
    _live(epoch);
    state = result;
  });
  Future<void> loadLogs({String? unit, String? text, String? cursor}) =>
      _action((epoch) async {
        final result = await _read('servers.logs', {
          if (unit != null) 'unit': unit,
          if (text != null && text.isNotEmpty) 'text': text,
          if (cursor != null) 'cursor': cursor,
        }, epoch);
        _live(epoch);
        logs = result;
      });
  Future<void> readConfiguration(String resource) => _action((epoch) async {
    final result = await _read('servers.configuration', {
      'resourceId': resource,
      'refresh': true,
    }, epoch);
    _live(epoch);
    configuration = result;
  });
  Future<void> inspectExecutor() => _action((epoch) async {
    executorInspection = null;
    final result = await _read('servers.executorInspect', {}, epoch);
    _live(epoch);
    executorInspection = result;
  });
  Future<void> confirmExecutor() => _action((epoch) async {
    final inspection = executorInspection;
    if (inspection == null) throw StateError('NOT_READY');
    final draft = ExecutorEnrollment.fromJson(
      inspection['enrollment'] as Map<String, Object?>,
    );
    final result = await client.call('executor.confirm', {
      'profileId': profileId,
      'challengeId': inspection['challengeId'],
      'hostId': draft.hostId,
    });
    _live(epoch);
    executor = ExecutorEnrollment.fromJson(
      result['enrollment'] as Map<String, Object?>,
    );
    executorInspection = null;
  });
  Future<void> revokeExecutor() => _action((epoch) async {
    await client.call('executor.revoke', {'profileId': profileId});
    _live(epoch);
    executor = null;
    executorInspection = null;
    configuration = null;
  });
  Future<void> cancel() async {
    final operation = _operation, method = _cancelMethod;
    _cancelled = true;
    if (!_disposed) notifyListeners();
    if (operation == null || method == null || client.isClosed) return;
    try {
      await client.call(method, {'operationId': operation});
    } catch (_) {}
  }

  void discardTrustChallenge() {
    trustChallenge = null;
    if (!_disposed) notifyListeners();
  }

  void discardExecutorInspection() {
    executorInspection = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    cancel().ignore();
    _disposed = true;
    _sampler?.cancel();
    _epoch++;
    super.dispose();
  }
}
