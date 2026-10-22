import 'dart:convert';

import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';

import '../storage/models.dart';
import '../storage/host_trust_models.dart';

Never _blocked() => throw StateError('STORAGE_BLOCKED');
T _get<T>(Map<String, T> values, String key) => values[key] ?? _blocked();
Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : _blocked();

/// Native adapter input. The logical loader neither opens Isar nor validates
/// filesystem/DPAPI custody; startup must compose those independent gates.
final class AutomationSnapshotRow {
  const AutomationSnapshotRow(this.nativeId, this.entityId, this.payload);
  final int nativeId;
  final String entityId, payload;
}

/// Complete retained metadata graph. Successful historical loading never grants
/// current execution permission or attests compiler/remote outcome evidence.
final class AutomationSnapshot {
  AutomationSnapshot._(_Loader loader)
    : grants = Map.unmodifiable(loader.grants),
      delegations = Map.unmodifiable(loader.delegations),
      profiles = Map.unmodifiable(loader.profiles),
      revisions = Map.unmodifiable(loader.revisions),
      plans = Map.unmodifiable(loader.plans),
      approvals = Map.unmodifiable(loader.approvals),
      jobs = Map.unmodifiable(loader.jobs),
      desired = Map.unmodifiable(loader.desired),
      events = Map.unmodifiable(loader.events),
      receipts = Map.unmodifiable(loader.receipts);

  static Future<AutomationSnapshot> load({
    required WorkspaceState foundation,
    required Map<String, List<AutomationSnapshotRow>> collections,
  }) async {
    // Schema2 native loading uses its closed schema1 foundation compatibility
    // model. A schema3 state must never silently select a different plan parser.
    if (foundation.schemaVersion != 1) throw StateError('INCOMPATIBLE');
    return _load(foundation, collections, trusted: false);
  }

  /// Schema3 retained history only. The supplied foundation/trust graph is
  /// already structurally bound; native custody and live authority are separate.
  static Future<AutomationSnapshot> loadTrusted({
    required HostTrustState foundation,
    required Map<String, List<AutomationSnapshotRow>> collections,
  }) => _load(foundation.foundation, collections, trusted: true);

  static Future<AutomationSnapshot> _load(
    WorkspaceState foundation,
    Map<String, List<AutomationSnapshotRow>> collections, {
    required bool trusted,
  }) async {
    try {
      // Capture the complete caller-owned input and foundation identity sets
      // synchronously before any async body/capsule/plan digest validation.
      final loader = _Loader(foundation, collections, trusted: trusted);
      await loader.parse();
      loader.references();
      return AutomationSnapshot._(loader);
    } on FormatException {
      _blocked();
    } on StateError {
      _blocked();
    }
  }

  final Map<String, ClientGrantRecord> grants;
  final Map<String, DelegationRecord> delegations;
  final Map<String, AutomationProfileRecord> profiles;
  final Map<String, AutomationRevisionRecord> revisions;
  final Map<String, AutomationPlanRecord> plans;
  final Map<String, AutomationApprovalRecord> approvals;
  final Map<String, AutomationJobRecord> jobs;
  final Map<String, AutomationDesiredStateRecord> desired;
  final Map<String, AutomationJobEventRecord> events;
  final Map<String, AutomationMutationReceiptRecord> receipts;
}

final class _Loader {
  _Loader(
    WorkspaceState foundation,
    Map<String, List<AutomationSnapshotRow>> input, {
    required this.trusted,
  }) : workspace = foundation.workspaceId,
       currentServers = Set.of(foundation.profiles.keys) {
    knownServers.addAll(currentServers);
    for (final receipt in foundation.receipts.values) {
      if (receipt.operation == 'profiles.delete' && receipt.result.deleted) {
        final doc = receipt.toJson();
        if (receipt.result.entityId != doc['profileId'] ||
            receipt.result.entityId == null)
          _blocked();
        knownServers.add(receipt.result.entityId!);
      }
    }
    final limits = {
      'grants': 32,
      'delegations': 1000,
      'profiles': 250,
      'revisions': 5000,
      'plans': 1000,
      'approvals': 100,
      'jobs': 1250,
      'desired': knownServers.length * 5,
      'events': 10000,
      'receipts': 10000,
    };
    if (input.length != limits.length || !limits.keys.every(input.containsKey))
      _blocked();
    var totalBytes = 0;
    for (final entry in limits.entries) {
      final source = input[entry.key]!;
      if (source.length > entry.value) _blocked();
      final collection = <String, Map<String, Object?>>{};
      final nativeIds = <int>{};
      final bound = switch (entry.key) {
        'events' => 4096,
        'receipts' => 8192,
        _ => 256 * 1024,
      };
      for (final row in source) {
        if (row.nativeId < 1 ||
            row.nativeId > 9223372036854775807 ||
            !nativeIds.add(row.nativeId) ||
            collection.containsKey(row.entityId))
          _blocked();
        final bytes = utf8.encode(row.payload);
        totalBytes += bytes.length;
        if (bytes.length > bound || totalBytes > 64 * 1024 * 1024) _blocked();
        StrictCodec().canonical(row.payload); // Reject malformed UTF16 too.
        final value = StrictCodec().decode(bytes, maxBytes: bound);
        if (value['workspaceId'] != workspace) _blocked();
        final key = switch (entry.key) {
          'revisions' => '${value['profileId']}:${value['revision']}',
          'events' => '${value['jobId']}:${value['sequence']}',
          'receipts' => value['requestId'],
          _ => value['id'],
        };
        if (key != row.entityId) _blocked();
        collection[row.entityId] = value;
      }
      raw[entry.key] = collection;
    }
  }

  final String workspace;
  final Set<String> currentServers, knownServers = {};
  final raw = <String, Map<String, Map<String, Object?>>>{};
  final grants = <String, ClientGrantRecord>{};
  final delegations = <String, DelegationRecord>{};
  final profiles = <String, AutomationProfileRecord>{};
  final revisions = <String, AutomationRevisionRecord>{};
  final plans = <String, AutomationPlanRecord>{};
  final approvals = <String, AutomationApprovalRecord>{};
  final jobs = <String, AutomationJobRecord>{};
  final desired = <String, AutomationDesiredStateRecord>{};
  final events = <String, AutomationJobEventRecord>{};
  final receipts = <String, AutomationMutationReceiptRecord>{};
  final bool trusted;

  void parseSync<T>(
    String name,
    Map<String, T> output,
    T Function(Map<String, Object?>) parse,
  ) {
    for (final entry in raw[name]!.entries) {
      output[entry.key] = parse(entry.value);
    }
  }

  Future<void> parse() async {
    parseSync('grants', grants, ClientGrantRecord.fromJson);
    parseSync('delegations', delegations, DelegationRecord.fromJson);
    parseSync('profiles', profiles, AutomationProfileRecord.fromJson);
    for (final entry in raw['revisions']!.entries) {
      revisions[entry.key] = await AutomationRevisionRecord.fromJson(
        entry.value,
      );
    }
    for (final entry in raw['plans']!.entries) {
      final revision = _get(
        revisions,
        '${entry.value['profileId']}:${entry.value['profileRevision']}',
      );
      plans[entry.key] = trusted
          ? await AutomationPlanRecord.fromTrustedJson(
              entry.value,
              revision: revision,
            )
          : await AutomationPlanRecord.fromJson(
              entry.value,
              revision: revision,
            );
    }
    parseSync('approvals', approvals, AutomationApprovalRecord.fromJson);
    parseSync('jobs', jobs, AutomationJobRecord.fromJson);
    parseSync('desired', desired, AutomationDesiredStateRecord.fromJson);
    parseSync('events', events, AutomationJobEventRecord.fromJson);
    parseSync('receipts', receipts, AutomationMutationReceiptRecord.fromJson);
  }

  void grant(String? id) {
    if (id != null) _get(grants, id);
  }

  void server(String id) {
    if (!knownServers.contains(id)) _blocked();
  }

  Map<String, Object?> planJson(String id) => _get(plans, id).toJson();
  void atOrAfter(DateTime value, DateTime created) {
    if (value.isBefore(created)) _blocked();
  }

  void knownGrantAuthorityAt(String? id, DateTime time) {
    if (id == null) return;
    final grant = _get(grants, id);
    if (grant.revokedAt != null && time.isAfter(grant.revokedAt!)) _blocked();
    // Earlier operations can belong to an unknown prior issuance. Never use
    // current issuedAt as their lower bound or replay today's mutable policy.
    if (!time.isBefore(grant.issuedAt) && !time.isBefore(grant.expiresAt))
      _blocked();
  }

  bool knownGrantEpoch(ClientGrantRecord grant, DateTime time) {
    final neverReplaced =
        grant.revision == 1 || grant.revision == 2 && grant.revokedAt != null;
    return time.isAfter(grant.issuedAt) ||
        time == grant.issuedAt && neverReplaced;
  }

  void knownGrantScopeAt(
    String? id,
    DateTime time,
    McpScope scope, {
    Iterable<String> targets = const [],
  }) {
    if (id == null) return;
    final grant = _get(grants, id);
    if (knownGrantEpoch(grant, time) &&
        (!grant.policy.allowsScope(scope) ||
            !grant.policy.serverIds.containsAll(targets)))
      _blocked();
  }

  void references() {
    final secretRefs = <String>{};
    for (final row in grants.values) {
      if (!secretRefs.add(row.secretRef)) _blocked();
      row.policy.serverIds.forEach(server);
    }
    for (final row in profiles.values) {
      if (row.headRevision > 20) _blocked();
      DateTime? previous;
      for (var n = 1; n <= row.headRevision; n++) {
        final revision = _get(revisions, '${row.id}:$n');
        if (previous != null) atOrAfter(revision.createdAt, previous);
        previous = revision.createdAt;
      }
    }
    for (final row in revisions.values) {
      if (_get(profiles, row.key.profileId).headRevision < row.key.revision)
        _blocked();
      grant(row.authorGrantId);
    }
    for (final row in delegations.values) {
      grant(row.grantId);
      row.serverIds.forEach(server);
      for (final key in row.profileRevisions) {
        if (_get(revisions, '${key.profileId}:${key.revision}').key != key)
          _blocked();
      }
    }
    for (final row in plans.values) {
      grant(row.toJson()['originGrantId'] as String?);
      server(row.serverId);
    }
    for (final row in approvals.values) {
      knownGrantAuthorityAt(row.grantId, row.createdAt);
      final plan = _get(plans, row.planId), doc = planJson(row.planId);
      row.validatePlanIdentity(
        workspaceId: workspace,
        planId: plan.id,
        digest: doc['digest'] as String,
        originGrantId: doc['originGrantId'] as String?,
        planCreatedAt: plan.createdAt,
        planExpiresAt: plan.expiresAt,
      );
      knownGrantScopeAt(
        row.grantId,
        row.createdAt,
        McpScope.apply,
        targets: [plan.serverId],
      );
    }
    validateJobs();
    validateDesired();
    validateEvents();
    validateReceipts();
  }

  void validateJobs() {
    final usedPlans = <String>{},
        attempts = <String>{},
        occupiedHosts = <String>{},
        occupiedServers = <String>{};
    var terminal = 0, active = 0;
    for (final job in jobs.values) {
      final plan = _get(plans, job.immutablePlanId),
          doc = planJson(job.immutablePlanId);
      if (plan.status != 'runnable' ||
          !usedPlans.add(plan.id) ||
          !attempts.add(job.hostAttemptId) ||
          !plan.isWithinLifetimeAt(job.createdAt))
        _blocked();
      job.validatePlanIdentity(
        workspaceId: workspace,
        planId: plan.id,
        digest: doc['digest'] as String,
        profileKey: plan.key,
        originGrantId: doc['originGrantId'] as String?,
      );
      knownGrantAuthorityAt(job.grantId, job.createdAt);
      knownGrantScopeAt(
        job.grantId,
        job.createdAt,
        McpScope.apply,
        targets: [plan.serverId],
      );
      if (const {'succeeded', 'failed', 'cancelled'}.contains(job.state)) {
        terminal++;
      } else {
        active++;
        if (!currentServers.contains(plan.serverId) ||
            !occupiedHosts.add(plan.hostId!) ||
            !occupiedServers.add(plan.serverId))
          _blocked();
      }
      final checks = {
        for (final raw in doc['checks'] as List)
          _object(raw)['id']: _object(raw),
      };
      for (final check in job.outcome?.checks ?? <AutomationJobCheck>[]) {
        if (checks[check.checkId]?['effectId'] != check.stepId) _blocked();
      }
      if (job.authority.kind == 'approval') {
        final approval = _get(approvals, job.authority.id);
        if (approval.state != 'consumed' ||
            approval.jobId != job.id ||
            approval.planId != plan.id ||
            approval.grantId != job.grantId ||
            job.createdAt.isBefore(approval.createdAt) ||
            !job.createdAt.isBefore(approval.expiresAt))
          _blocked();
      } else {
        final delegation = _get(delegations, job.authority.id);
        final params = _object(doc['exactParams']);
        if (delegation.grantId != job.grantId ||
            // Only create revision1 issues authority; revision2 is revoke-only.
            job.authority.revision != 1 ||
            job.authority.revision > delegation.revision ||
            !job.createdAt.isBefore(delegation.expiresAt) ||
            delegation.revokedAt != null &&
                job.createdAt.isAfter(delegation.revokedAt!) ||
            !delegation.profileRevisions.contains(plan.key) ||
            !delegation.serverIds.contains(plan.serverId) ||
            params.length != delegation.predicates.length ||
            delegation.predicates.entries.any(
              (entry) =>
                  !params.containsKey(entry.key) ||
                  !entry.value.matches(params[entry.key]),
            ))
          _blocked();
      }
    }
    if (terminal > 1000 || active > 250) _blocked();
    for (final row in approvals.values.where(
      (row) => row.state == 'consumed',
    )) {
      final job = _get(jobs, row.jobId!);
      if (job.authority.kind != 'approval' || job.authority.id != row.id)
        _blocked();
    }
  }

  void validateDesired() {
    final identities = <String>{};
    for (final row in desired.values) {
      final job = _get(jobs, row.lastJobId),
          plan = _get(plans, job.immutablePlanId),
          doc = planJson(plan.id);
      final resources = <String>{
        for (final raw in doc['effects'] as List)
          if (_object(raw)['resourceId'] case final String id) id,
        for (final recipe in plan.preflight!.recipes) ...recipe.ownedResources,
      };
      if (!managedResourceIds.contains(row.resourceId) ||
          !identities.add('${row.serverId}:${row.resourceId}'))
        _blocked();
      row.validateConfirmedJobIdentity(
        job,
        planId: plan.id,
        planDigest: doc['digest'] as String,
        planServerId: plan.serverId,
        resolvedInputDigest: doc['inputDigest'] as String,
        ownedResources: resources,
      );
    }
  }

  void validateEvents() {
    final grouped = <String, List<AutomationJobEventRecord>>{};
    for (final event in events.values) {
      (grouped[event.jobId] ??= []).add(event);
    }
    for (final entry in grouped.entries) {
      final job = _get(jobs, entry.key);
      final steps = {
        for (final raw in planJson(job.immutablePlanId)['effects'] as List)
          _object(raw)['id'],
      };
      entry.value.sort((a, b) => a.sequence.compareTo(b.sequence));
      AutomationJobEventRecord? previous;
      for (final event in entry.value) {
        event.validateJobIdentity(
          job,
          previousSequence: previous?.sequence,
          previousTimestamp: previous?.timestamp,
        );
        if (event.timestamp.isBefore(job.createdAt) ||
            event.timestamp.isAfter(job.updatedAt) ||
            event.stepId != null && !steps.contains(event.stepId))
          _blocked();
        previous = event;
      }
    }
  }

  void validateReceipts() {
    final byOperation = <String, List<AutomationMutationReceiptRecord>>{};
    for (final row in receipts.values) {
      grant(row.originGrantId);
      grant(row.objectGrantId);
      for (final id in {row.originGrantId, row.objectGrantId}) {
        if (id != null) atOrAfter(row.createdAt, _get(grants, id).createdAt);
      }
      knownGrantAuthorityAt(row.originGrantId, row.createdAt);
      (byOperation[row.operation] ??= []).add(row);
      final result = row.result;
      switch (row.operation.split('.').first) {
        case 'grant':
          final object = _get(grants, result['grantId'] as String);
          if (object.revision < (result['revision'] as int)) _blocked();
          atOrAfter(row.createdAt, object.createdAt);
        case 'delegation':
          final object = _get(delegations, result['delegationId'] as String);
          if (row.objectGrantId != object.grantId ||
              object.revision < (result['revision'] as int))
            _blocked();
        case 'profile':
          knownGrantScopeAt(row.originGrantId, row.createdAt, McpScope.author);
          final profile = _get(profiles, result['profileId'] as String);
          final revision = _get(
            revisions,
            '${profile.id}:${result['revision']}',
          );
          atOrAfter(row.createdAt, revision.createdAt);
          if (row.operation == 'profile.archive') {
            if (!profile.archived) _blocked();
          } else if (result['digest'] != revision.key.bodyDigest ||
              row.originGrantId != revision.authorGrantId) {
            _blocked();
          }
        case 'plan':
          final plan = _get(plans, result['planId'] as String),
              doc = planJson(plan.id);
          if (result['planDigest'] != doc['digest'] ||
              row.objectGrantId != doc['originGrantId'] ||
              row.originGrantId != doc['originGrantId'])
            _blocked();
          atOrAfter(row.createdAt, plan.createdAt);
          knownGrantScopeAt(
            row.originGrantId,
            row.createdAt,
            McpScope.plan,
            targets: [plan.serverId],
          );
        case 'approval':
          final approval = _get(approvals, result['approvalId'] as String);
          row.validateApprovalIdentity(approval);
          atOrAfter(row.createdAt, approval.createdAt);
          if (row.operation == 'approval.request')
            knownGrantScopeAt(
              row.originGrantId,
              row.createdAt,
              McpScope.apply,
              targets: [_get(plans, approval.planId).serverId],
            );
        case 'job':
          final job = _get(jobs, result['jobId'] as String);
          row.validateJobIdentity(job);
          atOrAfter(row.createdAt, job.createdAt);
          knownGrantScopeAt(
            row.originGrantId,
            row.createdAt,
            row.operation == 'job.reconcile' ? McpScope.read : McpScope.apply,
            targets: [_get(plans, job.immutablePlanId).serverId],
          );
        default:
          _blocked();
      }
    }
    List<AutomationMutationReceiptRecord> matching(
      String operation,
      String field,
      Object? id,
    ) => (byOperation[operation] ?? [])
        .where((row) => row.result[field] == id)
        .toList();
    void creation(
      String operation,
      String field,
      String id,
      DateTime time, {
      String? requestId,
    }) {
      final found = matching(operation, field, id)
          .where(
            (row) =>
                row.createdAt == time &&
                (requestId == null || row.requestId == requestId),
          )
          .toList();
      if (found.length != 1) _blocked();
    }

    for (final object in grants.values) {
      final history =
          <AutomationMutationReceiptRecord>[
            for (final op in ['grant.create', 'grant.replace', 'grant.revoke'])
              ...matching(op, 'grantId', object.id),
          ]..sort(
            (a, b) => (a.result['revision'] as int).compareTo(
              b.result['revision'] as int,
            ),
          );
      if (history.length != object.revision) _blocked();
      DateTime? previous, issued;
      for (var i = 0; i < history.length; i++) {
        final row = history[i];
        if (row.result['revision'] != i + 1 ||
            (i == 0
                ? row.operation != 'grant.create' ||
                      row.createdAt != object.createdAt
                : row.operation != 'grant.replace' &&
                      row.operation != 'grant.revoke') ||
            previous != null && row.createdAt.isBefore(previous))
          _blocked();
        if (row.operation == 'grant.revoke') {
          if (i != history.length - 1 || object.revokedAt != row.createdAt)
            _blocked();
        } else {
          issued = row.createdAt;
        }
        previous = row.createdAt;
      }
      if (issued != object.issuedAt ||
          (object.revokedAt != null) !=
              (history.last.operation == 'grant.revoke'))
        _blocked();
    }
    for (final object in delegations.values) {
      final creates = matching('delegation.create', 'delegationId', object.id);
      if (creates.length != 1 || creates.single.result['revision'] != 1)
        _blocked();
      final issued = creates.single.createdAt,
          lifetime = object.expiresAt.difference(issued);
      for (final key in object.profileRevisions) {
        atOrAfter(
          issued,
          _get(revisions, '${key.profileId}:${key.revision}').createdAt,
        );
      }
      knownGrantAuthorityAt(object.grantId, issued);
      final issuer = _get(grants, object.grantId);
      final knownEpoch = knownGrantEpoch(issuer, issued);
      if (knownEpoch && object.expiresAt.isAfter(issuer.expiresAt)) _blocked();
      knownGrantScopeAt(
        object.grantId,
        issued,
        McpScope.apply,
        targets: object.serverIds,
      );
      for (final job in jobs.values.where(
        (job) =>
            job.authority.kind == 'delegation' && job.authority.id == object.id,
      )) {
        atOrAfter(job.createdAt, issued);
      }
      if (lifetime < const Duration(minutes: 5) ||
          lifetime > const Duration(hours: 24))
        _blocked();
      final revokes = matching('delegation.revoke', 'delegationId', object.id);
      if (object.revokedAt == null
          ? object.revision != 1 || revokes.isNotEmpty
          : object.revision != 2 ||
                revokes.length != 1 ||
                revokes.single.result['revision'] != 2 ||
                revokes.single.createdAt != object.revokedAt ||
                object.revokedAt!.isBefore(issued))
        _blocked();
    }
    for (final object in revisions.values) {
      // Same-millisecond revisions are disambiguated by exact revision below.
      final found =
          matching(
                object.key.revision == 1 ? 'profile.create' : 'profile.update',
                'profileId',
                object.key.profileId,
              )
              .where(
                (row) =>
                    row.result['revision'] == object.key.revision &&
                    row.createdAt == object.createdAt,
              )
              .toList();
      if (found.length != 1) _blocked();
    }
    for (final object in profiles.values.where((row) => row.archived)) {
      if (matching('profile.archive', 'profileId', object.id).isEmpty)
        _blocked();
    }
    for (final object in plans.values) {
      creation(
        'plan.create',
        'planId',
        object.id,
        object.createdAt,
        requestId: object.toJson()['requestId'] as String,
      );
    }
    for (final object in approvals.values) {
      creation('approval.request', 'approvalId', object.id, object.createdAt);
      final decisions = matching('approval.decide', 'approvalId', object.id)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (const {'approved', 'consumed', 'denied'}.contains(object.state) &&
              decisions.isEmpty ||
          object.state == 'pending' && decisions.isNotEmpty)
        _blocked();
      if (decisions.isNotEmpty) {
        final first = decisions.first;
        if (first.result['decision'] == 'approved') {
          knownGrantAuthorityAt(object.grantId, first.createdAt);
          knownGrantScopeAt(
            object.grantId,
            first.createdAt,
            McpScope.apply,
            targets: [_get(plans, object.planId).serverId],
          );
        }
        if (!first.createdAt.isBefore(object.expiresAt) ||
            decisions.any(
              (row) => row.result['decision'] != first.result['decision'],
            ) ||
            object.state == 'consumed' &&
                first.createdAt.isAfter(_get(jobs, object.jobId!).createdAt))
          _blocked();
      }
    }
    for (final object in jobs.values) {
      creation(
        'job.apply',
        'jobId',
        object.id,
        object.createdAt,
        requestId: object.requestId,
      );
    }
  }
}
