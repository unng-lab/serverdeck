import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:isar_community/isar.dart';

import 'models.dart';
import 'records.dart';

const _terminal = {'succeeded', 'failed', 'cancelled'};
const _transitions = {
  'queued': {'preflight', 'cancelled'},
  'preflight': {'awaiting-approval', 'failed', 'cancelled'},
  'awaiting-approval': {'running', 'cancelled'},
  'running': {'succeeded', 'failed', 'cancel-requested', 'unknown'},
  'cancel-requested': {'unknown'},
  'unknown': {'reconciling'},
  'reconciling': {'succeeded', 'failed', 'cancelled', 'unknown'},
  'succeeded': <String>{},
  'failed': <String>{},
  'cancelled': <String>{},
};

String secureId() {
  final random = Random.secure();
  return List.generate(
    32,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Exclusively owned by locald, with atomic job/event/identity-lock writes.
final class LocalStore {
  LocalStore._(this._isar);
  final Isar _isar;
  static Future<LocalStore> open({
    required String directory,
    required String nativeLibraryPath,
    String name = 'serverdeck',
  }) async {
    await Directory(directory).create(recursive: true);
    final abi = Abi.current();
    await Isar.initializeIsarCore(
      libraries: {abi: nativeLibraryPath},
      download: false,
    );
    final isar = await Isar.open(
      [
        ProfileRecordSchema,
        JobRecordSchema,
        HostLockRecordSchema,
        EventRecordSchema,
        MetadataRecordSchema,
      ],
      directory: directory,
      name: name,
      relaxedDurability: false,
      inspector: false,
    );
    try {
      await isar.writeTxn(() async {
        final metadata = await isar.metadataRecords.get(1);
        if (metadata != null && metadata.schemaVersion != 1) {
          throw const LocalApiException('UnsupportedSchema');
        }
        if (metadata == null) {
          await isar.metadataRecords.put(MetadataRecord());
        }
      });
      return LocalStore._(isar);
    } catch (_) {
      await isar.close();
      rethrow;
    }
  }

  Future<void> close() async {
    await _isar.close();
  }

  Future<JsonMap> desktopSettings() async {
    final metadata = (await _isar.metadataRecords.get(1))!;
    return metadata.desktopSettingsJson == null
        ? {'theme': 'dark', 'updateAutoCheck': true}
        : jsonDecode(metadata.desktopSettingsJson!) as JsonMap;
  }

  Future<void> patchDesktopSettings(JsonMap patch) => _isar.writeTxn(() async {
    final metadata = (await _isar.metadataRecords.get(1))!;
    final previous = metadata.desktopSettingsJson == null
        ? <String, dynamic>{'theme': 'dark', 'updateAutoCheck': true}
        : jsonDecode(metadata.desktopSettingsJson!) as JsonMap;
    metadata.desktopSettingsJson = jsonEncode({...previous, ...patch});
    await _isar.metadataRecords.put(metadata);
  });

  Future<List<JsonMap>> profiles() async =>
      (await _isar.profileRecords.where().findAll())
          .map((r) => jsonDecode(r.payload) as JsonMap)
          .toList();

  Future<void> initializeProfiles(List<JsonMap> seeds) async {
    final validated = seeds.map(validateProfile).toList();
    if (validated.isEmpty ||
        validated.length > 250 ||
        validated.map((p) => p['id']).toSet().length != validated.length) {
      throw const LocalApiException('InvalidProfile');
    }
    await _isar.writeTxn(() async {
      final metadata = (await _isar.metadataRecords.get(1))!;
      if (metadata.profilesInitialized) {
        return;
      }
      for (final seed in validated) {
        await _isar.profileRecords.put(
          ProfileRecord()
            ..profileId = seed['id'] as String
            ..payload = jsonEncode(seed),
        );
      }
      metadata.profilesInitialized = true;
      await _isar.metadataRecords.put(metadata);
    });
  }

  Future<void> saveProfile(JsonMap profile) async {
    final value = validateProfile(profile);
    await _isar.writeTxn(() async {
      final existing = await _isar.profileRecords.getByProfileId(
        value['id'] as String,
      );
      if (existing == null && await _isar.profileRecords.count() >= 250) {
        throw const LocalApiException('ProfileLimit');
      }
      final record = existing ?? ProfileRecord();
      record.profileId = value['id'] as String;
      record.payload = jsonEncode(value);
      await _isar.profileRecords.put(record);
    });
  }

  Future<void> removeProfile(String id) async {
    await _isar.writeTxn(() async {
      if (await _isar.profileRecords.getByProfileId(id) == null) {
        throw const LocalApiException('NotFound');
      }
      if (await _isar.profileRecords.count() <= 1) {
        throw const LocalApiException('LastProfile');
      }
      await _isar.profileRecords.deleteByProfileId(id);
    });
  }

  Future<JobRecord> _job(String id) async =>
      await _isar.jobRecords.getByJobId(id) ??
      (throw const LocalApiException('NotFound'));
  JsonMap _jobJson(JobRecord job) => {
    'id': job.jobId,
    'idempotencyKey': job.idempotencyKey,
    'plan': jsonDecode(job.inputJson),
    'inputHash': job.inputHash,
    'phase': job.phase,
    'containerId': job.containerId,
    'createdAt': job.createdAt.toUtc().toIso8601String(),
  };
  Future<JsonMap> getJob(String id) async => _jobJson(await _job(id));
  Future<List<JsonMap>> jobs() async =>
      (await _isar.jobRecords
              .where()
              .sortByCreatedAtDesc()
              .limit(1000)
              .findAll())
          .map(_jobJson)
          .toList();

  Future<String> submit(JobPlan plan, String idempotencyKey) async {
    plan.validate();
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(idempotencyKey)) {
      throw const LocalApiException('InvalidIdempotencyKey');
    }
    final inputJson = canonicalPlan(plan);
    final hash = sha256.convert(utf8.encode(inputJson)).toString();
    return _isar.writeTxn(() async {
      final existing = await _isar.jobRecords.getByIdempotencyKey(
        idempotencyKey,
      );
      if (existing != null) {
        if (existing.inputHash != hash) {
          throw const LocalApiException('IdempotencyConflict');
        }
        return existing.jobId;
      }
      if (await _isar.hostLockRecords.getByFingerprint(plan.hostFingerprint) !=
          null) {
        throw const LocalApiException('HostLocked');
      }
      final job = JobRecord()
        ..jobId = secureId()
        ..idempotencyKey = idempotencyKey
        ..inputJson = inputJson
        ..inputHash = hash
        ..fingerprint = plan.hostFingerprint
        ..phase = 'queued'
        ..createdAt = DateTime.now().toUtc();
      await _isar.jobRecords.put(job);
      await _isar.hostLockRecords.put(
        HostLockRecord()
          ..fingerprint = plan.hostFingerprint
          ..jobId = job.jobId,
      );
      await _event(job, 'submitted');
      return job.jobId;
    });
  }

  Future<void> _event(
    JobRecord job,
    String code, [
    ProbeEvidence? evidence,
  ]) async {
    job.sequence++;
    await _isar.jobRecords.put(job);
    await _isar.eventRecords.put(
      EventRecord()
        ..jobId = job.jobId
        ..sequence = job.sequence
        ..phase = job.phase
        ..code = code
        ..evidenceJson = evidence == null ? null : jsonEncode(evidence.toJson())
        ..at = DateTime.now().toUtc(),
    );
  }

  Future<void> _transition(
    JobRecord job,
    String target,
    String code, [
    ProbeEvidence? evidence,
  ]) async {
    if (!(_transitions[job.phase]?.contains(target) ?? false)) {
      throw const LocalApiException('IllegalPhase');
    }
    job.phase = target;
    await _event(job, code, evidence);
    if (_terminal.contains(target)) {
      await _isar.hostLockRecords.deleteByFingerprint(job.fingerprint);
    }
  }

  Future<void> preflight(String id) => _isar.writeTxn(
    () async => _transition(await _job(id), 'preflight', 'preflight-started'),
  );
  Future<void> reviewed(String id) => _isar.writeTxn(
    () async =>
        _transition(await _job(id), 'awaiting-approval', 'preflight-reviewed'),
  );
  Future<void> approveAndLaunch(String id) async {
    await _job(id);
    throw const LocalApiException('ExecutionDisabled');
  }

  Future<void> requestCancel(String id) => _isar.writeTxn(() async {
    final job = await _job(id);
    if (_terminal.contains(job.phase) || job.phase == 'cancel-requested') {
      return;
    }
    if ({'queued', 'preflight', 'awaiting-approval'}.contains(job.phase)) {
      await _transition(job, 'cancelled', 'cancelled-before-writes');
    } else if (job.phase == 'running') {
      await _transition(job, 'cancel-requested', 'stop-requested-no-rollback');
    } else {
      throw const LocalApiException('ReconciliationRequired');
    }
  });
  Future<void> lostExecution(String id) => _isar.writeTxn(
    () async =>
        _transition(await _job(id), 'unknown', 'execution-unobservable'),
  );
  Future<void> beginReconcile(String id) => _isar.writeTxn(
    () async =>
        _transition(await _job(id), 'reconciling', 'reconciliation-started'),
  );

  // Only the service's future trusted probe adapter may call these methods.
  // Neither probe evidence nor running transitions are accepted over Local API.
  Future<void> finish(String id, ProbeEvidence evidence) => _isar.writeTxn(
    () async {
      final job = await _job(id);
      if (!{'running', 'reconciling'}.contains(job.phase)) {
        throw const LocalApiException('IllegalPhase');
      }
      if (!evidence.executionStopped || !evidence.remoteLockClear) {
        await _transition(job, 'unknown', 'remote-outcome-uncertain', evidence);
        return;
      }
      final plan = JobPlan.fromJson(jsonDecode(job.inputJson) as JsonMap);
      final verified =
          evidence.version == plan.version &&
          evidence.unitActive &&
          evidence.applicationHealthy;
      await _transition(
        job,
        verified ? 'succeeded' : 'failed',
        verified ? 'postconditions-verified' : 'postconditions-failed',
        evidence,
      );
    },
  );
  Future<void> confirmCancelled(String id, ProbeEvidence evidence) =>
      _isar.writeTxn(() async {
        final job = await _job(id);
        if (job.phase != 'reconciling') {
          throw const LocalApiException('IllegalPhase');
        }
        final stopped = evidence.executionStopped && evidence.remoteLockClear;
        await _transition(
          job,
          stopped ? 'cancelled' : 'unknown',
          stopped
              ? 'stopped-partial-effects-not-rolled-back'
              : 'cancel-outcome-uncertain',
          evidence,
        );
      });
  Future<List<JsonMap>> events(
    String id, {
    int after = 0,
    int limit = 100,
  }) async {
    if (after < 0 || limit < 1 || limit > 1000) {
      throw const LocalApiException('InvalidPage');
    }
    return (await _isar.eventRecords
            .filter()
            .jobIdEqualTo(id)
            .sequenceGreaterThan(after)
            .sortBySequence()
            .limit(limit)
            .findAll())
        .map(
          (e) => <String, dynamic>{
            'jobId': e.jobId,
            'sequence': e.sequence,
            'phase': e.phase,
            'code': e.code,
            'evidence': e.evidenceJson == null
                ? null
                : jsonDecode(e.evidenceJson!),
            'at': e.at.toUtc().toIso8601String(),
          },
        )
        .toList();
  }
}
