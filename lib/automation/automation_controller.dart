import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:serverdeck_protocol/automation/profile_body.dart';
import 'package:serverdeck_protocol/automation/profile_records.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

import '../bootstrap/local_api_client.dart' show newRequestId;

/// Borrows the native owner client. All effects use the shared owner services;
/// this controller owns response interest, never SSH or the lifetime of a job.
class AutomationController extends ChangeNotifier {
  AutomationController({required this.client, this.serverId}) {
    client.done.then<void>((_) {
      if (_disposed) return;
      _epoch++;
      _timer?.cancel();
      busy = false;
      error = 'SERVICE_UNAVAILABLE';
      notifyListeners();
    }).ignore();
  }
  final TrustedApiClient client;
  final String? serverId;
  String get _target => serverId ?? (throw StateError('VALIDATION'));
  final profiles = <AutomationProfileRecord>[];
  final jobs = <Map<String, Object?>>[];
  final approvals = <Map<String, Object?>>[];
  final delegations = <Map<String, Object?>>[];
  final grants = <Map<String, Object?>>[];
  Map<String, Object?>? launchConfiguration;
  bool grantsLoaded = false;
  final events = <Map<String, Object?>>[];
  Map<String, Object?>? revision, plan, job, catalog;
  Map<String, Object?>? validation, comparison;
  AutomationProfileRecord? profile;
  String? profilesCursor, jobsCursor, error;
  int? approvalsNext, delegationsNext;
  bool profilesLoaded = false, jobsLoaded = false, authoritiesLoaded = false;
  int droppedEvents = 0, _afterEvent = 0, _epoch = 0;
  bool busy = false, _disposed = false, _cancelled = false;
  Timer? _timer;
  String? _operation, _cancelMethod;
  _Action? _pending;
  bool get canMutate => !busy && _pending == null && !client.isClosed;
  bool get canRetry => !busy && _pending != null && !client.isClosed;
  String? get pendingLabel => _pending?.label;
  static const terminal = {
    'succeeded',
    'failed',
    'cancelled',
    'cancelled-partial',
  };

  void _live(int epoch) {
    if (_disposed || _cancelled || epoch != _epoch || client.isClosed)
      throw StateError('CANCELLED');
  }

  Future<void> _run(_Action action, {bool retry = false}) async {
    if (_disposed ||
        busy ||
        client.isClosed ||
        action.durable && _pending != null && !retry)
      return;
    busy = true;
    _cancelled = false;
    error = null;
    if (action.durable) _pending = action;
    final epoch = _epoch;
    notifyListeners();
    try {
      await action.work(epoch);
      _live(epoch);
      if (identical(_pending, action)) _pending = null;
    } catch (failure) {
      if (!_disposed && epoch == _epoch) {
        error = switch (failure) {
          TrustedRpcException() => failure.code,
          StateError() => failure.message,
          FormatException() => 'VALIDATION',
          _ => 'SERVICE_UNAVAILABLE',
        };
      }
    } finally {
      if (!_disposed && epoch == _epoch) {
        busy = false;
        _operation = _cancelMethod = null;
        notifyListeners();
        _schedule();
      }
    }
  }

  Future<void> retryPending() async {
    final action = _pending;
    if (action != null) await _run(action, retry: true);
  }

  void dismissPending() {
    if (_disposed || busy) return;
    _pending = null;
    error = null;
    notifyListeners();
  }

  Future<Map<String, Object?>> _direct(
    String method,
    Map<String, Object?> args,
    int epoch,
  ) async {
    _live(epoch);
    final value = await client.call(method, args);
    _live(epoch);
    final failure = value['failure'];
    if (failure is Map<String, Object?>)
      throw StateError(failure['code'] as String);
    return value;
  }

  Future<Map<String, Object?>> _async(
    String method,
    Map<String, Object?> args,
    int epoch, {
    bool read = false,
  }) async {
    _live(epoch);
    final id = newRequestId(), watch = Stopwatch()..start();
    final status = read ? 'servers.readStatus' : 'automation.status';
    final cancel = read ? 'servers.readCancel' : 'automation.cancel';
    _operation = id;
    _cancelMethod = cancel;
    var completed = false;
    try {
      var response = await client.call(method, args, requestId: id);
      while (true) {
        _live(epoch);
        if (response['operationId'] != id) throw StateError('INCOMPATIBLE');
        if (response['state'] == (read ? 'succeeded' : 'done')) {
          completed = true;
          if (response['kind'] != (read ? 'recipes' : method))
            throw StateError('INCOMPATIBLE');
          final result = response['result'] as Map<String, Object?>;
          if (read) return result;
          final business =
              McpToolResult.fromJson(result).toJson()['structuredContent']
                  as Map<String, Object?>;
          if (business['ok'] != true) {
            final error = business['error'] as Map<String, Object?>;
            throw StateError(error['code'] as String);
          }
          return business['data'] as Map<String, Object?>;
        }
        if (response['state'] == 'failed') {
          completed = true;
          throw StateError(response['code'] as String);
        }
        if (response['state'] != 'running') throw StateError('INCOMPATIBLE');
        if (watch.elapsed >= const Duration(seconds: 30))
          throw StateError('TIMEOUT');
        await Future<void>.delayed(const Duration(milliseconds: 250));
        _live(epoch);
        response = await client.call(status, {'operationId': id});
      }
    } finally {
      // Dropping a handle's response interest never means cancelling a job.
      if (!client.isClosed && !completed) {
        try {
          await client.call(cancel, {'operationId': id});
        } catch (_) {}
      }
      if (_operation == id) _operation = _cancelMethod = null;
    }
  }

  Future<void> cancelInterest() async {
    if (_disposed || !busy) return;
    _cancelled = true;
    final operation = _operation, cancel = _cancelMethod;
    if (operation != null && cancel != null && !client.isClosed) {
      try {
        await client.call(cancel, {'operationId': operation});
      } catch (_) {}
    }
  }

  Future<void> _profiles(int epoch, {bool more = false}) async {
    final value = await _direct('automation.profiles.list', {
      'limit': 25,
      if (more && profilesCursor != null) 'cursor': profilesCursor,
    }, epoch);
    final rows = (value['items'] as List)
        .map(
          (row) =>
              AutomationProfileRecord.fromJson(row as Map<String, Object?>),
        )
        .toList();
    if (!more) profiles.clear();
    for (final row in rows) {
      profiles.removeWhere((previous) => previous.id == row.id);
      profiles.add(row);
    }
    profilesCursor = value['nextCursor'] as String?;
    profilesLoaded = true;
  }

  Future<void> refreshProfiles({bool more = false}) =>
      _run(_Action('Профили', false, (epoch) => _profiles(epoch, more: more)));

  Future<void> _select(String id, int epoch, {int? version}) async {
    final value = await _direct('automation.profiles.get', {
      'profileId': id,
      if (version != null) 'revision': version,
    }, epoch);
    final captured = await AutomationRevisionRecord.fromJson(
      value['revision'] as Map<String, Object?>,
    );
    _live(epoch);
    profile = AutomationProfileRecord.fromJson(
      value['profile'] as Map<String, Object?>,
    );
    revision = captured.toJson();
    validation = comparison = null;
  }

  Future<void> selectProfile(String id, {int? version}) => _run(
    _Action(
      'Версия профиля',
      false,
      (epoch) => _select(id, epoch, version: version),
    ),
  );

  Future<void> validateBody(Map<String, Object?> body) {
    final captured = jsonDecode(jsonEncode(body)) as Map<String, Object?>;
    return _run(
      _Action('Проверка профиля', false, (epoch) async {
        validation = null;
        final result = await _direct('automation.profiles.validate', {
          'body': captured,
        }, epoch);
        if (result['valid'] is! bool || result['issues'] is! List)
          throw const FormatException('INCOMPATIBLE');
        validation = result;
      }),
    );
  }

  Future<void> compareVersions(Map<String, Object?> versions) {
    requireFields(versions, {'fromRevision', 'toRevision'});
    final selected = profile;
    if (selected == null) return Future.value();
    final from = versions['fromRevision'], to = versions['toRevision'];
    if (from is! int ||
        to is! int ||
        from < 1 ||
        to < 1 ||
        from > selected.headRevision ||
        to > selected.headRevision)
      throw const FormatException('VALIDATION');
    final input = {
      'profileId': selected.id,
      'fromRevision': from,
      'toRevision': to,
    };
    return _run(
      _Action('Сравнение версий', false, (epoch) async {
        comparison = null;
        final result = await _direct(
          'automation.profiles.compare',
          input,
          epoch,
        );
        if (result['changes'] is! List || result['truncated'] is! bool)
          throw const FormatException('INCOMPATIBLE');
        comparison = {...input, 'result': result};
      }),
    );
  }

  Future<void> saveProfile({
    required String name,
    required String description,
    required Map<String, Object?> body,
    AutomationProfileRecord? existing,
  }) {
    final captured = AutomationBody.fromJson(body).toJson(),
        request = newRequestId();
    return _run(
      _Action('Сохранение профиля', true, (epoch) async {
        final result = await _direct(
          'automation.profiles.${existing == null ? 'create' : 'update'}',
          {
            'requestId': request,
            'name': name,
            'description': description,
            'body': captured,
            if (existing != null) ...{
              'profileId': existing.id,
              'expectedRevision': existing.headRevision,
            },
          },
          epoch,
        );
        await _profiles(epoch);
        await _select(
          result['profileId'] as String,
          epoch,
          version: result['revision'] as int,
        );
      }),
    );
  }

  Future<void> archiveProfile(AutomationProfileRecord selected) {
    final request = newRequestId();
    return _run(
      _Action('Архивирование профиля', true, (epoch) async {
        await _direct('automation.profiles.archive', {
          'requestId': request,
          'profileId': selected.id,
          'expectedRevision': selected.headRevision,
        }, epoch);
        await _profiles(epoch);
        if (profile?.id == selected.id) {
          profile = null;
          revision = null;
        }
      }),
    );
  }

  Future<void> createPlan(Map<String, Object?> parameters) {
    final selected = revision;
    if (selected == null) return Future.value();
    final args = {
      'requestId': newRequestId(),
      'serverId': _target,
      'profileId': selected['profileId'],
      'revision': selected['revision'],
      'parameters': jsonDecode(jsonEncode(parameters)) as Map<String, Object?>,
    };
    return _run(
      _Action('Создание плана', true, (epoch) async {
        final ack = await _async('plans.create', args, epoch);
        await _loadPlan(ack['planId'] as String, epoch);
      }),
    );
  }

  Future<void> _loadPlan(String id, int epoch) async {
    final result = await _async('plans.get', {'planId': id}, epoch);
    final captured = result['plan'] as Map<String, Object?>;
    if (captured['serverId'] != serverId) throw StateError('PLAN_STALE');
    plan = captured;
  }

  Future<void> loadPlan(String id) =>
      _run(_Action('Чтение плана', false, (epoch) => _loadPlan(id, epoch)));

  Future<void> approvePlan(
    Map<String, Object?> displayed, {
    required bool approve,
  }) {
    final id = displayed['id'] as String,
        digest = displayed['digest'] as String;
    final requestId = newRequestId(), decisionId = newRequestId();
    return _run(
      _Action(approve ? 'Подтверждение плана' : 'Отклонение плана', true, (
        epoch,
      ) async {
        final ack = await _direct('approvals.request', {
          'requestId': requestId,
          'planId': id,
        }, epoch);
        if (ack['planDigest'] != digest) throw StateError('PLAN_STALE');
        await _direct('approvals.decide', {
          'requestId': decisionId,
          'approvalId': ack['approvalId'],
          'planDigest': digest,
          'decision': approve ? 'approved' : 'denied',
        }, epoch);
        await _authorities(epoch);
      }),
    );
  }

  Future<void> applyPlan(Map<String, Object?> displayed) {
    final args = {'requestId': newRequestId(), 'planId': displayed['id']};
    return _run(
      _Action('Запуск плана', true, (epoch) async {
        final ack = await _async('jobs.apply', args, epoch);
        await _jobs(epoch);
        await _job(ack['jobId'] as String, epoch);
      }),
    );
  }

  Future<void> _jobs(int epoch, {bool more = false}) async {
    if (serverId == null) return;
    final value = await _async('jobs.list', {
      'serverId': serverId,
      'limit': 25,
      if (more && jobsCursor != null) 'cursor': jobsCursor,
    }, epoch);
    if (!more) jobs.clear();
    for (final row in (value['items'] as List).cast<Map<String, Object?>>()) {
      final id = (row['job'] as Map<String, Object?>)['id'];
      jobs.removeWhere(
        (old) => (old['job'] as Map<String, Object?>)['id'] == id,
      );
      jobs.add(row);
    }
    jobsCursor = value['nextCursor'] as String?;
    jobsLoaded = true;
  }

  Future<void> refreshJobs({bool more = false}) =>
      _run(_Action('Задания', false, (epoch) => _jobs(epoch, more: more)));
  Future<void> _job(String id, int epoch) async {
    final value = await _async('jobs.get', {'jobId': id}, epoch);
    if ((value['plan'] as Map<String, Object?>)['serverId'] != serverId)
      throw StateError('FORBIDDEN');
    if (job?['id'] != id) {
      events.clear();
      _afterEvent = 0;
      droppedEvents = 0;
    }
    job = value['job'] as Map<String, Object?>;
    final index = jobs.indexWhere(
      (row) => (row['job'] as Map<String, Object?>)['id'] == id,
    );
    if (index >= 0) jobs[index] = {'job': job, 'serverId': serverId};
    final page = await _async('jobs.events', {
      'jobId': id,
      'after': _afterEvent,
      'limit': 100,
    }, epoch);
    events.addAll((page['events'] as List).cast<Map<String, Object?>>());
    if (events.length > 200) events.removeRange(0, events.length - 200);
    droppedEvents += page['dropped'] as int;
    _afterEvent = (page['nextSequence'] as int) - 1;
  }

  Future<void> selectJob(String id) =>
      _run(_Action('Состояние задания', false, (epoch) => _job(id, epoch)));
  Future<void> jobAction(String id, {required bool reconcile}) {
    final args = {'requestId': newRequestId(), 'jobId': id};
    return _run(
      _Action(reconcile ? 'Уточнение результата' : 'Остановка задания', true, (
        epoch,
      ) async {
        await _async(reconcile ? 'jobs.reconcile' : 'jobs.cancel', args, epoch);
        await _job(id, epoch);
        await _jobs(epoch);
      }),
    );
  }

  void _schedule() {
    _timer?.cancel();
    final selected = job;
    if (_disposed ||
        client.isClosed ||
        selected == null ||
        terminal.contains(selected['state']))
      return;
    final id = selected['id'] as String;
    _timer = Timer(const Duration(seconds: 1), () async {
      if (_disposed || client.isClosed) return;
      if (!busy) await selectJob(id);
      if (!_disposed && !client.isClosed) _schedule();
    });
  }

  Future<void> _authorities(int epoch) async {
    if (serverId == null) return;
    await _authorityPage(true, epoch);
    await _authorityPage(false, epoch);
    authoritiesLoaded = true;
  }

  Future<void> _authorityPage(
    bool approval,
    int epoch, {
    bool more = false,
  }) async {
    if (serverId == null) return;
    final offset = approval ? approvalsNext : delegationsNext;
    final value = await _direct(
      approval ? 'approvals.list' : 'delegations.list',
      {
        'limit': 50,
        'serverId': serverId,
        if (more && offset != null) 'offset': offset,
      },
      epoch,
    );
    final rows = approval ? approvals : delegations;
    if (!more) rows.clear();
    for (final row in (value['items'] as List).cast<Map<String, Object?>>()) {
      rows.removeWhere((old) => old['id'] == row['id']);
      rows.add(row);
    }
    if (approval) {
      approvalsNext = value['nextOffset'] as int?;
    } else {
      delegationsNext = value['nextOffset'] as int?;
    }
  }

  Future<void> initialize() => _run(
    _Action('Автоматизация', false, (epoch) async {
      await _profiles(epoch);
      await _jobs(epoch);
      await _authorities(epoch);
      await _grants(epoch);
    }),
  );
  Future<void> moreAuthorities({required bool approvals}) => _run(
    _Action(
      'Разрешения',
      false,
      (epoch) => _authorityPage(approvals, epoch, more: true),
    ),
  );

  Future<void> refreshAuthorities() =>
      _run(_Action('Разрешения', false, _authorities));

  Future<void> _grants(int epoch) async {
    final value = await _direct('grants.list', {}, epoch);
    grants
      ..clear()
      ..addAll((value['items'] as List).cast<Map<String, Object?>>());
    grantsLoaded = true;
  }

  Future<void> refreshGrants() => _run(_Action('Доступ ИИ', false, _grants));
  Future<void> saveGrant(
    Map<String, Object?> value, {
    Map<String, Object?>? existing,
  }) {
    requireFields(value, {'label', 'scopes', 'serverIds', 'lifetimeSeconds'});
    final captured = jsonDecode(jsonEncode(value)) as Map<String, Object?>;
    final args = {
      'requestId': newRequestId(),
      'grantId': existing?['id'] ?? newRequestId(),
      ...captured,
      if (existing != null) 'expectedRevision': existing['revision'],
    };
    return _run(
      _Action(
        existing == null ? 'Подключение ИИ' : 'Изменение доступа ИИ',
        true,
        (epoch) async {
          await _direct(
            existing == null ? 'grants.create' : 'grants.replace',
            args,
            epoch,
          );
          launchConfiguration = null;
          await _grants(epoch);
        },
      ),
    );
  }

  Future<void> revokeGrant(Map<String, Object?> selected) {
    final args = {
      'requestId': newRequestId(),
      'grantId': selected['id'],
      'expectedRevision': selected['revision'],
    };
    return _run(
      _Action('Отзыв доступа ИИ', true, (epoch) async {
        await _direct('grants.revoke', args, epoch);
        launchConfiguration = null;
        await _grants(epoch);
        await _authorities(epoch);
      }),
    );
  }

  Future<void> configurationForGrant(String id) => _run(
    _Action('Конфигурация MCP', false, (epoch) async {
      launchConfiguration = await _direct('grants.configuration', {
        'grantId': id,
      }, epoch);
    }),
  );
  Future<void> createDelegation({
    required Map<String, Object?> displayedRevision,
    required String grantId,
    required Map<String, Object?> predicates,
    required int lifetimeSeconds,
  }) {
    final selected = displayedRevision;
    final args = {
      'requestId': newRequestId(),
      'grantId': grantId,
      'serverIds': [_target],
      'profileRevisions': [
        {
          'profileId': selected['profileId'],
          'revision': selected['revision'],
          'bodyDigest': selected['digest'],
        },
      ],
      'predicates': jsonDecode(jsonEncode(predicates)),
      'lifetimeSeconds': lifetimeSeconds,
    };
    return _run(
      _Action('Делегирование профиля', true, (epoch) async {
        await _direct('delegations.create', args, epoch);
        await _authorities(epoch);
      }),
    );
  }

  Future<void> revokeDelegation(Map<String, Object?> selected) {
    final args = {
      'requestId': newRequestId(),
      'delegationId': selected['id'],
      'expectedRevision': selected['revision'],
    };
    return _run(
      _Action('Отзыв делегирования', true, (epoch) async {
        await _direct('delegations.revoke', args, epoch);
        await _authorities(epoch);
      }),
    );
  }

  Future<void> loadRecipes() => _run(
    _Action('Рецепты установки', false, (epoch) async {
      final value = await _async(
        'servers.recipes',
        {'profileId': _target},
        epoch,
        read: true,
      );
      catalog = value['catalog'] as Map<String, Object?>;
    }),
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    final operation = _operation, cancel = _cancelMethod;
    if (operation != null && cancel != null && !client.isClosed)
      client.call(cancel, {'operationId': operation}).ignore();
    super.dispose();
  }
}

final class _Action {
  _Action(this.label, this.durable, this.work);
  final String label;
  final bool durable;
  final Future<void> Function(int) work;
}
