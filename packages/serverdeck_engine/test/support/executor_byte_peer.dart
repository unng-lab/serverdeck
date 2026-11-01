import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:serverdeck_engine/automation/compiler.dart';
import 'package:serverdeck_engine/platform/verified_release.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/executor.dart';
import 'package:serverdeck_protocol/executor_release.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../remote/ssh_io_policy_test.dart' as bytes;
import '../storage/actual_state_store_test.dart' show id;
import 'actual_mcp_setup.dart' show utcNow;
import 'schema3_fixture.dart' as fixture;

String hash(Object? value) => const DartSha256()
    .hashSync(StrictCodec().canonical(value))
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();
String fileHash(String value) => const DartSha256()
    .hashSync(utf8.encode(value))
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

/// Declared RAM platform-verification boundary, not native artifact acceptance.
final class Release implements VerifiedExecutorRelease {
  Release() {
    final files = <String, Object?>{
      for (final name in [
        '__init__.py',
        'codec.py',
        'compiler.py',
        'journal.py',
        'probes.py',
        'runner.py',
        'jobs.py',
        'preflight.py',
        'bridge.py',
        'supervisor.py',
        'qualification.py',
        'apt.py',
        'apt_gate.py',
      ])
        name: hash('synthetic source $name'),
    };
    final lock = hash('synthetic lock'), bridge = hash('synthetic bridge');
    final version = hash({
      'baseVersion': '1.0.0',
      'lockDigest': lock,
      'bridgeDigest': bridge,
      'files': files,
    });
    _descriptor = ExecutorRelease.fromJson({
      'format': 1,
      'runtimeVersion': '1.0.0+$version',
      'lockDigest': lock,
      'bridgeDigest': bridge,
      'compilerDigest': hash({
        'codec.py': files['codec.py'],
        'compiler.py': files['compiler.py'],
      }),
      'files': files,
    });
  }
  late final ExecutorRelease _descriptor;
  int validations = 0;
  bool valid = true;
  @override
  ExecutorRelease get descriptor {
    revalidate();
    return _descriptor;
  }

  @override
  void revalidate() {
    validations++;
    if (!valid) throw StateError('PREREQUISITE_UNAVAILABLE');
  }
}

/// State is behind the SSH byte port, not a domain-service success stub. Requests
/// pass the real framing/request parsers; responses pass the real client parsers.
/// This models a root journal and one MOTD effect, never launches a process.
final class ExecutorBytePeer {
  final release = Release();
  final requests = <Map<String, Object?>>[], errors = <Object>[];
  final preflights = <String, Map<String, Object?>>{};
  final attempts = <String, Attempt>{};
  final registryDigest = hash('synthetic resource registry');
  final bootIdHash = hash('synthetic boot');
  final String hostId = id(3900);
  String motd = 'unit baseline\n';
  bool queueWithoutChallenge = false, unknownAfterAuthorize = false;
  int permits = 0, effects = 0, reconciliations = 0, cancellations = 0;
  String? controlFailure;
  // Faults/latches act on encoded peer replies, never replace domain handlers.
  Future<void> Function(
    Map<String, Object?> request,
    Map<String, Object?> response,
    bytes.Session session,
  )?
  beforeReply;

  void attach(bytes.Session session) {
    final wire = _Wire(this, session);
    session.onInput = wire.receive;
  }

  Attempt _attempt(Map<String, Object?> params) {
    if (controlFailure case final String code) throw _Rejected(code);
    final attempt = attempts[params['attemptId']];
    if (attempt == null) throw _Rejected('NOT_FOUND');
    return attempt;
  }

  Map<String, Object?> observation(
    Map<String, Object?> target,
    String resource,
  ) {
    if (resource != 'system.motd') throw StateError('UNDECLARED_RESOURCE');
    return {
      ...target,
      'resourceId': resource,
      'hostId': hostId,
      'resourceRegistryDigest': registryDigest,
      'observedAt': utcNow().toIso8601String(),
      'status': 'known',
      'value': {
        'exists': true,
        'fileDigest': fileHash(motd),
        'baselineDigest': hash('unit inode metadata'),
        'values': {'text': motd},
      },
    };
  }

  Future<Map<String, Object?>> handle(Map<String, Object?> request) async {
    requireFields(request, {'v', 'id', 'method', 'params'});
    if (request['v'] != 1) throw StateError('INVALID_UNIT_REQUEST_VERSION');
    final method = request['method'] as String,
        params = request['params'] as Map<String, Object?>;
    ExecutorRequest.capture(method, params, requestId: request['id'] as String);
    requests.add(request);
    final descriptor = release.descriptor;
    switch (method) {
      case 'hello':
        if (params['controllerId'] != fixture.workspace ||
            params['workspaceId'] != fixture.workspace)
          throw StateError('UNEXPECTED_CONTROLLER');
        return {
          'hostId': hostId,
          'runtimeVersion': descriptor.runtimeVersion,
          'lockDigest': descriptor.lockDigest,
          'compilerDigest': descriptor.compilerDigest,
          'bridgeDigest': descriptor.bridgeDigest,
          'registryDigest': registryDigest,
          'bootIdHash': bootIdHash,
          'capabilities': {'install': false},
        };
      case 'observe':
        return {
          'observation': observation(
            params['target'] as Map<String, Object?>,
            params['resourceId'] as String,
          ),
        };
      case 'recipes':
        return {
          'hostId': hostId,
          'runtimeVersion': descriptor.runtimeVersion,
          'registryDigest': registryDigest,
          'environment': 'ubuntu24.04-amd64-systemd',
          'installEnabled': false,
          'recipes': <Object?>[],
          'unavailable': [
            for (final name in ['postgresql16', 'clickhouse'])
              {'id': name, 'code': 'QUALIFICATION_REQUIRED'},
          ],
          'prerequisites': {
            'requiresFreshInstall': true,
            'requiresPreflight': true,
            'metadataRefresh': false,
          },
        };
      case 'preflight':
        final body = AutomationBody.fromJson(
          params['profileBody'] as Map<String, Object?>,
        );
        if (await body.digest() != params['profileDigest'])
          throw StateError('PROFILE_DIGEST_MISMATCH');
        final parameters = body.resolveParameters(
          params['parameters'] as Map<String, Object?>,
        );
        final row = observation(
          params['target'] as Map<String, Object?>,
          'system.motd',
        );
        final fingerprint =
            await ManagedResourceObservationRecord.fromTrustedJson(row)
                .fingerprint();
        final capsule = await AutomationPreflightCapsule.fromJson({
          'format': 1,
          'operationId': params['operationId'],
          'hostId': hostId,
          'environment': 'ubuntu24.04-amd64-systemd',
          'profileDigest': params['profileDigest'],
          'inputDigest': hash(parameters),
          'runtimeVersion': descriptor.runtimeVersion,
          'runtimeLockDigest': descriptor.lockDigest,
          'compilerDigest': descriptor.compilerDigest,
          'registryDigest': registryDigest,
          'bootIdHash': bootIdHash,
          'packageSnapshotDigest': hash('unit packages'),
          'expectedPackageSnapshotDigest': hash('unit packages'),
          'netbirdSnapshotDigest': hash('protected unit NetBird'),
          'aptIndexDigests': <String>[],
          'recipes': <Object?>[],
          'baseObservations': [
            {'resourceId': 'system.motd', 'fingerprint': fingerprint},
          ],
        });
        final program = compileAutomation(
          body: body,
          parameters: parameters,
          baselineFingerprints: {'system.motd': fingerprint},
          qualifiedRecipes: {},
        ).toJson();
        final facts = <String, Object?>{
          'planFacts': capsule.toJson(),
          'digest': capsule.digest,
          'effects': program['effects'],
          'checks': program['checks'],
          'reasons': <Object?>[],
          'observations': [row],
        };
        preflights[params['operationId'] as String] = facts;
        return {'operationId': params['operationId'], 'state': 'completed'};
      case 'preflight_get':
        final facts = preflights[params['operationId']];
        if (facts == null) throw StateError('MISSING_PREFLIGHT');
        return {
          'operationId': params['operationId'],
          'state': 'succeeded',
          'result': facts,
        };
      case 'submit':
        final facts = preflights.values.singleWhere(
          (p) => p['digest'] == params['preflightDigest'],
        );
        final attemptId = params['attemptId'] as String;
        final prior = attempts[attemptId];
        if (prior != null) {
          if (hash(prior.input) != hash(params))
            throw StateError('DUPLICATE_SUBMIT_CONFLICT');
        } else {
          attempts[attemptId] = Attempt(
            params,
            facts,
            queueWithoutChallenge,
            unknownAfterAuthorize,
          );
        }
        return {'attemptId': attemptId, 'state': 'queued', 'sequence': 1};
      case 'status':
        return _attempt(params).status();
      case 'authorize_step':
        final attempt = attempts[params['attemptId']]!;
        if (attempt.state != 'waiting' ||
            params['stepId'] != 'e1' ||
            params['planDigest'] != attempt.input['planDigest'] ||
            params['challenge'] != attempt.challenge ||
            params['authorizationEpoch'] != attempt.epoch + 1 ||
            params['expiresAt'] != attempt.expires.toIso8601String() ||
            !utcNow().isBefore(attempt.expires))
          throw StateError('UNAUTHORIZED_ROOT_PERMIT');
        permits++;
        attempt.epoch++;
        if (attempt.uncertain) {
          attempt.state = 'unknown';
          attempt.event('uncertain', 'UNKNOWN_OUTCOME');
        } else {
          final effect = (attempt.facts['effects'] as List).single as Map;
          if (effect['kind'] != 'config_file' ||
              effect['resourceId'] != 'system.motd')
            throw StateError('UNDECLARED_EFFECT');
          motd = renderedConfiguration(
            'system.motd',
            Map<String, Object?>.from(effect['values'] as Map),
          );
          effects++;
          attempt.step = 1;
          attempt.state = 'succeeded';
          attempt.event('launch_committed');
          attempt.event('terminal');
        }
        return {'attemptId': params['attemptId'], 'state': 'running'};
      case 'cancel':
        final attempt = _attempt(params);
        cancellations++;
        attempt.state = 'cancelled';
        attempt.event('cancel_recorded');
        attempt.event('terminal', 'CANCELLED');
        return {'attemptId': params['attemptId'], 'state': 'cancelled'};
      case 'reconcile':
        final attempt = _attempt(params);
        if (!{
          'queued',
          'waiting',
          'unknown',
          'succeeded',
          'failed',
          'cancelled',
        }.contains(attempt.state))
          throw StateError('UNDECLARED_RECONCILIATION');
        reconciliations++;
        // Mirrors jobs.py reconcile when no launch/child has been admitted.
        if ({'queued', 'waiting', 'unknown'}.contains(attempt.state)) {
          attempt.state = 'cancelled';
          attempt.event('recovery');
          attempt.event('terminal', 'CANCELLED');
        }
        return {
          'attemptId': params['attemptId'],
          'state': attempt.state,
          'childrenStopped': true,
          'sequence': attempt.sequence,
        };
      default:
        throw StateError('UNDECLARED_EXECUTOR_METHOD');
    }
  }
}

final class Attempt {
  Attempt(this.input, this.facts, bool queued, this.uncertain)
    : state = queued ? 'queued' : 'waiting' {
    event('waiting');
  }
  final Map<String, Object?> input, facts;
  final bool uncertain;
  String state;
  int sequence = 0, epoch = 0, step = 0, statusCalls = 0;
  final events = <Map<String, Object?>>[];
  late final String challenge = base64Url
      .encode(
        const DartSha256()
            .hashSync(utf8.encode(input['attemptId'] as String))
            .bytes,
      )
      .replaceAll('=', '');
  late final DateTime expires = utcNow().add(const Duration(seconds: 5));
  void event(String kind, [String? code]) {
    events.add({
      'sequence': ++sequence,
      'at': utcNow().toIso8601String(),
      'kind': kind,
      'stepId': kind == 'launch_committed' ? 'e1' : null,
      'code': code,
    });
  }

  Map<String, Object?> status() {
    statusCalls++;
    return {
      'attemptId': input['attemptId'],
      'state': state,
      'stepIndex': step,
      'authorizationEpoch': epoch,
      'sequence': sequence,
      'events': events,
      'checks': state == 'succeeded'
          ? [
              for (final check in facts['checks'] as List)
                {'checkId': (check as Map)['id'], 'passed': true},
            ]
          : <Object?>[],
      'needsAuthorization': state == 'waiting'
          ? {
              'challenge': challenge,
              'stepId': 'e1',
              'planDigest': input['planDigest'],
              'expiresAt': expires.toIso8601String(),
            }
          : null,
      'failureCode': state == 'unknown'
          ? 'UNKNOWN_OUTCOME'
          : state == 'cancelled'
          ? 'CANCELLED'
          : null,
      'droppedEvents': 0,
    };
  }
}

final class _Rejected implements Exception {
  _Rejected(this.code) {
    if (!executorCodes.contains(code))
      throw StateError('UNDECLARED_UNIT_ROOT_ERROR');
  }
  final String code;
}

final class _Wire {
  _Wire(this.peer, this.session);
  final ExecutorBytePeer peer;
  final bytes.Session session;
  final buffer = <int>[];
  Future<void> tail = Future.value();
  void receive(Uint8List chunk) {
    buffer.addAll(chunk);
    while (buffer.length >= 4) {
      final length = ByteData.sublistView(
        Uint8List.fromList(buffer.take(4).toList()),
      ).getUint32(0, Endian.big);
      if (length < 1 || length > 256 * 1024)
        throw StateError('INVALID_UNIT_REQUEST_LENGTH');
      if (buffer.length < length + 4) return;
      final payload = buffer.sublist(4, length + 4);
      buffer.removeRange(0, length + 4);
      tail = tail
          .then((_) async {
            final request = StrictCodec().decode(payload, maxBytes: 256 * 1024);
            Map<String, Object?> response;
            try {
              final result = await peer.handle(request);
              await peer.beforeReply?.call(request, result, session);
              response = {'id': request['id'], 'result': result};
            } on _Rejected catch (error) {
              response = {
                'id': request['id'],
                'error': {'code': error.code, 'retry': false},
              };
            }
            if (session.finishing) return;
            final body = Uint8List.fromList(
              StrictCodec().encode(response, maxBytes: 8 << 20),
            );
            final header = Uint8List(4);
            ByteData.sublistView(header).setUint32(0, body.length, Endian.big);
            for (final part in [
              header.sublist(0, 1),
              header.sublist(1),
              body.sublist(0, 3),
              body.sublist(3),
            ]) {
              session.output.add(part);
            }
          })
          .catchError((Object error) {
            peer.errors.add(error);
            session.exitCode = 1;
            session.close();
          });
    }
  }
}
