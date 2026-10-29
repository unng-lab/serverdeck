// T033: explicit applicability and planned test contracts, never runtime proof.
// Production sections/controllers remain the only implementation under test.

enum DesignStateCategory {
  loading,
  successfulEmpty,
  data,
  validation,
  denied,
  unsupported,
  stale,
  dropped,
  incomplete,
  localUnavailable,
  sshUnavailable,
  unknown,
}

enum DesignStateResult { notRun, passed, failed }

enum DesignStateScope {
  productionPresentation,
  localOwnerIntegration,
  privateEpochComposition,
}

enum DesignStateMeaning {
  readiness,
  localSnapshot,
  localMutation,
  remoteObservation,
  localRecord,
  trustWrite,
  automationRead,
  automationWrite,
  planInvalidation,
  jobOutcome,
  confirmedReceipts,
  privateRetirement,
}

class DesignStateSource {
  const DesignStateSource(this.path, this.anchor);
  final String path, anchor;
}

sealed class DesignStateCell {
  const DesignStateCell();
}

class DesignStateApplicable extends DesignStateCell {
  const DesignStateApplicable(this.caseIds);
  final List<String> caseIds;
}

class DesignStateNotApplicable extends DesignStateCell {
  const DesignStateNotApplicable({required this.reason, required this.source});
  final String reason;
  final DesignStateSource source;
}

/// No unnamed/default state: each origin must decide all twelve categories.
class DesignStateOrigin {
  const DesignStateOrigin({
    required this.originId,
    required this.loading,
    required this.successfulEmpty,
    required this.data,
    required this.validation,
    required this.denied,
    required this.unsupported,
    required this.stale,
    required this.dropped,
    required this.incomplete,
    required this.localUnavailable,
    required this.sshUnavailable,
    required this.unknown,
  });
  final String originId;
  final DesignStateCell loading,
      successfulEmpty,
      data,
      validation,
      denied,
      unsupported,
      stale,
      dropped,
      incomplete,
      localUnavailable,
      sshUnavailable,
      unknown;

  Map<DesignStateCategory, DesignStateCell> get cells => {
    DesignStateCategory.loading: loading,
    DesignStateCategory.successfulEmpty: successfulEmpty,
    DesignStateCategory.data: data,
    DesignStateCategory.validation: validation,
    DesignStateCategory.denied: denied,
    DesignStateCategory.unsupported: unsupported,
    DesignStateCategory.stale: stale,
    DesignStateCategory.dropped: dropped,
    DesignStateCategory.incomplete: incomplete,
    DesignStateCategory.localUnavailable: localUnavailable,
    DesignStateCategory.sshUnavailable: sshUnavailable,
    DesignStateCategory.unknown: unknown,
  };
}

/// An expected delta at the named observable UI boundary, not an RPC assertion.
/// Existing owner initialization/polling is counted separately by real providers.
class DesignStateAction {
  const DesignStateAction(this.trigger, this.counter, this.expectedDelta);
  final String trigger, counter;
  final int expectedDelta;
}

const designStatePassiveCounters = <DesignStateAction>[
  DesignStateAction('render', 'additionalUiInitiatedOwnerActions', 0),
  DesignStateAction('theme-change', 'additionalUiInitiatedOwnerActions', 0),
  DesignStateAction('resize', 'additionalUiInitiatedOwnerActions', 0),
];

class DesignStateCase {
  const DesignStateCase({
    required this.caseId,
    required this.originId,
    required this.category,
    required this.taskId,
    required this.owner,
    required this.sources,
    required this.phase,
    required this.expectations,
    required this.actions,
    required this.meaning,
    required this.scope,
  });
  final String caseId, originId, taskId, owner, phase;
  final DesignStateCategory category;
  final List<DesignStateSource> sources;
  final List<String> expectations;
  final List<DesignStateAction> actions;
  final DesignStateMeaning meaning;
  final DesignStateScope scope;
  DesignStateResult get result => DesignStateResult.notRun;
  List<DesignStateAction> get passiveCounters => designStatePassiveCounters;
  String get verificationTest => taskId == 'T037'
      ? 'test/widget/design_privacy_test.dart'
      : 'test/widget/design_state_test.dart';
  String get command => 'flutter test $verificationTest --plain-name "$caseId"';
  String get limitation =>
      'Planned assertion contract only. Import/registry checks do not execute a '
      'state case. Callback counts do not prove RPC identity, native effects, '
      'authorization, SSH or durable recovery; real owner providers must state '
      'their measured boundaries and count existing lifecycle work separately.';
}

/// A future provider may persist this only after its actual test has run.
/// There is no default result, fabricated callback or success constructor.
class DesignStateExecutionRecord {
  const DesignStateExecutionRecord({
    required this.caseId,
    required this.testPath,
    required this.command,
    required this.result,
    required this.scope,
    required this.actualCounters,
    required this.assertions,
    required this.evidence,
  });
  final String caseId, testPath, command, evidence;
  final DesignStateResult result;
  final DesignStateScope scope;
  final Map<String, int> actualCounters;
  final List<String> assertions;
}

// T033 adds no actual execution record. T034–T038 provide and execute tests.
const designStateExecutionRecords = <DesignStateExecutionRecord>[];

const _originSource01 = DesignStateSource(
  'lib/shell/readiness_view.dart',
  'class ReadinessView',
);
const _originSource02 = DesignStateSource(
  'lib/shell/readiness_view.dart',
  'class ReadinessView',
);
const _originSource03 = DesignStateSource(
  'lib/shell/readiness_view.dart',
  'class ReadinessView',
);
const _originSource04 = DesignStateSource(
  'lib/profiles/profile_list.dart',
  'class ProfileList',
);
const _originSource05 = DesignStateSource(
  'lib/profiles/profile_list.dart',
  'class ProfileList',
);
const _originSource07 = DesignStateSource(
  'lib/profiles/profile_form.dart',
  'class ProfileForm',
);
const _originSource08 = DesignStateSource(
  'lib/profiles/profile_form.dart',
  'class ProfileForm',
);
const _originSource09 = DesignStateSource(
  'lib/profiles/profile_delete.dart',
  'class ProfileDelete',
);
const _originSource10 = DesignStateSource(
  'lib/servers/server_sections.dart',
  'class ServerTrustConfirmation',
);
const _originSource12 = DesignStateSource(
  'lib/profiles/credential_input.dart',
  'class CredentialInput',
);
const _originSource13 = DesignStateSource(
  'lib/profiles/mutation_status.dart',
  'class MutationStatus',
);
const _originSource16 = DesignStateSource(
  'lib/software/software_panel.dart',
  'class SoftwarePanel',
);
const _originSource17 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationRecipesSection',
);
const _originSource18 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationPlanSection',
);
const _originSource19 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationPlanDecisionDialog',
);
const _originSource22 = DesignStateSource(
  'lib/servers/server_sections.dart',
  'class ServerLogsSection',
);
const _originSource23 = DesignStateSource(
  'lib/servers/server_sections.dart',
  'class ServerLogRecordDialog',
);
const _originSource27 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationJobsSection',
);
const _originSource28 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationJobsSection',
);
const _originSource29 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationJobsSection',
);
const _originSource30 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationJobsSection',
);
const _originSource31 = DesignStateSource(
  'lib/profiles/recovery_view.dart',
  'class RecentOperationsView',
);
const _originSource32 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationProfilesSection',
);
const _originSource33 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationProfileEditorDialog',
);
const _originSource34 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationProfileDetailSection',
);
const _originSource35 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationJsonEditorDialog',
);
const _originSource36 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationGrantsSection',
);
const _originSource37 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationJsonEditorDialog',
);
const _originSource38 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationGrantsSection',
);
const _originSource39 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationAuthoritiesSection',
);
const _originSource40 = DesignStateSource(
  'lib/servers/server_sections.dart',
  'class ServerExecutorConfirmation',
);
const _originSource84 = DesignStateSource(
  'lib/settings/settings_view.dart',
  'class SettingsView',
);
const _originSource85 = DesignStateSource(
  'lib/settings/settings_form.dart',
  'class SettingsForm',
);
const _originSource94 = DesignStateSource(
  'lib/automation/automation_sections.dart',
  'class AutomationPlanSection',
);

const designStateOrigins = <DesignStateOrigin>[
  DesignStateOrigin(
    originId: '01-startup',
    loading: DesignStateApplicable(['state-01-startup-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '01-startup / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource01,
    ),
    data: DesignStateNotApplicable(
      reason: '01-startup / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource01,
    ),
    validation: DesignStateApplicable(['state-01-startup-validation']),
    denied: DesignStateApplicable(['state-01-startup-denied']),
    unsupported: DesignStateApplicable(['state-01-startup-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '01-startup / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource01,
    ),
    dropped: DesignStateNotApplicable(
      reason: '01-startup / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource01,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '01-startup / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource01,
    ),
    localUnavailable: DesignStateApplicable([
      'state-01-startup-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '01-startup / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource01,
    ),
    unknown: DesignStateNotApplicable(
      reason: '01-startup / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource01,
    ),
  ),
  DesignStateOrigin(
    originId: '02-service-unavailable',
    loading: DesignStateApplicable(['state-02-service-unavailable-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '02-service-unavailable / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource02,
    ),
    data: DesignStateNotApplicable(
      reason: '02-service-unavailable / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource02,
    ),
    validation: DesignStateApplicable([
      'state-02-service-unavailable-validation',
    ]),
    denied: DesignStateApplicable(['state-02-service-unavailable-denied']),
    unsupported: DesignStateApplicable([
      'state-02-service-unavailable-unsupported',
    ]),
    stale: DesignStateNotApplicable(
      reason: '02-service-unavailable / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource02,
    ),
    dropped: DesignStateNotApplicable(
      reason: '02-service-unavailable / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource02,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '02-service-unavailable / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource02,
    ),
    localUnavailable: DesignStateApplicable([
      'state-02-service-unavailable-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '02-service-unavailable / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource02,
    ),
    unknown: DesignStateNotApplicable(
      reason: '02-service-unavailable / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource02,
    ),
  ),
  DesignStateOrigin(
    originId: '03-storage-blocked',
    loading: DesignStateApplicable(['state-03-storage-blocked-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '03-storage-blocked / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource03,
    ),
    data: DesignStateNotApplicable(
      reason: '03-storage-blocked / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource03,
    ),
    validation: DesignStateApplicable(['state-03-storage-blocked-validation']),
    denied: DesignStateApplicable(['state-03-storage-blocked-denied']),
    unsupported: DesignStateApplicable([
      'state-03-storage-blocked-unsupported',
    ]),
    stale: DesignStateNotApplicable(
      reason: '03-storage-blocked / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource03,
    ),
    dropped: DesignStateNotApplicable(
      reason: '03-storage-blocked / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource03,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '03-storage-blocked / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource03,
    ),
    localUnavailable: DesignStateApplicable([
      'state-03-storage-blocked-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '03-storage-blocked / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource03,
    ),
    unknown: DesignStateNotApplicable(
      reason: '03-storage-blocked / ReadinessView: Public non-ready readiness has no private collection, remote observation, event stream or durable intent.',
      source: _originSource03,
    ),
  ),
  DesignStateOrigin(
    originId: '04-empty-workspace',
    loading: DesignStateApplicable(['state-04-empty-workspace-loading']),
    successfulEmpty: DesignStateApplicable([
      'state-04-empty-workspace-successfulEmpty',
    ]),
    data: DesignStateApplicable(['state-04-empty-workspace-data']),
    validation: DesignStateApplicable(['state-04-empty-workspace-validation']),
    denied: DesignStateApplicable(['state-04-empty-workspace-denied']),
    unsupported: DesignStateApplicable([
      'state-04-empty-workspace-unsupported',
    ]),
    stale: DesignStateNotApplicable(
      reason: '04-empty-workspace / ProfileList / ProfileController: ProfileController accepts a coherent current local snapshot; it has no observation freshness/TTL. Old revisions are ignored; malformed snapshots are errors.',
      source: _originSource04,
    ),
    dropped: DesignStateNotApplicable(
      reason: '04-empty-workspace / ProfileList / ProfileController: This local draft/snapshot/status has no event cursor or dropped counter. A resource bound does not mean lost events.',
      source: _originSource04,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '04-empty-workspace / ProfileList / ProfileController: The local snapshot/result is accepted as a whole. Missing data is loading/error; write readback is not an incomplete observation.',
      source: _originSource04,
    ),
    localUnavailable: DesignStateApplicable([
      'state-04-empty-workspace-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '04-empty-workspace / ProfileList / ProfileController: Local profiles/settings/receipts remain available without SSH. An absent trusted client does not establish SSH connection state.',
      source: _originSource04,
    ),
    unknown: DesignStateNotApplicable(
      reason: '04-empty-workspace / ProfileList / ProfileController: This read-only local owner has no durable intent whose lost reply it can resolve.',
      source: _originSource04,
    ),
  ),
  DesignStateOrigin(
    originId: '05-server-list',
    loading: DesignStateApplicable(['state-05-server-list-loading']),
    successfulEmpty: DesignStateApplicable([
      'state-05-server-list-successfulEmpty',
    ]),
    data: DesignStateApplicable(['state-05-server-list-data']),
    validation: DesignStateApplicable(['state-05-server-list-validation']),
    denied: DesignStateApplicable(['state-05-server-list-denied']),
    unsupported: DesignStateApplicable(['state-05-server-list-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '05-server-list / ProfileList / ProfileController: ProfileController accepts a coherent current local snapshot; it has no observation freshness/TTL. Old revisions are ignored; malformed snapshots are errors.',
      source: _originSource05,
    ),
    dropped: DesignStateNotApplicable(
      reason: '05-server-list / ProfileList / ProfileController: This local draft/snapshot/status has no event cursor or dropped counter. A resource bound does not mean lost events.',
      source: _originSource05,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '05-server-list / ProfileList / ProfileController: The local snapshot/result is accepted as a whole. Missing data is loading/error; write readback is not an incomplete observation.',
      source: _originSource05,
    ),
    localUnavailable: DesignStateApplicable([
      'state-05-server-list-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '05-server-list / ProfileList / ProfileController: Local profiles/settings/receipts remain available without SSH. An absent trusted client does not establish SSH connection state.',
      source: _originSource05,
    ),
    unknown: DesignStateNotApplicable(
      reason: '05-server-list / ProfileList / ProfileController: This read-only local owner has no durable intent whose lost reply it can resolve.',
      source: _originSource05,
    ),
  ),
  DesignStateOrigin(
    originId: '06-server-overview',
    loading: DesignStateApplicable(['state-06-server-overview-loading']),
    successfulEmpty: DesignStateApplicable([
      'state-06-server-overview-successfulEmpty',
    ]),
    data: DesignStateApplicable(['state-06-server-overview-data']),
    validation: DesignStateApplicable(['state-06-server-overview-validation']),
    denied: DesignStateApplicable(['state-06-server-overview-denied']),
    unsupported: DesignStateApplicable([
      'state-06-server-overview-unsupported',
    ]),
    stale: DesignStateApplicable(['state-06-server-overview-stale']),
    dropped: DesignStateApplicable(['state-06-server-overview-dropped']),
    incomplete: DesignStateApplicable(['state-06-server-overview-incomplete']),
    localUnavailable: DesignStateApplicable([
      'state-06-server-overview-localUnavailable',
    ]),
    sshUnavailable: DesignStateApplicable([
      'state-06-server-overview-sshUnavailable',
    ]),
    unknown: DesignStateApplicable(['state-06-server-overview-unknown']),
  ),
  DesignStateOrigin(
    originId: '07-profile-create',
    loading: DesignStateApplicable(['state-07-profile-create-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '07-profile-create / ProfileForm / MutationController: An empty editable draft is not a successfully obtained empty collection.',
      source: _originSource07,
    ),
    data: DesignStateApplicable(['state-07-profile-create-data']),
    validation: DesignStateApplicable(['state-07-profile-create-validation']),
    denied: DesignStateApplicable(['state-07-profile-create-denied']),
    unsupported: DesignStateApplicable(['state-07-profile-create-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '07-profile-create / ProfileForm / MutationController: A captured revision or draft is not an observation. Revision mismatch is CAS validation/conflict, not stale data.',
      source: _originSource07,
    ),
    dropped: DesignStateNotApplicable(
      reason: '07-profile-create / ProfileForm / MutationController: This local draft/snapshot/status has no event cursor or dropped counter. A resource bound does not mean lost events.',
      source: _originSource07,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '07-profile-create / ProfileForm / MutationController: The local snapshot/result is accepted as a whole. Missing data is loading/error; write readback is not an incomplete observation.',
      source: _originSource07,
    ),
    localUnavailable: DesignStateApplicable([
      'state-07-profile-create-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '07-profile-create / ProfileForm / MutationController: Local profiles/settings/receipts remain available without SSH. An absent trusted client does not establish SSH connection state.',
      source: _originSource07,
    ),
    unknown: DesignStateApplicable(['state-07-profile-create-unknown']),
  ),
  DesignStateOrigin(
    originId: '08-profile-edit',
    loading: DesignStateApplicable(['state-08-profile-edit-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '08-profile-edit / ProfileForm / MutationController: An empty editable draft is not a successfully obtained empty collection.',
      source: _originSource08,
    ),
    data: DesignStateApplicable(['state-08-profile-edit-data']),
    validation: DesignStateApplicable(['state-08-profile-edit-validation']),
    denied: DesignStateApplicable(['state-08-profile-edit-denied']),
    unsupported: DesignStateApplicable(['state-08-profile-edit-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '08-profile-edit / ProfileForm / MutationController: A captured revision or draft is not an observation. Revision mismatch is CAS validation/conflict, not stale data.',
      source: _originSource08,
    ),
    dropped: DesignStateNotApplicable(
      reason: '08-profile-edit / ProfileForm / MutationController: This local draft/snapshot/status has no event cursor or dropped counter. A resource bound does not mean lost events.',
      source: _originSource08,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '08-profile-edit / ProfileForm / MutationController: The local snapshot/result is accepted as a whole. Missing data is loading/error; write readback is not an incomplete observation.',
      source: _originSource08,
    ),
    localUnavailable: DesignStateApplicable([
      'state-08-profile-edit-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '08-profile-edit / ProfileForm / MutationController: Local profiles/settings/receipts remain available without SSH. An absent trusted client does not establish SSH connection state.',
      source: _originSource08,
    ),
    unknown: DesignStateApplicable(['state-08-profile-edit-unknown']),
  ),
  DesignStateOrigin(
    originId: '09-profile-delete',
    loading: DesignStateApplicable(['state-09-profile-delete-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '09-profile-delete / ProfileDelete / MutationController: Deletion has one required target. Its disappearance after reread is not successful collection emptiness.',
      source: _originSource09,
    ),
    data: DesignStateApplicable(['state-09-profile-delete-data']),
    validation: DesignStateApplicable(['state-09-profile-delete-validation']),
    denied: DesignStateApplicable(['state-09-profile-delete-denied']),
    unsupported: DesignStateApplicable(['state-09-profile-delete-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '09-profile-delete / ProfileDelete / MutationController: A captured revision or draft is not an observation. Revision mismatch is CAS validation/conflict, not stale data.',
      source: _originSource09,
    ),
    dropped: DesignStateNotApplicable(
      reason: '09-profile-delete / ProfileDelete / MutationController: This local draft/snapshot/status has no event cursor or dropped counter. A resource bound does not mean lost events.',
      source: _originSource09,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '09-profile-delete / ProfileDelete / MutationController: The local snapshot/result is accepted as a whole. Missing data is loading/error; write readback is not an incomplete observation.',
      source: _originSource09,
    ),
    localUnavailable: DesignStateApplicable([
      'state-09-profile-delete-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '09-profile-delete / ProfileDelete / MutationController: Local profiles/settings/receipts remain available without SSH. An absent trusted client does not establish SSH connection state.',
      source: _originSource09,
    ),
    unknown: DesignStateApplicable(['state-09-profile-delete-unknown']),
  ),
  DesignStateOrigin(
    originId: '10-host-trust',
    loading: DesignStateApplicable(['state-10-host-trust-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '10-host-trust / ServerTrustConfirmation / ServerPanel / ServerController: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource10,
    ),
    data: DesignStateApplicable(['state-10-host-trust-data']),
    validation: DesignStateApplicable(['state-10-host-trust-validation']),
    denied: DesignStateApplicable(['state-10-host-trust-denied']),
    unsupported: DesignStateApplicable(['state-10-host-trust-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '10-host-trust / ServerTrustConfirmation / ServerPanel / ServerController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource10,
    ),
    dropped: DesignStateNotApplicable(
      reason: '10-host-trust / ServerTrustConfirmation / ServerPanel / ServerController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource10,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '10-host-trust / ServerTrustConfirmation / ServerPanel / ServerController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource10,
    ),
    localUnavailable: DesignStateApplicable([
      'state-10-host-trust-localUnavailable',
    ]),
    sshUnavailable: DesignStateApplicable([
      'state-10-host-trust-sshUnavailable',
    ]),
    unknown: DesignStateApplicable(['state-10-host-trust-unknown']),
  ),
  DesignStateOrigin(
    originId: '12-credential-input',
    loading: DesignStateApplicable(['state-12-credential-input-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '12-credential-input / CredentialInput in ProfileForm / MutationController: An empty editable draft is not a successfully obtained empty collection.',
      source: _originSource12,
    ),
    data: DesignStateApplicable(['state-12-credential-input-data']),
    validation: DesignStateApplicable(['state-12-credential-input-validation']),
    denied: DesignStateApplicable(['state-12-credential-input-denied']),
    unsupported: DesignStateApplicable([
      'state-12-credential-input-unsupported',
    ]),
    stale: DesignStateNotApplicable(
      reason: '12-credential-input / CredentialInput in ProfileForm / MutationController: A captured revision or draft is not an observation. Revision mismatch is CAS validation/conflict, not stale data.',
      source: _originSource12,
    ),
    dropped: DesignStateNotApplicable(
      reason: '12-credential-input / CredentialInput in ProfileForm / MutationController: This local draft/snapshot/status has no event cursor or dropped counter. A resource bound does not mean lost events.',
      source: _originSource12,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '12-credential-input / CredentialInput in ProfileForm / MutationController: The local snapshot/result is accepted as a whole. Missing data is loading/error; write readback is not an incomplete observation.',
      source: _originSource12,
    ),
    localUnavailable: DesignStateApplicable([
      'state-12-credential-input-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '12-credential-input / CredentialInput in ProfileForm / MutationController: Local profiles/settings/receipts remain available without SSH. An absent trusted client does not establish SSH connection state.',
      source: _originSource12,
    ),
    unknown: DesignStateApplicable(['state-12-credential-input-unknown']),
  ),
  DesignStateOrigin(
    originId: '13-mutation-conflict',
    loading: DesignStateApplicable(['state-13-mutation-conflict-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '13-mutation-conflict / MutationStatus / MutationController in owning form: MutationPresentation.idle means no active status, not a successful empty read.',
      source: _originSource13,
    ),
    data: DesignStateApplicable(['state-13-mutation-conflict-data']),
    validation: DesignStateApplicable([
      'state-13-mutation-conflict-validation',
    ]),
    denied: DesignStateApplicable(['state-13-mutation-conflict-denied']),
    unsupported: DesignStateApplicable([
      'state-13-mutation-conflict-unsupported',
    ]),
    stale: DesignStateNotApplicable(
      reason: '13-mutation-conflict / MutationStatus / MutationController in owning form: A captured revision or draft is not an observation. Revision mismatch is CAS validation/conflict, not stale data.',
      source: _originSource13,
    ),
    dropped: DesignStateNotApplicable(
      reason: '13-mutation-conflict / MutationStatus / MutationController in owning form: This local draft/snapshot/status has no event cursor or dropped counter. A resource bound does not mean lost events.',
      source: _originSource13,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '13-mutation-conflict / MutationStatus / MutationController in owning form: The local snapshot/result is accepted as a whole. Missing data is loading/error; write readback is not an incomplete observation.',
      source: _originSource13,
    ),
    localUnavailable: DesignStateApplicable([
      'state-13-mutation-conflict-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '13-mutation-conflict / MutationStatus / MutationController in owning form: Local profiles/settings/receipts remain available without SSH. An absent trusted client does not establish SSH connection state.',
      source: _originSource13,
    ),
    unknown: DesignStateApplicable(['state-13-mutation-conflict-unknown']),
  ),
  DesignStateOrigin(
    originId: '16-install-catalog',
    loading: DesignStateApplicable(['state-16-install-catalog-loading']),
    successfulEmpty: DesignStateApplicable([
      'state-16-install-catalog-successfulEmpty',
    ]),
    data: DesignStateApplicable(['state-16-install-catalog-data']),
    validation: DesignStateNotApplicable(
      reason: '16-install-catalog / SoftwarePanel / AutomationRecipesSection / AutomationPanel: This obtained read-only section or consent body has no input validation. Owner errors and invalid consent are covered in their actual phases.',
      source: _originSource16,
    ),
    denied: DesignStateApplicable(['state-16-install-catalog-denied']),
    unsupported: DesignStateApplicable([
      'state-16-install-catalog-unsupported',
    ]),
    stale: DesignStateNotApplicable(
      reason: '16-install-catalog / SoftwarePanel / AutomationRecipesSection / AutomationPanel: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource16,
    ),
    dropped: DesignStateNotApplicable(
      reason: '16-install-catalog / SoftwarePanel / AutomationRecipesSection / AutomationPanel: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource16,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '16-install-catalog / SoftwarePanel / AutomationRecipesSection / AutomationPanel: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource16,
    ),
    localUnavailable: DesignStateApplicable([
      'state-16-install-catalog-localUnavailable',
    ]),
    sshUnavailable: DesignStateApplicable([
      'state-16-install-catalog-sshUnavailable',
    ]),
    unknown: DesignStateApplicable(['state-16-install-catalog-unknown']),
  ),
  DesignStateOrigin(
    originId: '17-recipe-detail',
    loading: DesignStateApplicable(['state-17-recipe-detail-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '17-recipe-detail / AutomationRecipesSection / AutomationPanel: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource17,
    ),
    data: DesignStateApplicable(['state-17-recipe-detail-data']),
    validation: DesignStateNotApplicable(
      reason: '17-recipe-detail / AutomationRecipesSection / AutomationPanel: This obtained read-only section or consent body has no input validation. Owner errors and invalid consent are covered in their actual phases.',
      source: _originSource17,
    ),
    denied: DesignStateApplicable(['state-17-recipe-detail-denied']),
    unsupported: DesignStateApplicable(['state-17-recipe-detail-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '17-recipe-detail / AutomationRecipesSection / AutomationPanel: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource17,
    ),
    dropped: DesignStateNotApplicable(
      reason: '17-recipe-detail / AutomationRecipesSection / AutomationPanel: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource17,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '17-recipe-detail / AutomationRecipesSection / AutomationPanel: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource17,
    ),
    localUnavailable: DesignStateApplicable([
      'state-17-recipe-detail-localUnavailable',
    ]),
    sshUnavailable: DesignStateApplicable([
      'state-17-recipe-detail-sshUnavailable',
    ]),
    unknown: DesignStateApplicable(['state-17-recipe-detail-unknown']),
  ),
  DesignStateOrigin(
    originId: '18-install-preflight',
    loading: DesignStateApplicable(['state-18-install-preflight-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '18-install-preflight / AutomationPlanSection / AutomationPanel / AutomationController: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource18,
    ),
    data: DesignStateApplicable(['state-18-install-preflight-data']),
    validation: DesignStateApplicable([
      'state-18-install-preflight-validation',
    ]),
    denied: DesignStateApplicable(['state-18-install-preflight-denied']),
    unsupported: DesignStateApplicable([
      'state-18-install-preflight-unsupported',
    ]),
    stale: DesignStateApplicable(['state-18-install-preflight-stale']),
    dropped: DesignStateNotApplicable(
      reason: '18-install-preflight / AutomationPlanSection / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource18,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '18-install-preflight / AutomationPlanSection / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource18,
    ),
    localUnavailable: DesignStateApplicable([
      'state-18-install-preflight-localUnavailable',
    ]),
    sshUnavailable: DesignStateApplicable([
      'state-18-install-preflight-sshUnavailable',
    ]),
    unknown: DesignStateApplicable(['state-18-install-preflight-unknown']),
  ),
  DesignStateOrigin(
    originId: '19-plan-approval',
    loading: DesignStateApplicable(['state-19-plan-approval-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '19-plan-approval / AutomationPlanDecisionDialog / AutomationPanel / AutomationController: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource19,
    ),
    data: DesignStateApplicable(['state-19-plan-approval-data']),
    validation: DesignStateNotApplicable(
      reason: '19-plan-approval / AutomationPlanDecisionDialog / AutomationPanel / AutomationController: This obtained read-only section or consent body has no input validation. Owner errors and invalid consent are covered in their actual phases.',
      source: _originSource19,
    ),
    denied: DesignStateApplicable(['state-19-plan-approval-denied']),
    unsupported: DesignStateApplicable(['state-19-plan-approval-unsupported']),
    stale: DesignStateApplicable(['state-19-plan-approval-stale']),
    dropped: DesignStateNotApplicable(
      reason: '19-plan-approval / AutomationPlanDecisionDialog / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource19,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '19-plan-approval / AutomationPlanDecisionDialog / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource19,
    ),
    localUnavailable: DesignStateApplicable([
      'state-19-plan-approval-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '19-plan-approval / AutomationPlanDecisionDialog / AutomationPanel / AutomationController: This locally retained record/list/approval is available without a live SSH connection. Its owner transport failure is local-unavailable, not SSH offline.',
      source: _originSource19,
    ),
    unknown: DesignStateApplicable(['state-19-plan-approval-unknown']),
  ),
  DesignStateOrigin(
    originId: '22-server-logs',
    loading: DesignStateApplicable(['state-22-server-logs-loading']),
    successfulEmpty: DesignStateApplicable([
      'state-22-server-logs-successfulEmpty',
    ]),
    data: DesignStateApplicable(['state-22-server-logs-data']),
    validation: DesignStateApplicable(['state-22-server-logs-validation']),
    denied: DesignStateApplicable(['state-22-server-logs-denied']),
    unsupported: DesignStateApplicable(['state-22-server-logs-unsupported']),
    stale: DesignStateApplicable(['state-22-server-logs-stale']),
    dropped: DesignStateApplicable(['state-22-server-logs-dropped']),
    incomplete: DesignStateApplicable(['state-22-server-logs-incomplete']),
    localUnavailable: DesignStateApplicable([
      'state-22-server-logs-localUnavailable',
    ]),
    sshUnavailable: DesignStateApplicable([
      'state-22-server-logs-sshUnavailable',
    ]),
    unknown: DesignStateNotApplicable(
      reason: '22-server-logs / ServerLogsSection / ServerPanel / ServerController: This read-only flow has no durable write outcome. Unknown observation quality must not be relabelled as an unknown write.',
      source: _originSource22,
    ),
  ),
  DesignStateOrigin(
    originId: '23-log-record',
    loading: DesignStateNotApplicable(
      reason: '23-log-record / ServerLogRecordDialog, obtained through ServerLogsSection: The selected read-only log record has already been obtained. It owns no request/loading/error handler; acquisition states belong to origin 22-server-logs.',
      source: _originSource23,
    ),
    successfulEmpty: DesignStateNotApplicable(
      reason: '23-log-record / ServerLogRecordDialog, obtained through ServerLogsSection: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource23,
    ),
    data: DesignStateApplicable(['state-23-log-record-data']),
    validation: DesignStateNotApplicable(
      reason: '23-log-record / ServerLogRecordDialog, obtained through ServerLogsSection: This obtained read-only section or consent body has no input validation. Owner errors and invalid consent are covered in their actual phases.',
      source: _originSource23,
    ),
    denied: DesignStateNotApplicable(
      reason: '23-log-record / ServerLogRecordDialog, obtained through ServerLogsSection: The selected read-only log record has already been obtained. It owns no request/loading/error handler; acquisition states belong to origin 22-server-logs.',
      source: _originSource23,
    ),
    unsupported: DesignStateNotApplicable(
      reason: '23-log-record / ServerLogRecordDialog, obtained through ServerLogsSection: The selected read-only log record has already been obtained. It owns no request/loading/error handler; acquisition states belong to origin 22-server-logs.',
      source: _originSource23,
    ),
    stale: DesignStateNotApplicable(
      reason: '23-log-record / ServerLogRecordDialog, obtained through ServerLogsSection: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource23,
    ),
    dropped: DesignStateNotApplicable(
      reason: '23-log-record / ServerLogRecordDialog, obtained through ServerLogsSection: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource23,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '23-log-record / ServerLogRecordDialog, obtained through ServerLogsSection: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource23,
    ),
    localUnavailable: DesignStateApplicable([
      'state-23-log-record-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '23-log-record / ServerLogRecordDialog, obtained through ServerLogsSection: This locally retained record/list/approval is available without a live SSH connection. Its owner transport failure is local-unavailable, not SSH offline.',
      source: _originSource23,
    ),
    unknown: DesignStateNotApplicable(
      reason: '23-log-record / ServerLogRecordDialog, obtained through ServerLogsSection: This read-only flow has no durable write outcome. Unknown observation quality must not be relabelled as an unknown write.',
      source: _originSource23,
    ),
  ),
  DesignStateOrigin(
    originId: '27-job-list',
    loading: DesignStateApplicable(['state-27-job-list-loading']),
    successfulEmpty: DesignStateApplicable([
      'state-27-job-list-successfulEmpty',
    ]),
    data: DesignStateApplicable(['state-27-job-list-data']),
    validation: DesignStateNotApplicable(
      reason: '27-job-list / AutomationJobsSection / AutomationController: This obtained read-only section or consent body has no input validation. Owner errors and invalid consent are covered in their actual phases.',
      source: _originSource27,
    ),
    denied: DesignStateApplicable(['state-27-job-list-denied']),
    unsupported: DesignStateApplicable(['state-27-job-list-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '27-job-list / AutomationJobsSection / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource27,
    ),
    dropped: DesignStateNotApplicable(
      reason: '27-job-list / AutomationJobsSection / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource27,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '27-job-list / AutomationJobsSection / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource27,
    ),
    localUnavailable: DesignStateApplicable([
      'state-27-job-list-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '27-job-list / AutomationJobsSection / AutomationController: This locally retained record/list/approval is available without a live SSH connection. Its owner transport failure is local-unavailable, not SSH offline.',
      source: _originSource27,
    ),
    unknown: DesignStateApplicable(['state-27-job-list-unknown']),
  ),
  DesignStateOrigin(
    originId: '28-job-detail',
    loading: DesignStateApplicable(['state-28-job-detail-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '28-job-detail / AutomationJobsSection / AutomationController: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource28,
    ),
    data: DesignStateApplicable(['state-28-job-detail-data']),
    validation: DesignStateNotApplicable(
      reason: '28-job-detail / AutomationJobsSection / AutomationController: This obtained read-only section or consent body has no input validation. Owner errors and invalid consent are covered in their actual phases.',
      source: _originSource28,
    ),
    denied: DesignStateApplicable(['state-28-job-detail-denied']),
    unsupported: DesignStateApplicable(['state-28-job-detail-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '28-job-detail / AutomationJobsSection / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource28,
    ),
    dropped: DesignStateApplicable(['state-28-job-detail-dropped']),
    incomplete: DesignStateApplicable(['state-28-job-detail-incomplete']),
    localUnavailable: DesignStateApplicable([
      'state-28-job-detail-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '28-job-detail / AutomationJobsSection / AutomationController: This locally retained record/list/approval is available without a live SSH connection. Its owner transport failure is local-unavailable, not SSH offline.',
      source: _originSource28,
    ),
    unknown: DesignStateApplicable(['state-28-job-detail-unknown']),
  ),
  DesignStateOrigin(
    originId: '29-job-unknown',
    loading: DesignStateApplicable(['state-29-job-unknown-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '29-job-unknown / AutomationJobsSection / AutomationController: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource29,
    ),
    data: DesignStateApplicable(['state-29-job-unknown-data']),
    validation: DesignStateNotApplicable(
      reason: '29-job-unknown / AutomationJobsSection / AutomationController: This obtained read-only section or consent body has no input validation. Owner errors and invalid consent are covered in their actual phases.',
      source: _originSource29,
    ),
    denied: DesignStateApplicable(['state-29-job-unknown-denied']),
    unsupported: DesignStateApplicable(['state-29-job-unknown-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '29-job-unknown / AutomationJobsSection / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource29,
    ),
    dropped: DesignStateApplicable(['state-29-job-unknown-dropped']),
    incomplete: DesignStateApplicable(['state-29-job-unknown-incomplete']),
    localUnavailable: DesignStateApplicable([
      'state-29-job-unknown-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '29-job-unknown / AutomationJobsSection / AutomationController: This locally retained record/list/approval is available without a live SSH connection. Its owner transport failure is local-unavailable, not SSH offline.',
      source: _originSource29,
    ),
    unknown: DesignStateApplicable(['state-29-job-unknown-unknown']),
  ),
  DesignStateOrigin(
    originId: '30-job-cancel',
    loading: DesignStateApplicable(['state-30-job-cancel-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '30-job-cancel / AutomationJobsSection / AutomationController: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource30,
    ),
    data: DesignStateApplicable(['state-30-job-cancel-data']),
    validation: DesignStateNotApplicable(
      reason: '30-job-cancel / AutomationJobsSection / AutomationController: This obtained read-only section or consent body has no input validation. Owner errors and invalid consent are covered in their actual phases.',
      source: _originSource30,
    ),
    denied: DesignStateApplicable(['state-30-job-cancel-denied']),
    unsupported: DesignStateApplicable(['state-30-job-cancel-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '30-job-cancel / AutomationJobsSection / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource30,
    ),
    dropped: DesignStateApplicable(['state-30-job-cancel-dropped']),
    incomplete: DesignStateApplicable(['state-30-job-cancel-incomplete']),
    localUnavailable: DesignStateApplicable([
      'state-30-job-cancel-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '30-job-cancel / AutomationJobsSection / AutomationController: This locally retained record/list/approval is available without a live SSH connection. Its owner transport failure is local-unavailable, not SSH offline.',
      source: _originSource30,
    ),
    unknown: DesignStateApplicable(['state-30-job-cancel-unknown']),
  ),
  DesignStateOrigin(
    originId: '31-recent-operations',
    loading: DesignStateApplicable(['state-31-recent-operations-loading']),
    successfulEmpty: DesignStateApplicable([
      'state-31-recent-operations-successfulEmpty',
    ]),
    data: DesignStateApplicable(['state-31-recent-operations-data']),
    validation: DesignStateApplicable([
      'state-31-recent-operations-validation',
    ]),
    denied: DesignStateApplicable(['state-31-recent-operations-denied']),
    unsupported: DesignStateApplicable([
      'state-31-recent-operations-unsupported',
    ]),
    stale: DesignStateNotApplicable(
      reason: '31-recent-operations / RecentOperationsButton / _History / StartupRecovery: Receipt-floor waiting is loading/current-snapshot readback, not observation staleness.',
      source: _originSource31,
    ),
    dropped: DesignStateNotApplicable(
      reason: '31-recent-operations / RecentOperationsButton / _History / StartupRecovery: The bounded 20 receipts and truncated flag describe limited confirmed history, not dropped events.',
      source: _originSource31,
    ),
    incomplete: DesignStateApplicable([
      'state-31-recent-operations-incomplete',
    ]),
    localUnavailable: DesignStateApplicable([
      'state-31-recent-operations-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '31-recent-operations / RecentOperationsButton / _History / StartupRecovery: Local profiles/settings/receipts remain available without SSH. An absent trusted client does not establish SSH connection state.',
      source: _originSource31,
    ),
    unknown: DesignStateNotApplicable(
      reason: '31-recent-operations / RecentOperationsButton / _History / StartupRecovery: These are confirmed receipts; absence does not resolve an unknown write and this list does not reconcile jobs.',
      source: _originSource31,
    ),
  ),
  DesignStateOrigin(
    originId: '32-automation-profiles',
    loading: DesignStateApplicable(['state-32-automation-profiles-loading']),
    successfulEmpty: DesignStateApplicable([
      'state-32-automation-profiles-successfulEmpty',
    ]),
    data: DesignStateApplicable(['state-32-automation-profiles-data']),
    validation: DesignStateNotApplicable(
      reason: '32-automation-profiles / AutomationProfilesSection / AutomationController: This obtained read-only section or consent body has no input validation. Owner errors and invalid consent are covered in their actual phases.',
      source: _originSource32,
    ),
    denied: DesignStateApplicable(['state-32-automation-profiles-denied']),
    unsupported: DesignStateApplicable([
      'state-32-automation-profiles-unsupported',
    ]),
    stale: DesignStateNotApplicable(
      reason: '32-automation-profiles / AutomationProfilesSection / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource32,
    ),
    dropped: DesignStateNotApplicable(
      reason: '32-automation-profiles / AutomationProfilesSection / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource32,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '32-automation-profiles / AutomationProfilesSection / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource32,
    ),
    localUnavailable: DesignStateApplicable([
      'state-32-automation-profiles-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '32-automation-profiles / AutomationProfilesSection / AutomationController: This locally retained record/list/approval is available without a live SSH connection. Its owner transport failure is local-unavailable, not SSH offline.',
      source: _originSource32,
    ),
    unknown: DesignStateNotApplicable(
      reason: '32-automation-profiles / AutomationProfilesSection / AutomationController: This read-only flow has no durable write outcome. Unknown observation quality must not be relabelled as an unknown write.',
      source: _originSource32,
    ),
  ),
  DesignStateOrigin(
    originId: '33-profile-authoring',
    loading: DesignStateApplicable(['state-33-profile-authoring-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '33-profile-authoring / AutomationProfileEditorDialog / AutomationPanel / AutomationController: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource33,
    ),
    data: DesignStateApplicable(['state-33-profile-authoring-data']),
    validation: DesignStateApplicable([
      'state-33-profile-authoring-validation',
    ]),
    denied: DesignStateApplicable(['state-33-profile-authoring-denied']),
    unsupported: DesignStateApplicable([
      'state-33-profile-authoring-unsupported',
    ]),
    stale: DesignStateNotApplicable(
      reason: '33-profile-authoring / AutomationProfileEditorDialog / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource33,
    ),
    dropped: DesignStateNotApplicable(
      reason: '33-profile-authoring / AutomationProfileEditorDialog / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource33,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '33-profile-authoring / AutomationProfileEditorDialog / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource33,
    ),
    localUnavailable: DesignStateApplicable([
      'state-33-profile-authoring-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '33-profile-authoring / AutomationProfileEditorDialog / AutomationPanel / AutomationController: This locally retained record/list/approval is available without a live SSH connection. Its owner transport failure is local-unavailable, not SSH offline.',
      source: _originSource33,
    ),
    unknown: DesignStateApplicable(['state-33-profile-authoring-unknown']),
  ),
  DesignStateOrigin(
    originId: '34-profile-revisions',
    loading: DesignStateApplicable(['state-34-profile-revisions-loading']),
    successfulEmpty: DesignStateApplicable([
      'state-34-profile-revisions-successfulEmpty',
    ]),
    data: DesignStateApplicable(['state-34-profile-revisions-data']),
    validation: DesignStateApplicable([
      'state-34-profile-revisions-validation',
    ]),
    denied: DesignStateApplicable(['state-34-profile-revisions-denied']),
    unsupported: DesignStateApplicable([
      'state-34-profile-revisions-unsupported',
    ]),
    stale: DesignStateNotApplicable(
      reason: '34-profile-revisions / AutomationProfileDetailSection / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource34,
    ),
    dropped: DesignStateNotApplicable(
      reason: '34-profile-revisions / AutomationProfileDetailSection / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource34,
    ),
    incomplete: DesignStateApplicable([
      'state-34-profile-revisions-incomplete',
    ]),
    localUnavailable: DesignStateApplicable([
      'state-34-profile-revisions-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '34-profile-revisions / AutomationProfileDetailSection / AutomationController: This locally retained record/list/approval is available without a live SSH connection. Its owner transport failure is local-unavailable, not SSH offline.',
      source: _originSource34,
    ),
    unknown: DesignStateApplicable(['state-34-profile-revisions-unknown']),
  ),
  DesignStateOrigin(
    originId: '35-plan-parameters',
    loading: DesignStateApplicable(['state-35-plan-parameters-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '35-plan-parameters / AutomationJsonEditorDialog / AutomationPanel / AutomationController: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource35,
    ),
    data: DesignStateApplicable(['state-35-plan-parameters-data']),
    validation: DesignStateApplicable(['state-35-plan-parameters-validation']),
    denied: DesignStateApplicable(['state-35-plan-parameters-denied']),
    unsupported: DesignStateApplicable([
      'state-35-plan-parameters-unsupported',
    ]),
    stale: DesignStateNotApplicable(
      reason: '35-plan-parameters / AutomationJsonEditorDialog / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource35,
    ),
    dropped: DesignStateNotApplicable(
      reason: '35-plan-parameters / AutomationJsonEditorDialog / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource35,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '35-plan-parameters / AutomationJsonEditorDialog / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource35,
    ),
    localUnavailable: DesignStateApplicable([
      'state-35-plan-parameters-localUnavailable',
    ]),
    sshUnavailable: DesignStateApplicable([
      'state-35-plan-parameters-sshUnavailable',
    ]),
    unknown: DesignStateApplicable(['state-35-plan-parameters-unknown']),
  ),
  DesignStateOrigin(
    originId: '36-ai-grants',
    loading: DesignStateApplicable(['state-36-ai-grants-loading']),
    successfulEmpty: DesignStateApplicable([
      'state-36-ai-grants-successfulEmpty',
    ]),
    data: DesignStateApplicable(['state-36-ai-grants-data']),
    validation: DesignStateApplicable(['state-36-ai-grants-validation']),
    denied: DesignStateApplicable(['state-36-ai-grants-denied']),
    unsupported: DesignStateApplicable(['state-36-ai-grants-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '36-ai-grants / AutomationGrantsSection / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource36,
    ),
    dropped: DesignStateNotApplicable(
      reason: '36-ai-grants / AutomationGrantsSection / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource36,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '36-ai-grants / AutomationGrantsSection / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource36,
    ),
    localUnavailable: DesignStateApplicable([
      'state-36-ai-grants-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '36-ai-grants / AutomationGrantsSection / AutomationPanel / AutomationController: This locally retained record/list/approval is available without a live SSH connection. Its owner transport failure is local-unavailable, not SSH offline.',
      source: _originSource36,
    ),
    unknown: DesignStateApplicable(['state-36-ai-grants-unknown']),
  ),
  DesignStateOrigin(
    originId: '37-ai-grant-form',
    loading: DesignStateApplicable(['state-37-ai-grant-form-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '37-ai-grant-form / AutomationJsonEditorDialog / AutomationPanel / AutomationController: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource37,
    ),
    data: DesignStateApplicable(['state-37-ai-grant-form-data']),
    validation: DesignStateApplicable(['state-37-ai-grant-form-validation']),
    denied: DesignStateApplicable(['state-37-ai-grant-form-denied']),
    unsupported: DesignStateApplicable(['state-37-ai-grant-form-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '37-ai-grant-form / AutomationJsonEditorDialog / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource37,
    ),
    dropped: DesignStateNotApplicable(
      reason: '37-ai-grant-form / AutomationJsonEditorDialog / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource37,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '37-ai-grant-form / AutomationJsonEditorDialog / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource37,
    ),
    localUnavailable: DesignStateApplicable([
      'state-37-ai-grant-form-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '37-ai-grant-form / AutomationJsonEditorDialog / AutomationPanel / AutomationController: This locally retained record/list/approval is available without a live SSH connection. Its owner transport failure is local-unavailable, not SSH offline.',
      source: _originSource37,
    ),
    unknown: DesignStateApplicable(['state-37-ai-grant-form-unknown']),
  ),
  DesignStateOrigin(
    originId: '38-mcp-client-config',
    loading: DesignStateApplicable(['state-38-mcp-client-config-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '38-mcp-client-config / AutomationGrantsSection configuration / AutomationController: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource38,
    ),
    data: DesignStateApplicable(['state-38-mcp-client-config-data']),
    validation: DesignStateNotApplicable(
      reason: '38-mcp-client-config / AutomationGrantsSection configuration / AutomationController: This obtained read-only section or consent body has no input validation. Owner errors and invalid consent are covered in their actual phases.',
      source: _originSource38,
    ),
    denied: DesignStateApplicable(['state-38-mcp-client-config-denied']),
    unsupported: DesignStateApplicable([
      'state-38-mcp-client-config-unsupported',
    ]),
    stale: DesignStateNotApplicable(
      reason: '38-mcp-client-config / AutomationGrantsSection configuration / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource38,
    ),
    dropped: DesignStateNotApplicable(
      reason: '38-mcp-client-config / AutomationGrantsSection configuration / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource38,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '38-mcp-client-config / AutomationGrantsSection configuration / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource38,
    ),
    localUnavailable: DesignStateApplicable([
      'state-38-mcp-client-config-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '38-mcp-client-config / AutomationGrantsSection configuration / AutomationController: This locally retained record/list/approval is available without a live SSH connection. Its owner transport failure is local-unavailable, not SSH offline.',
      source: _originSource38,
    ),
    unknown: DesignStateNotApplicable(
      reason: '38-mcp-client-config / AutomationGrantsSection configuration / AutomationController: This read-only flow has no durable write outcome. Unknown observation quality must not be relabelled as an unknown write.',
      source: _originSource38,
    ),
  ),
  DesignStateOrigin(
    originId: '39-delegations',
    loading: DesignStateApplicable(['state-39-delegations-loading']),
    successfulEmpty: DesignStateApplicable([
      'state-39-delegations-successfulEmpty',
    ]),
    data: DesignStateApplicable(['state-39-delegations-data']),
    validation: DesignStateApplicable(['state-39-delegations-validation']),
    denied: DesignStateApplicable(['state-39-delegations-denied']),
    unsupported: DesignStateApplicable(['state-39-delegations-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '39-delegations / AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource39,
    ),
    dropped: DesignStateNotApplicable(
      reason: '39-delegations / AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource39,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '39-delegations / AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource39,
    ),
    localUnavailable: DesignStateApplicable([
      'state-39-delegations-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '39-delegations / AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController: This locally retained record/list/approval is available without a live SSH connection. Its owner transport failure is local-unavailable, not SSH offline.',
      source: _originSource39,
    ),
    unknown: DesignStateApplicable(['state-39-delegations-unknown']),
  ),
  DesignStateOrigin(
    originId: '40-executor-binding',
    loading: DesignStateApplicable(['state-40-executor-binding-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '40-executor-binding / ServerExecutorConfirmation / ServerPanel / ServerController: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource40,
    ),
    data: DesignStateApplicable(['state-40-executor-binding-data']),
    validation: DesignStateApplicable(['state-40-executor-binding-validation']),
    denied: DesignStateApplicable(['state-40-executor-binding-denied']),
    unsupported: DesignStateApplicable([
      'state-40-executor-binding-unsupported',
    ]),
    stale: DesignStateNotApplicable(
      reason: '40-executor-binding / ServerExecutorConfirmation / ServerPanel / ServerController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource40,
    ),
    dropped: DesignStateNotApplicable(
      reason: '40-executor-binding / ServerExecutorConfirmation / ServerPanel / ServerController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource40,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '40-executor-binding / ServerExecutorConfirmation / ServerPanel / ServerController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource40,
    ),
    localUnavailable: DesignStateApplicable([
      'state-40-executor-binding-localUnavailable',
    ]),
    sshUnavailable: DesignStateApplicable([
      'state-40-executor-binding-sshUnavailable',
    ]),
    unknown: DesignStateApplicable(['state-40-executor-binding-unknown']),
  ),
  DesignStateOrigin(
    originId: '84-settings',
    loading: DesignStateApplicable(['state-84-settings-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '84-settings / SettingsView / ProfileController: The settings record is required; a null selected profile is normal settings data, not an absent settings record.',
      source: _originSource84,
    ),
    data: DesignStateApplicable(['state-84-settings-data']),
    validation: DesignStateApplicable(['state-84-settings-validation']),
    denied: DesignStateApplicable(['state-84-settings-denied']),
    unsupported: DesignStateApplicable(['state-84-settings-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '84-settings / SettingsView / ProfileController: ProfileController accepts a coherent current local snapshot; it has no observation freshness/TTL. Old revisions are ignored; malformed snapshots are errors.',
      source: _originSource84,
    ),
    dropped: DesignStateNotApplicable(
      reason: '84-settings / SettingsView / ProfileController: This local draft/snapshot/status has no event cursor or dropped counter. A resource bound does not mean lost events.',
      source: _originSource84,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '84-settings / SettingsView / ProfileController: The local snapshot/result is accepted as a whole. Missing data is loading/error; write readback is not an incomplete observation.',
      source: _originSource84,
    ),
    localUnavailable: DesignStateApplicable([
      'state-84-settings-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '84-settings / SettingsView / ProfileController: Local profiles/settings/receipts remain available without SSH. An absent trusted client does not establish SSH connection state.',
      source: _originSource84,
    ),
    unknown: DesignStateNotApplicable(
      reason: '84-settings / SettingsView / ProfileController: This read-only local owner has no durable intent whose lost reply it can resolve.',
      source: _originSource84,
    ),
  ),
  DesignStateOrigin(
    originId: '85-settings-form',
    loading: DesignStateApplicable(['state-85-settings-form-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '85-settings-form / SettingsForm / MutationController: The settings record is required; a null selected profile is normal settings data, not an absent settings record.',
      source: _originSource85,
    ),
    data: DesignStateApplicable(['state-85-settings-form-data']),
    validation: DesignStateApplicable(['state-85-settings-form-validation']),
    denied: DesignStateApplicable(['state-85-settings-form-denied']),
    unsupported: DesignStateApplicable(['state-85-settings-form-unsupported']),
    stale: DesignStateNotApplicable(
      reason: '85-settings-form / SettingsForm / MutationController: A captured revision or draft is not an observation. Revision mismatch is CAS validation/conflict, not stale data.',
      source: _originSource85,
    ),
    dropped: DesignStateNotApplicable(
      reason: '85-settings-form / SettingsForm / MutationController: This local draft/snapshot/status has no event cursor or dropped counter. A resource bound does not mean lost events.',
      source: _originSource85,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '85-settings-form / SettingsForm / MutationController: The local snapshot/result is accepted as a whole. Missing data is loading/error; write readback is not an incomplete observation.',
      source: _originSource85,
    ),
    localUnavailable: DesignStateApplicable([
      'state-85-settings-form-localUnavailable',
    ]),
    sshUnavailable: DesignStateNotApplicable(
      reason: '85-settings-form / SettingsForm / MutationController: Local profiles/settings/receipts remain available without SSH. An absent trusted client does not establish SSH connection state.',
      source: _originSource85,
    ),
    unknown: DesignStateApplicable(['state-85-settings-form-unknown']),
  ),
  DesignStateOrigin(
    originId: '94-plan-invalidated',
    loading: DesignStateApplicable(['state-94-plan-invalidated-loading']),
    successfulEmpty: DesignStateNotApplicable(
      reason: '94-plan-invalidated / AutomationPlanSection / AutomationPanel / AutomationController: A single required record, inspected target, plan or editable draft cannot be represented by a successful empty collection.',
      source: _originSource94,
    ),
    data: DesignStateApplicable(['state-94-plan-invalidated-data']),
    validation: DesignStateNotApplicable(
      reason: '94-plan-invalidated / AutomationPlanSection / AutomationPanel / AutomationController: This obtained read-only section or consent body has no input validation. Owner errors and invalid consent are covered in their actual phases.',
      source: _originSource94,
    ),
    denied: DesignStateApplicable(['state-94-plan-invalidated-denied']),
    unsupported: DesignStateApplicable([
      'state-94-plan-invalidated-unsupported',
    ]),
    stale: DesignStateApplicable(['state-94-plan-invalidated-stale']),
    dropped: DesignStateNotApplicable(
      reason: '94-plan-invalidated / AutomationPlanSection / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource94,
    ),
    incomplete: DesignStateNotApplicable(
      reason: '94-plan-invalidated / AutomationPlanSection / AutomationPanel / AutomationController: This DTO has no observation quality, dropped count or partial-observation marker for this category. Revision, expiry and pagination are separate domain concepts.',
      source: _originSource94,
    ),
    localUnavailable: DesignStateApplicable([
      'state-94-plan-invalidated-localUnavailable',
    ]),
    sshUnavailable: DesignStateApplicable([
      'state-94-plan-invalidated-sshUnavailable',
    ]),
    unknown: DesignStateNotApplicable(
      reason: '94-plan-invalidated / AutomationPlanSection / AutomationPanel / AutomationController: This read-only flow has no durable write outcome. Unknown observation quality must not be relabelled as an unknown write.',
      source: _originSource94,
    ),
  ),
];

// Explicit shared contract first used by state-01-startup-loading.
const _stateSources001 = <DesignStateSource>[
  DesignStateSource('lib/shell/readiness_view.dart', 'class ReadinessView'),
];

// Explicit shared contract first used by state-01-startup-loading.
const _stateExpectations001 = <String>[
  'Show exact existing readiness stage and static pending symbol under reduced motion; private content is absent.',
  'An in-progress retry has no duplicate invocation.',
];

// Explicit shared contract first used by state-01-startup-loading.
const _stateActions001 = <DesignStateAction>[
  DesignStateAction('activate-pending-retry', 'onRetry', 0),
];

// Explicit shared contract first used by state-01-startup-validation.
const _stateExpectations002 = <String>[
  'Render exact safe reason ErrorCode.validation, role, symbol and existing readiness guidance; this is legal reason presentation, not evidence that every backend failure scenario exists.',
  'Retry is enabled only for unavailable/incompatible/storageBlocked, never an automatic retry; no plaintext/reset for protection failure.',
];

// Explicit shared contract first used by state-01-startup-validation.
const _stateActions002 = <DesignStateAction>[
  DesignStateAction('activate-enabled-retry-on-unavailable', 'onRetry', 1),
];

// Explicit shared contract first used by state-01-startup-denied.
const _stateExpectations003 = <String>[
  'Render exact safe reason ErrorCode.forbidden and ErrorCode.unauthorized, role, symbol and existing readiness guidance; this is legal reason presentation, not evidence that every backend failure scenario exists.',
  'Retry is enabled only for unavailable/incompatible/storageBlocked, never an automatic retry; no plaintext/reset for protection failure.',
];

// Explicit shared contract first used by state-01-startup-unsupported.
const _stateExpectations004 = <String>[
  'Render exact safe reason ErrorCode.unsupported, role, symbol and existing readiness guidance; this is legal reason presentation, not evidence that every backend failure scenario exists.',
  'Retry is enabled only for unavailable/incompatible/storageBlocked, never an automatic retry; no plaintext/reset for protection failure.',
];

// Explicit shared contract first used by state-01-startup-localUnavailable.
const _stateExpectations005 = <String>[
  'Display exact readiness reason, safe next step and status symbol with no private profile/secret/target content.',
  'Protection failure never offers plaintext/reset. Retry on the existing allowed states is explicit and duplicate retry is blocked while pending.',
];

// Explicit shared contract first used by state-01-startup-localUnavailable.
const _stateActions003 = <DesignStateAction>[
  DesignStateAction('activate-enabled-retry-once', 'onRetry', 1),
  DesignStateAction('activate-busy-retry', 'onRetry', 0),
];

// Explicit shared contract first used by state-04-empty-workspace-loading.
const _stateSources002 = <DesignStateSource>[
  DesignStateSource('lib/profiles/profile_list.dart', 'class ProfileList'),
  DesignStateSource(
    'lib/profiles/profile_controller.dart',
    'class ProfileController',
  ),
];

// Explicit shared contract first used by state-04-empty-workspace-loading.
const _stateExpectations006 = <String>[
  'Loading is distinct from an empty collection or null required settings record; no fake zero values.',
  'A delayed old generation does not publish loaded data. Count the real ModelClient read lifecycle separately.',
];

// Explicit shared contract first used by state-04-empty-workspace-loading.
const _stateActions004 = <DesignStateAction>[
  DesignStateAction('rebuild-pending-snapshot', 'uiInitiatedRefresh', 0),
];

// Explicit shared contract first used by state-04-empty-workspace-successfulEmpty.
const _stateExpectations007 = <String>[
  'ProfileController loaded=true with profiles=[]; retain existing create action and explain no local profiles.',
  'No automatic read/mutation/connect is triggered by displaying emptiness.',
];

// Explicit shared contract first used by state-04-empty-workspace-successfulEmpty.
const _stateActions005 = <DesignStateAction>[
  DesignStateAction('no-user-intent', 'explicitActionCallbacks', 0),
];

// Explicit shared contract first used by state-04-empty-workspace-data.
const _stateExpectations008 = <String>[
  'Display actual coherent local profile names/addresses and current selected metadata; no SSH status inferred from selection.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-04-empty-workspace-validation.
const _stateExpectations009 = <String>[
  'Show typed ReadErrorView reason and existing read-again/check-service guidance; do not display failed read as successful empty.',
  'For open history the typed reason remains inside actual modal, not only behind its route.',
];

// Explicit shared contract first used by state-04-empty-workspace-validation.
const _stateActions006 = <DesignStateAction>[
  DesignStateAction('render-validation-guidance', 'automaticReadRetries', 0),
];

// Explicit shared contract first used by state-04-empty-workspace-denied.
const _stateExpectations010 = <String>[
  'Show precise FORBIDDEN/UNAUTHORIZED reason and existing read/service guidance; failed read is not empty.',
  'Already open form/history retains a visible typed reason. No synthetic active permissions handler.',
];

// Explicit shared contract first used by state-04-empty-workspace-denied.
const _stateActions007 = <DesignStateAction>[
  DesignStateAction(
    'render-denied-or-unsupported-guidance',
    'automaticReadRetries',
    0,
  ),
];

// Explicit shared contract first used by state-04-empty-workspace-unsupported.
const _stateExpectations011 = <String>[
  'Show precise UNSUPPORTED reason and existing read/service guidance; failed read is not empty.',
  'Already open form/history retains a visible typed reason. No synthetic active permissions handler.',
];

// Explicit shared contract first used by state-04-empty-workspace-localUnavailable.
const _stateSources003 = <DesignStateSource>[
  DesignStateSource('lib/profiles/profile_list.dart', 'class ProfileList'),
  DesignStateSource(
    'lib/profiles/profile_controller.dart',
    'class ProfileController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-04-empty-workspace-localUnavailable.
const _stateExpectations012 = <String>[
  'Exercise unavailable, storageBlocked, incompatible, connecting, disconnected, closed and unauthorized retirement, including rapid loss/current recovery and old-generation snapshot.',
  'Remove private render, offstage, semantics, tooltip and modal title/target/secret/consent immediately; late picker/Future/receipt cannot reintroduce retired content.',
  'Recovery needs current authorized snapshot; closed needs a new connection. Secret/consent/connect/apply are not restored. Ordinary theme/resize retains live State/draft/route.',
  'Persisted store/trust/history/jobs are not erased. Count legitimate existing refresh/recent reads separately from zero new UI-triggered mutations/connect/apply/consent.',
];

// Explicit shared contract first used by state-04-empty-workspace-localUnavailable.
const _stateActions008 = <DesignStateAction>[
  DesignStateAction(
    'retirement-and-recovery',
    'uiInitiatedMutationConnectApplyConsent',
    0,
  ),
  DesignStateAction('late-retired-completion', 'privateContentReintroduced', 0),
];

// Explicit shared contract first used by state-06-server-overview-loading.
const _stateSources004 = <DesignStateSource>[
  DesignStateSource(
    'lib/servers/server_sections.dart',
    'class ServerOverviewSection',
  ),
  DesignStateSource(
    'lib/servers/server_controller.dart',
    'class ServerController',
  ),
];

// Explicit shared contract first used by state-06-server-overview-loading.
const _stateExpectations013 = <String>[
  'Show existing owner operation label and pending symbol; disable only duplicate same action.',
  'For recipe loading include actual connection/catalog phase. Bare consent/JSON bodies own no fictitious request spinner.',
  'Stop waiting, when provided, drops response interest and does not promise job cancellation.',
];

// Explicit shared contract first used by state-06-server-overview-loading.
const _stateActions009 = <DesignStateAction>[
  DesignStateAction(
    'activate-duplicate-owner-action',
    'sameActionCallbacks',
    0,
  ),
];

// Explicit shared contract first used by state-06-server-overview-successfulEmpty.
const _stateExpectations014 = <String>[
  'A successfully received history=[] with current quality has no samples; it is not missing/unknown metrics and draws no invented zero/line.',
  'No automatic read/mutation/connect is triggered by displaying emptiness.',
];

// Explicit shared contract first used by state-06-server-overview-data.
const _stateExpectations015 = <String>[
  'Render known values/source/observedAt/receivedAt from DTO. Also exercise missing/quality=unknown observation separately: no zero, no fabricated source/time, no unknown-write claim.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-06-server-overview-validation.
const _stateExpectations016 = <String>[
  'Show exact existing safe error/context reason; no automatic trust acceptance/connect/reset.',
  'A stale/mismatched host-key or executor consent cannot be reused; cancel closes without confirmation.',
];

// Explicit shared contract first used by state-06-server-overview-validation.
const _stateActions010 = <DesignStateAction>[
  DesignStateAction('render-validation', 'automaticRetryCallbacks', 0),
];

// Explicit shared contract first used by state-06-server-overview-denied.
const _stateExpectations017 = <String>[
  'Preserve available source/time and denied label/symbol; absent values/records are not zero/successful empty.',
  'Show only existing owner refresh/connect guidance; no fake permission or capability handler.',
];

// Explicit shared contract first used by state-06-server-overview-denied.
const _stateActions011 = <DesignStateAction>[
  DesignStateAction(
    'render-quality-or-owner-error',
    'automaticRetryCallbacks',
    0,
  ),
];

// Explicit shared contract first used by state-06-server-overview-unsupported.
const _stateExpectations018 = <String>[
  'Preserve available source/time and unsupported label/symbol; absent values/records are not zero/successful empty.',
  'Show only existing owner refresh/connect guidance; no fake permission or capability handler.',
];

// Explicit shared contract first used by state-06-server-overview-stale.
const _stateExpectations019 = <String>[
  'Label stale explicitly with symbol, source/time retained; never render current/success solely from old known quality.',
  'For metrics preserve series symbols and stale dash patterns. For logs stale empty records is not successful empty. No new UI freshness timer.',
];

// Explicit shared contract first used by state-06-server-overview-stale.
const _stateActions012 = <DesignStateAction>[
  DesignStateAction('render-stale', 'automaticRefreshCallbacks', 0),
];

// Explicit shared contract first used by state-06-server-overview-dropped.
const _stateExpectations020 = <String>[
  'Explain dropped/cache-evicted history without a fabricated count; preserve existing source/time/quality.',
  'The 120-sample cap alone is not dropped data; no invented zero/gap-to-now/interpolated curve.',
];

// Explicit shared contract first used by state-06-server-overview-dropped.
const _stateActions013 = <DesignStateAction>[
  DesignStateAction('render-dropped-data', 'automaticRecoveryCallbacks', 0),
];

// Explicit shared contract first used by state-06-server-overview-incomplete.
const _stateExpectations021 = <String>[
  'Explicit partial/gap/parse-error reason survives known quality; keep real counts, source/time and received values.',
  'Missing/partial records or metrics are never zero or successful empty. No fabricated completeness when DTO omits fields.',
];

// Explicit shared contract first used by state-06-server-overview-incomplete.
const _stateActions014 = <DesignStateAction>[
  DesignStateAction('render-incomplete-data', 'automaticRecoveryCallbacks', 0),
];

// Explicit shared contract first used by state-06-server-overview-localUnavailable.
const _stateSources005 = <DesignStateSource>[
  DesignStateSource(
    'lib/servers/server_sections.dart',
    'class ServerOverviewSection',
  ),
  DesignStateSource(
    'lib/servers/server_controller.dart',
    'class ServerController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-06-server-overview-sshUnavailable.
const _stateExpectations022 = <String>[
  'Say connection is not established, never server stopped/locald failure. Local profiles/catalog metadata remain accessible.',
  'Offer only the existing connect/trust diagnosis under owner conditions; host-key change never auto-accepts.',
];

// Explicit shared contract first used by state-06-server-overview-sshUnavailable.
const _stateActions015 = <DesignStateAction>[
  DesignStateAction('render-ssh-offline', 'automaticConnectCallbacks', 0),
];

// Explicit shared contract first used by state-06-server-overview-unknown.
const _stateExpectations023 = <String>[
  'An uncertain write reply is not an observation quality or confirmed acceptance. No automatic re-confirm/connect.',
  'ServerController has no automation retryPending queue; only existing explicit status/reread/trust-review conditions are offered. Native transport/recovery authority is not proven by a section fixture.',
];

// Explicit shared contract first used by state-06-server-overview-unknown.
const _stateActions016 = <DesignStateAction>[
  DesignStateAction(
    'render-uncertain-server-write',
    'automaticConfirmConnectCallbacks',
    0,
  ),
];

// Explicit shared contract first used by state-07-profile-create-loading.
const _stateSources006 = <DesignStateSource>[
  DesignStateSource('lib/profiles/profile_form.dart', 'class ProfileForm'),
  DesignStateSource(
    'lib/profiles/mutation_controller.dart',
    'class MutationController',
  ),
  DesignStateSource(
    'lib/profiles/mutation_status.dart',
    'class MutationStatus',
  ),
];

// Explicit shared contract first used by state-07-profile-create-loading.
const _stateExpectations024 = <String>[
  'Exact submitting/check/readback/reread phase is visible; no duplicate same action while pending.',
  'Draft and current target are retained during ordinary theme/resize, not across private retirement.',
];

// Explicit shared contract first used by state-07-profile-create-loading.
const _stateActions017 = <DesignStateAction>[
  DesignStateAction(
    'activate-duplicate-pending-action',
    'sameActionCallbacks',
    0,
  ),
];

// Explicit shared contract first used by state-07-profile-create-data.
const _stateExpectations025 = <String>[
  'Display current draft/target or committed/current-readback-confirmed result with correct lifecycle, never success before readback.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-07-profile-create-validation.
const _stateExpectations026 = <String>[
  'Existing field validation retains draft and masking and sends no mutation; forms without editable validated fields instead exercise the definitive owner VALIDATION response to one explicit submit.',
  'CAS conflict is validation/conflict, not observation stale. Only edit/delete/settings owners with an expected revision exercise explicit conflict reread and its precise pending state; profile creation has no expected revision.',
  'Already-open form read error must show typed reason rather than only disable save.',
];

// Explicit shared contract first used by state-07-profile-create-validation.
const _stateActions018 = <DesignStateAction>[
  DesignStateAction(
    'render-validation-without-new-intent',
    'additionalMutationRequests',
    0,
  ),
];

// Explicit shared contract first used by state-07-profile-create-denied.
const _stateExpectations027 = <String>[
  'Show definitive FORBIDDEN mutation rejection with permitted correction/read guidance and preserved RAM draft; this is not an unknown outcome. UNAUTHORIZED is not a no-effect mutation result: preserve the owner unknown decision and retire private UI through the authorization gate.',
  'Do not resubmit automatically or bypass credentials/protection; missing/disabled callback is not an active fake handler.',
];

// Explicit shared contract first used by state-07-profile-create-denied.
const _stateActions019 = <DesignStateAction>[
  DesignStateAction('render-definite-rejection', 'automaticMutationRetries', 0),
];

// Explicit shared contract first used by state-07-profile-create-unsupported.
const _stateExpectations028 = <String>[
  'Show definitive UNSUPPORTED rejection with permitted correction/read guidance and preserved RAM draft; this is not an unknown outcome.',
  'Do not resubmit automatically or bypass credentials/protection; missing/disabled callback is not an active fake handler.',
];

// Explicit shared contract first used by state-07-profile-create-localUnavailable.
const _stateSources007 = <DesignStateSource>[
  DesignStateSource('lib/profiles/profile_form.dart', 'class ProfileForm'),
  DesignStateSource(
    'lib/profiles/mutation_controller.dart',
    'class MutationController',
  ),
  DesignStateSource(
    'lib/profiles/mutation_status.dart',
    'class MutationStatus',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-07-profile-create-unknown.
const _stateExpectations029 = <String>[
  'Check-result is observational; absence of receipt is not proof of loss. Retry only after actual owner retryAllowed and keeps exact object/request identity/input.',
  'Busy check/retry has no duplicate; committed waits for current snapshot before confirmed success; no generic automatic retry.',
];

// Explicit shared contract first used by state-07-profile-create-unknown.
const _stateActions020 = <DesignStateAction>[
  DesignStateAction('activate-check-result-once', 'checkResultCallbacks', 1),
  DesignStateAction(
    'activate-disabled-pending-check',
    'additionalCheckCallbacks',
    0,
  ),
  DesignStateAction(
    'explicit-retryAllowed-retry',
    'sameIntentRetryCallbacks',
    1,
  ),
];

// Explicit shared contract first used by state-09-profile-delete-loading.
const _stateSources008 = <DesignStateSource>[
  DesignStateSource('lib/profiles/profile_delete.dart', 'class ProfileDelete'),
  DesignStateSource(
    'lib/profiles/mutation_controller.dart',
    'class MutationController',
  ),
  DesignStateSource(
    'lib/profiles/mutation_status.dart',
    'class MutationStatus',
  ),
];

// Explicit shared contract first used by state-09-profile-delete-localUnavailable.
const _stateSources009 = <DesignStateSource>[
  DesignStateSource('lib/profiles/profile_delete.dart', 'class ProfileDelete'),
  DesignStateSource(
    'lib/profiles/mutation_controller.dart',
    'class MutationController',
  ),
  DesignStateSource(
    'lib/profiles/mutation_status.dart',
    'class MutationStatus',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-10-host-trust-loading.
const _stateSources010 = <DesignStateSource>[
  DesignStateSource(
    'lib/servers/server_sections.dart',
    'class ServerTrustConfirmation',
  ),
  DesignStateSource('lib/servers/server_panel.dart', 'class ServerPanel'),
  DesignStateSource(
    'lib/servers/server_controller.dart',
    'class ServerController',
  ),
];

// Explicit shared contract first used by state-10-host-trust-data.
const _stateExpectations030 = <String>[
  'Bind captured name/address:port including IPv6 and exact fingerprint to matching challenge/profile/revisions. An initially mismatched pair is hidden; later context change retains the frozen review with an explicit invalidation warning and permanently blocks old consent. Private authorization retirement instead removes all private content under P10.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-10-host-trust-validation.
const _stateActions021 = <DesignStateAction>[
  DesignStateAction('confirm-invalid-context', 'confirmCallbacks', 0),
];

// Explicit shared contract first used by state-10-host-trust-denied.
const _stateSources011 = <DesignStateSource>[
  DesignStateSource(
    'lib/servers/server_sections.dart',
    'class ServerTrustConfirmation',
  ),
  DesignStateSource('lib/servers/server_panel.dart', 'class ServerPanel'),
  DesignStateSource(
    'lib/servers/server_controller.dart',
    'class ServerController',
  ),
  DesignStateSource(
    'packages/serverdeck_protocol/lib/host_trust.dart',
    'class TrustedLocalError',
  ),
];

// Explicit shared contract first used by state-10-host-trust-denied.
const _stateExpectations031 = <String>[
  'Actual Panel/Status composition presents precise FORBIDDEN/UNAUTHORIZED and safe existing next step; read failure is not a loaded empty list.',
  'For approvals/delegations an inner failure permits only PLAN_STALE/PLAN_EXPIRED; UNSUPPORTED is legal in the outer typed envelope. Do not invent owner state=failed.',
  'Bare JSON/decision dialogs own no fictitious error props: validate errors inside real editor, post-close save/decision errors in owner status.',
];

// Explicit shared contract first used by state-10-host-trust-denied.
const _stateActions022 = <DesignStateAction>[
  DesignStateAction(
    'render-definite-owner-error',
    'automaticRetryCallbacks',
    0,
  ),
];

// Explicit shared contract first used by state-10-host-trust-unsupported.
const _stateExpectations032 = <String>[
  'Actual Panel/Status composition presents precise UNSUPPORTED and safe existing next step; read failure is not a loaded empty list.',
  'For approvals/delegations an inner failure permits only PLAN_STALE/PLAN_EXPIRED; UNSUPPORTED is legal in the outer typed envelope. Do not invent owner state=failed.',
  'Bare JSON/decision dialogs own no fictitious error props: validate errors inside real editor, post-close save/decision errors in owner status.',
];

// Explicit shared contract first used by state-10-host-trust-localUnavailable.
const _stateSources012 = <DesignStateSource>[
  DesignStateSource(
    'lib/servers/server_sections.dart',
    'class ServerTrustConfirmation',
  ),
  DesignStateSource('lib/servers/server_panel.dart', 'class ServerPanel'),
  DesignStateSource(
    'lib/servers/server_controller.dart',
    'class ServerController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-12-credential-input-loading.
const _stateSources013 = <DesignStateSource>[
  DesignStateSource(
    'lib/profiles/credential_input.dart',
    'class CredentialInput',
  ),
  DesignStateSource(
    'lib/profiles/mutation_controller.dart',
    'class MutationController',
  ),
  DesignStateSource(
    'lib/profiles/mutation_status.dart',
    'class MutationStatus',
  ),
];

// Explicit shared contract first used by state-12-credential-input-loading.
const _stateExpectations033 = <String>[
  'Exact pending phase remains visible; submit/check/reload duplicate is unavailable and RAM draft is preserved.',
  'Credential picker pending is distinct from durable mutation pending; late/disposed picker cannot restore secret.',
];

// Explicit shared contract first used by state-12-credential-input-data.
const _stateExpectations034 = <String>[
  'Exercise actual password/private-key/passphrase/keep/replace modes with masking, labels, validation and current picker lifecycle; never read existing secret for display.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-12-credential-input-localUnavailable.
const _stateSources014 = <DesignStateSource>[
  DesignStateSource(
    'lib/profiles/credential_input.dart',
    'class CredentialInput',
  ),
  DesignStateSource(
    'lib/profiles/mutation_controller.dart',
    'class MutationController',
  ),
  DesignStateSource(
    'lib/profiles/mutation_status.dart',
    'class MutationStatus',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-13-mutation-conflict-loading.
const _stateSources015 = <DesignStateSource>[
  DesignStateSource(
    'lib/profiles/mutation_status.dart',
    'class MutationStatus',
  ),
  DesignStateSource(
    'lib/profiles/mutation_controller.dart',
    'class MutationController',
  ),
];

// Explicit shared contract first used by state-13-mutation-conflict-localUnavailable.
const _stateSources016 = <DesignStateSource>[
  DesignStateSource(
    'lib/profiles/mutation_status.dart',
    'class MutationStatus',
  ),
  DesignStateSource(
    'lib/profiles/mutation_controller.dart',
    'class MutationController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-16-install-catalog-loading.
const _stateSources017 = <DesignStateSource>[
  DesignStateSource('lib/software/software_panel.dart', 'class SoftwarePanel'),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
];

// Explicit shared contract first used by state-16-install-catalog-successfulEmpty.
const _stateExpectations035 = <String>[
  'Actual SoftwarePanel loaded with profiles=[] has no target profiles. Do not manufacture an installEnabled=true/recipes=[] catalog, which the codec forbids.',
  'No automatic read/mutation/connect is triggered by displaying emptiness.',
];

// Explicit shared contract first used by state-16-install-catalog-data.
const _stateExpectations036 = <String>[
  'Render actual supported catalog target/environment/recipe versions and constraints, no unrelated general inventory.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-16-install-catalog-denied.
const _stateSources018 = <DesignStateSource>[
  DesignStateSource('lib/software/software_panel.dart', 'class SoftwarePanel'),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource(
    'packages/serverdeck_protocol/lib/host_trust.dart',
    'class TrustedLocalError',
  ),
];

// Explicit shared contract first used by state-16-install-catalog-localUnavailable.
const _stateSources019 = <DesignStateSource>[
  DesignStateSource('lib/software/software_panel.dart', 'class SoftwarePanel'),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-16-install-catalog-unknown.
const _stateExpectations037 = <String>[
  'Display unconfirmed write separately from definitive FORBIDDEN/UNSUPPORTED; pendingLabel alone is insufficient to classify unknown.',
  'Only existing retryPending uses retained exact request IDs/input; dismiss clears UI interest, not physical job/effect. No generic automatic retry.',
  'UNKNOWN_OUTCOME is a business/job safeCode, never an outer TrustedLocalError; terminal native timeout closes client, requiring real authorized recovery.',
];

// Explicit shared contract first used by state-16-install-catalog-unknown.
const _stateActions023 = <DesignStateAction>[
  DesignStateAction('explicit-allowed-retryPending', 'onRetryPending', 1),
  DesignStateAction('render-unknown', 'automaticRetryCallbacks', 0),
  DesignStateAction('dismiss-pending-ui', 'physicalJobCancelCallbacks', 0),
];

// Explicit shared contract first used by state-17-recipe-detail-loading.
const _stateSources020 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationRecipesSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
];

// Explicit shared contract first used by state-17-recipe-detail-data.
const _stateExpectations038 = <String>[
  'Show exact recipe version, digest, environment, license and install constraints; selection does not execute installation.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-17-recipe-detail-denied.
const _stateSources021 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationRecipesSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource(
    'packages/serverdeck_protocol/lib/host_trust.dart',
    'class TrustedLocalError',
  ),
];

// Explicit shared contract first used by state-17-recipe-detail-localUnavailable.
const _stateSources022 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationRecipesSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-18-install-preflight-loading.
const _stateSources023 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationPlanSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
];

// Explicit shared contract first used by state-18-install-preflight-data.
const _stateExpectations039 = <String>[
  'Show exact target, params, effects, checks, deadline and matching automation profile/version/digest before consent.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-18-install-preflight-validation.
const _stateExpectations040 = <String>[
  'Retain editor draft with local parse/constraint reason; invalid editor submit produces no durable callback.',
  'Service validation/revision conflict is shown in the actual owner status after modal closes, not invented dialog error props.',
];

// Explicit shared contract first used by state-18-install-preflight-validation.
const _stateActions024 = <DesignStateAction>[
  DesignStateAction('submit-invalid-draft', 'durableSubmitCallbacks', 0),
];

// Explicit shared contract first used by state-18-install-preflight-denied.
const _stateSources024 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationPlanSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource(
    'packages/serverdeck_protocol/lib/host_trust.dart',
    'class TrustedLocalError',
  ),
];

// Explicit shared contract first used by state-18-install-preflight-stale.
const _stateExpectations041 = <String>[
  'Old approve/apply is disabled; exact invalidation reason/deadline is visible and old consent cannot return after context reverts.',
  'Only existing explicit reread/new-plan action is allowed; revision conflict remains a different validation case.',
];

// Explicit shared contract first used by state-18-install-preflight-stale.
const _stateActions025 = <DesignStateAction>[
  DesignStateAction('activate-old-apply-or-approve', 'oldConsentCallbacks', 0),
];

// Explicit shared contract first used by state-18-install-preflight-localUnavailable.
const _stateSources025 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationPlanSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-19-plan-approval-loading.
const _stateSources026 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationPlanDecisionDialog',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
];

// Explicit shared contract first used by state-19-plan-approval-data.
const _stateExpectations042 = <String>[
  'Plan decision shows exact readable target/effects/deadline and current context; cancel/close grants no approval/apply.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-19-plan-approval-denied.
const _stateSources027 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationPlanDecisionDialog',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource(
    'packages/serverdeck_protocol/lib/host_trust.dart',
    'class TrustedLocalError',
  ),
];

// Explicit shared contract first used by state-19-plan-approval-localUnavailable.
const _stateSources028 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationPlanDecisionDialog',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-22-server-logs-loading.
const _stateSources029 = <DesignStateSource>[
  DesignStateSource(
    'lib/servers/server_sections.dart',
    'class ServerLogsSection',
  ),
  DesignStateSource(
    'lib/servers/server_controller.dart',
    'class ServerController',
  ),
];

// Explicit shared contract first used by state-22-server-logs-successfulEmpty.
const _stateExpectations043 = <String>[
  'Successfully received quality=known with records=[] states no records for the selected filter; null/denied/incomplete is not successful empty.',
  'No automatic read/mutation/connect is triggered by displaying emptiness.',
];

// Explicit shared contract first used by state-22-server-logs-data.
const _stateExpectations044 = <String>[
  'Render received log records/source/UTC and long Unicode text with actual detail action; selection opens exact record, not a new read.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-22-server-logs-dropped.
const _stateExpectations045 = <String>[
  'Show actual dropped count and incompleteness warning, preserve received records/filter/source/time; no full-success claim.',
  'A bounded page/cursor alone is not dropped records.',
];

// Explicit shared contract first used by state-22-server-logs-localUnavailable.
const _stateSources030 = <DesignStateSource>[
  DesignStateSource(
    'lib/servers/server_sections.dart',
    'class ServerLogsSection',
  ),
  DesignStateSource(
    'lib/servers/server_controller.dart',
    'class ServerController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-23-log-record-data.
const _stateSources031 = <DesignStateSource>[
  DesignStateSource(
    'lib/servers/server_sections.dart',
    'class ServerLogRecordDialog',
  ),
];

// Explicit shared contract first used by state-23-log-record-data.
const _stateExpectations046 = <String>[
  'Show full selected message and UTC selectable text; close exactly once and initiate no record read.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-23-log-record-data.
const _stateActions026 = <DesignStateAction>[
  DesignStateAction('activate-close', 'onClose', 1),
  DesignStateAction('activate-close', 'recordReadRequests', 0),
];

// Explicit shared contract first used by state-23-log-record-localUnavailable.
const _stateSources032 = <DesignStateSource>[
  DesignStateSource(
    'lib/servers/server_sections.dart',
    'class ServerLogRecordDialog',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-27-job-list-loading.
const _stateSources033 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationJobsSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
];

// Explicit shared contract first used by state-27-job-list-successfulEmpty.
const _stateExpectations047 = <String>[
  'jobsLoaded=true with jobs=[] describes no jobs in the obtained local page, not unavailable SSH or running request.',
  'No automatic read/mutation/connect is triggered by displaying emptiness.',
];

// Explicit shared contract first used by state-27-job-list-data.
const _stateExpectations048 = <String>[
  'Render actual obtained job IDs/state and context; local list availability does not assert SSH connected.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-27-job-list-denied.
const _stateSources034 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationJobsSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource(
    'packages/serverdeck_protocol/lib/host_trust.dart',
    'class TrustedLocalError',
  ),
];

// Explicit shared contract first used by state-27-job-list-localUnavailable.
const _stateSources035 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationJobsSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-27-job-list-unknown.
const _stateExpectations049 = <String>[
  'Display unknown outcome, actual effects and observational reconcile availability; never success/empty.',
  'Distinguish safe cancel, cancel-requested and stop waiting. Rendering/navigation/theme/resize does not cancel durable job.',
];

// Explicit shared contract first used by state-27-job-list-unknown.
const _stateActions027 = <DesignStateAction>[
  DesignStateAction('activate-existing-reconcile-once', 'onReconcile', 1),
  DesignStateAction('render-or-stop-waiting', 'onCancelJob', 0),
];

// Explicit shared contract first used by state-28-job-detail-data.
const _stateExpectations050 = <String>[
  'Render actual state, effects, safe cancel/reconcile availability and postchecks. Empty terminal checks means not provided, never passed. cancel-requested is not terminal safe completion.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-28-job-detail-dropped.
const _stateExpectations051 = <String>[
  'Show actual dropped count/gap warning while keeping job state/effects/postchecks and safe next step.',
  'Retaining at most 200 events alone does not indicate dropped events.',
];

// Explicit shared contract first used by state-28-job-detail-incomplete.
const _stateExpectations052 = <String>[
  'Preserve actual uncertain effects/event completeness and show checks not provided when absent; never label missing checks passed.',
  'Bounded 200 events alone is not an incomplete flag; do not synthesize unknown job outcome from a partial page.',
];

// Explicit shared contract first used by state-31-recent-operations-loading.
const _stateSources036 = <DesignStateSource>[
  DesignStateSource(
    'lib/profiles/recovery_view.dart',
    'class RecentOperationsView',
  ),
  DesignStateSource(
    'lib/profiles/startup_recovery.dart',
    'class StartupRecovery',
  ),
];

// Explicit shared contract first used by state-31-recent-operations-loading.
const _stateExpectations053 = <String>[
  'A pending history refresh/floor wait is not an empty receipt list; display exact pending stage.',
  'At most 20 confirmed receipts; floor/current coherent snapshot and late-generation guards remain owned by StartupRecovery.',
];

// Explicit shared contract first used by state-31-recent-operations-loading.
const _stateActions028 = <DesignStateAction>[
  DesignStateAction(
    'activate-busy-history-refresh',
    'additionalHistoryReload',
    0,
  ),
];

// Explicit shared contract first used by state-31-recent-operations-successfulEmpty.
const _stateExpectations054 = <String>[
  'StartupRecovery loaded=true with receipts=[] explicitly means no confirmed records in this bounded sample; absence proves no lost-write outcome.',
  'No automatic read/mutation/connect is triggered by displaying emptiness.',
];

// Explicit shared contract first used by state-31-recent-operations-data.
const _stateExpectations055 = <String>[
  'Display at most 20 confirmed receipts with request identity, operation, UTC and store revision; receipts never replace current readback/job state.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-31-recent-operations-incomplete.
const _stateExpectations056 = <String>[
  'Explicitly say only part of saved receipts is shown; at most 20 and absence proves no unknown-write outcome.',
  'Receipt floor wait is loading, not incomplete; malformed whole response is error.',
];

// Explicit shared contract first used by state-31-recent-operations-localUnavailable.
const _stateSources037 = <DesignStateSource>[
  DesignStateSource(
    'lib/profiles/recovery_view.dart',
    'class RecentOperationsView',
  ),
  DesignStateSource(
    'lib/profiles/startup_recovery.dart',
    'class StartupRecovery',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-32-automation-profiles-loading.
const _stateSources038 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationProfilesSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
];

// Explicit shared contract first used by state-32-automation-profiles-successfulEmpty.
const _stateExpectations057 = <String>[
  'profilesLoaded=true with profiles=[] is the successfully loaded automation-profile list; keep existing create action.',
  'No automatic read/mutation/connect is triggered by displaying emptiness.',
];

// Explicit shared contract first used by state-32-automation-profiles-data.
const _stateExpectations058 = <String>[
  'Render loaded profiles and actual page cursor; selection retains exact profile/revision/digest under owner.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-32-automation-profiles-denied.
const _stateSources039 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationProfilesSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource(
    'packages/serverdeck_protocol/lib/host_trust.dart',
    'class TrustedLocalError',
  ),
];

// Explicit shared contract first used by state-32-automation-profiles-localUnavailable.
const _stateSources040 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationProfilesSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-33-profile-authoring-loading.
const _stateSources041 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationProfileEditorDialog',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
];

// Explicit shared contract first used by state-33-profile-authoring-loading.
const _stateExpectations059 = <String>[
  'Real validate callback pending disables duplicate validation without clearing draft.',
  'Bare editor save does not gain invented busy/error props; show post-close save pending in owner status composition.',
];

// Explicit shared contract first used by state-33-profile-authoring-loading.
const _stateActions029 = <DesignStateAction>[
  DesignStateAction('activate-disabled-validate', 'onValidate', 0),
  DesignStateAction('rebuild-owner-save-pending', 'additionalSaveCallbacks', 0),
];

// Explicit shared contract first used by state-33-profile-authoring-data.
const _stateExpectations060 = <String>[
  'Render actual name/description/body draft, parsed validation and preview without changing payload or committing while editing.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-33-profile-authoring-denied.
const _stateSources042 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationProfileEditorDialog',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource(
    'packages/serverdeck_protocol/lib/host_trust.dart',
    'class TrustedLocalError',
  ),
];

// Explicit shared contract first used by state-33-profile-authoring-localUnavailable.
const _stateSources043 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationProfileEditorDialog',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-34-profile-revisions-loading.
const _stateSources044 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationProfileDetailSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
];

// Explicit shared contract first used by state-34-profile-revisions-successfulEmpty.
const _stateExpectations061 = <String>[
  'A successfully obtained comparison changes=[] states no detected changes; missing comparison and failed comparison are distinct.',
  'No automatic read/mutation/connect is triggered by displaying emptiness.',
];

// Explicit shared contract first used by state-34-profile-revisions-data.
const _stateExpectations062 = <String>[
  'Render actual selected revision, digest, comparison and archive status; numeric revision is not software version and pagination is not loss.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-34-profile-revisions-denied.
const _stateSources045 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationProfileDetailSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource(
    'packages/serverdeck_protocol/lib/host_trust.dart',
    'class TrustedLocalError',
  ),
];

// Explicit shared contract first used by state-34-profile-revisions-incomplete.
const _stateExpectations063 = <String>[
  'Show comparison truncation, not a complete/no-change assertion. A missing/failed comparison is not changes=[].',
  'Existing explicit compare/select/archive actions retain owner gating.',
];

// Explicit shared contract first used by state-34-profile-revisions-localUnavailable.
const _stateSources046 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationProfileDetailSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-35-plan-parameters-loading.
const _stateSources047 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationJsonEditorDialog',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
];

// Explicit shared contract first used by state-35-plan-parameters-data.
const _stateExpectations064 = <String>[
  'Show actual parameter constraints and exact target/profile revision before durable plan creation; draft remains editable until existing submit.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-35-plan-parameters-denied.
const _stateSources048 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationJsonEditorDialog',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource(
    'packages/serverdeck_protocol/lib/host_trust.dart',
    'class TrustedLocalError',
  ),
];

// Explicit shared contract first used by state-35-plan-parameters-localUnavailable.
const _stateSources049 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationJsonEditorDialog',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-36-ai-grants-loading.
const _stateSources050 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationGrantsSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
];

// Explicit shared contract first used by state-36-ai-grants-successfulEmpty.
const _stateExpectations065 = <String>[
  'grantsLoaded=true with grants=[] is no local grants; existing create action remains available under owner gating.',
  'No automatic read/mutation/connect is triggered by displaying emptiness.',
];

// Explicit shared contract first used by state-36-ai-grants-data.
const _stateExpectations066 = <String>[
  'Show actual scopes/server targets/deadline and explicit current/expired/revoked variants. Expired non-revoked may permit explicit replacement; revoked does not regain authority.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-36-ai-grants-denied.
const _stateSources051 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationGrantsSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource(
    'packages/serverdeck_protocol/lib/host_trust.dart',
    'class TrustedLocalError',
  ),
];

// Explicit shared contract first used by state-36-ai-grants-localUnavailable.
const _stateSources052 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationGrantsSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-37-ai-grant-form-data.
const _stateExpectations067 = <String>[
  'Show exact target list, scopes and lifetime in real JSON editor; unresolved target is explicit, never guessed from unrelated selection.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-38-mcp-client-config-data.
const _stateExpectations068 = <String>[
  'Show exact command/args and configuration of the actual grant with Mono machine values, wrapping/selectability/copy and human labels unchanged.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-39-delegations-loading.
const _stateSources053 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationAuthoritiesSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
];

// Explicit shared contract first used by state-39-delegations-successfulEmpty.
const _stateExpectations069 = <String>[
  'AutomationAuthoritiesSection loaded=true with delegations=[] is an empty obtained delegation list, never an empty JSON draft.',
  'No automatic read/mutation/connect is triggered by displaying emptiness.',
];

// Explicit shared contract first used by state-39-delegations-data.
const _stateExpectations070 = <String>[
  'Show actual delegations/predicates/profile revisions/targets/deadlines and expired/revoked variants; editable draft does not confer delegation.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-39-delegations-denied.
const _stateSources054 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationAuthoritiesSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource(
    'packages/serverdeck_protocol/lib/host_trust.dart',
    'class TrustedLocalError',
  ),
];

// Explicit shared contract first used by state-39-delegations-localUnavailable.
const _stateSources055 = <DesignStateSource>[
  DesignStateSource(
    'lib/automation/automation_sections.dart',
    'class AutomationAuthoritiesSection',
  ),
  DesignStateSource(
    'lib/automation/automation_panel.dart',
    'class AutomationPanel',
  ),
  DesignStateSource(
    'lib/automation/automation_controller.dart',
    'class AutomationController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-40-executor-binding-loading.
const _stateSources056 = <DesignStateSource>[
  DesignStateSource(
    'lib/servers/server_sections.dart',
    'class ServerExecutorConfirmation',
  ),
  DesignStateSource('lib/servers/server_panel.dart', 'class ServerPanel'),
  DesignStateSource(
    'lib/servers/server_controller.dart',
    'class ServerController',
  ),
];

// Explicit shared contract first used by state-40-executor-binding-data.
const _stateExpectations071 = <String>[
  'Bind actual inspection fingerprint and readable target to server/profile/connection/credential/trust revisions; changed then restored metadata never restores consent.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-40-executor-binding-denied.
const _stateSources057 = <DesignStateSource>[
  DesignStateSource(
    'lib/servers/server_sections.dart',
    'class ServerExecutorConfirmation',
  ),
  DesignStateSource('lib/servers/server_panel.dart', 'class ServerPanel'),
  DesignStateSource(
    'lib/servers/server_controller.dart',
    'class ServerController',
  ),
  DesignStateSource(
    'packages/serverdeck_protocol/lib/host_trust.dart',
    'class TrustedLocalError',
  ),
];

// Explicit shared contract first used by state-40-executor-binding-localUnavailable.
const _stateSources058 = <DesignStateSource>[
  DesignStateSource(
    'lib/servers/server_sections.dart',
    'class ServerExecutorConfirmation',
  ),
  DesignStateSource('lib/servers/server_panel.dart', 'class ServerPanel'),
  DesignStateSource(
    'lib/servers/server_controller.dart',
    'class ServerController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-84-settings-loading.
const _stateSources059 = <DesignStateSource>[
  DesignStateSource('lib/settings/settings_view.dart', 'class SettingsView'),
  DesignStateSource(
    'lib/profiles/profile_controller.dart',
    'class ProfileController',
  ),
];

// Explicit shared contract first used by state-84-settings-data.
const _stateExpectations072 = <String>[
  'Display required current settings and selected-profile metadata; selected=null is normal data labelled not selected.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-84-settings-localUnavailable.
const _stateSources060 = <DesignStateSource>[
  DesignStateSource('lib/settings/settings_view.dart', 'class SettingsView'),
  DesignStateSource(
    'lib/profiles/profile_controller.dart',
    'class ProfileController',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-85-settings-form-loading.
const _stateSources061 = <DesignStateSource>[
  DesignStateSource('lib/settings/settings_form.dart', 'class SettingsForm'),
  DesignStateSource(
    'lib/profiles/mutation_controller.dart',
    'class MutationController',
  ),
  DesignStateSource(
    'lib/profiles/mutation_status.dart',
    'class MutationStatus',
  ),
];

// Explicit shared contract first used by state-85-settings-form-data.
const _stateExpectations073 = <String>[
  'Display current RAM settings draft and required baseline revision without changing selected profile or saving on theme/resize.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

// Explicit shared contract first used by state-85-settings-form-localUnavailable.
const _stateSources062 = <DesignStateSource>[
  DesignStateSource('lib/settings/settings_form.dart', 'class SettingsForm'),
  DesignStateSource(
    'lib/profiles/mutation_controller.dart',
    'class MutationController',
  ),
  DesignStateSource(
    'lib/profiles/mutation_status.dart',
    'class MutationStatus',
  ),
  DesignStateSource('lib/app.dart', '_retirePrivateSession'),
  DesignStateSource('lib/theme/motion.dart', 'showMotionDialog'),
];

// Explicit shared contract first used by state-94-plan-invalidated-data.
const _stateExpectations074 = <String>[
  'PLAN_STALE/PLAN_EXPIRED/TRUST_CHANGED explain plan invalidation; old apply/approve remains unavailable even after context reverts.',
  'Display/render/theme/resize emits no new UI-initiated owner action.',
];

const designStateCases = <DesignStateCase>[
  DesignStateCase(
    caseId: 'state-01-startup-loading',
    originId: '01-startup',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: pending startup/recovery/shutdown or explicit retry already in progress',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations001,
    actions: _stateActions001,
  ),
  DesignStateCase(
    caseId: 'state-01-startup-validation',
    originId: '01-startup',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: legal typed reason ErrorCode.validation on a non-ready readiness state',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations002,
    actions: _stateActions002,
  ),
  DesignStateCase(
    caseId: 'state-01-startup-denied',
    originId: '01-startup',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: legal typed reason ErrorCode.forbidden and ErrorCode.unauthorized on a non-ready readiness state',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations003,
    actions: _stateActions002,
  ),
  DesignStateCase(
    caseId: 'state-01-startup-unsupported',
    originId: '01-startup',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: legal typed reason ErrorCode.unsupported on a non-ready readiness state',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations004,
    actions: _stateActions002,
  ),
  DesignStateCase(
    caseId: 'state-01-startup-localUnavailable',
    originId: '01-startup',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: actual non-ready unavailable/storageBlocked/incompatible reason with existing retry gate',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations005,
    actions: _stateActions003,
  ),
  DesignStateCase(
    caseId: 'state-02-service-unavailable-loading',
    originId: '02-service-unavailable',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: pending startup/recovery/shutdown or explicit retry already in progress',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations001,
    actions: _stateActions001,
  ),
  DesignStateCase(
    caseId: 'state-02-service-unavailable-validation',
    originId: '02-service-unavailable',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: legal typed reason ErrorCode.validation on a non-ready readiness state',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations002,
    actions: _stateActions002,
  ),
  DesignStateCase(
    caseId: 'state-02-service-unavailable-denied',
    originId: '02-service-unavailable',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: legal typed reason ErrorCode.forbidden and ErrorCode.unauthorized on a non-ready readiness state',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations003,
    actions: _stateActions002,
  ),
  DesignStateCase(
    caseId: 'state-02-service-unavailable-unsupported',
    originId: '02-service-unavailable',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: legal typed reason ErrorCode.unsupported on a non-ready readiness state',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations004,
    actions: _stateActions002,
  ),
  DesignStateCase(
    caseId: 'state-02-service-unavailable-localUnavailable',
    originId: '02-service-unavailable',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: actual non-ready unavailable/storageBlocked/incompatible reason with existing retry gate',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations005,
    actions: _stateActions003,
  ),
  DesignStateCase(
    caseId: 'state-03-storage-blocked-loading',
    originId: '03-storage-blocked',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: pending startup/recovery/shutdown or explicit retry already in progress',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations001,
    actions: _stateActions001,
  ),
  DesignStateCase(
    caseId: 'state-03-storage-blocked-validation',
    originId: '03-storage-blocked',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: legal typed reason ErrorCode.validation on a non-ready readiness state',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations002,
    actions: _stateActions002,
  ),
  DesignStateCase(
    caseId: 'state-03-storage-blocked-denied',
    originId: '03-storage-blocked',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: legal typed reason ErrorCode.forbidden and ErrorCode.unauthorized on a non-ready readiness state',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations003,
    actions: _stateActions002,
  ),
  DesignStateCase(
    caseId: 'state-03-storage-blocked-unsupported',
    originId: '03-storage-blocked',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: legal typed reason ErrorCode.unsupported on a non-ready readiness state',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations004,
    actions: _stateActions002,
  ),
  DesignStateCase(
    caseId: 'state-03-storage-blocked-localUnavailable',
    originId: '03-storage-blocked',
    taskId: 'T034',
    owner: 'ReadinessView',
    phase: 'ReadinessView: actual non-ready unavailable/storageBlocked/incompatible reason with existing retry gate',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.readiness,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources001,
    expectations: _stateExpectations005,
    actions: _stateActions003,
  ),
  DesignStateCase(
    caseId: 'state-04-empty-workspace-loading',
    originId: '04-empty-workspace',
    taskId: 'T034',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController: loaded=false while a coherent current snapshot is pending',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources002,
    expectations: _stateExpectations006,
    actions: _stateActions004,
  ),
  DesignStateCase(
    caseId: 'state-04-empty-workspace-successfulEmpty',
    originId: '04-empty-workspace',
    taskId: 'T034',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController: successfulEmpty at its existing owning phase',
    category: DesignStateCategory.successfulEmpty,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources002,
    expectations: _stateExpectations007,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-04-empty-workspace-data',
    originId: '04-empty-workspace',
    taskId: 'T034',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources002,
    expectations: _stateExpectations008,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-04-empty-workspace-validation',
    originId: '04-empty-workspace',
    taskId: 'T034',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController: ErrorCode.validation from actual local read/reload, not invalid synthetic records',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources002,
    expectations: _stateExpectations009,
    actions: _stateActions006,
  ),
  DesignStateCase(
    caseId: 'state-04-empty-workspace-denied',
    originId: '04-empty-workspace',
    taskId: 'T034',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController: typed local read FORBIDDEN/UNAUTHORIZED; current private unauthorized retirement is also covered separately',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources002,
    expectations: _stateExpectations010,
    actions: _stateActions007,
  ),
  DesignStateCase(
    caseId: 'state-04-empty-workspace-unsupported',
    originId: '04-empty-workspace',
    taskId: 'T034',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController: typed local read UNSUPPORTED; current private unauthorized retirement is also covered separately',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources002,
    expectations: _stateExpectations011,
    actions: _stateActions007,
  ),
  DesignStateCase(
    caseId: 'state-04-empty-workspace-localUnavailable',
    originId: '04-empty-workspace',
    taskId: 'T037',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources003,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-05-server-list-loading',
    originId: '05-server-list',
    taskId: 'T034',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController: loaded=false while a coherent current snapshot is pending',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources002,
    expectations: _stateExpectations006,
    actions: _stateActions004,
  ),
  DesignStateCase(
    caseId: 'state-05-server-list-successfulEmpty',
    originId: '05-server-list',
    taskId: 'T034',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController: successfulEmpty at its existing owning phase',
    category: DesignStateCategory.successfulEmpty,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources002,
    expectations: _stateExpectations007,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-05-server-list-data',
    originId: '05-server-list',
    taskId: 'T034',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources002,
    expectations: _stateExpectations008,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-05-server-list-validation',
    originId: '05-server-list',
    taskId: 'T034',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController: ErrorCode.validation from actual local read/reload, not invalid synthetic records',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources002,
    expectations: _stateExpectations009,
    actions: _stateActions006,
  ),
  DesignStateCase(
    caseId: 'state-05-server-list-denied',
    originId: '05-server-list',
    taskId: 'T034',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController: typed local read FORBIDDEN/UNAUTHORIZED; current private unauthorized retirement is also covered separately',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources002,
    expectations: _stateExpectations010,
    actions: _stateActions007,
  ),
  DesignStateCase(
    caseId: 'state-05-server-list-unsupported',
    originId: '05-server-list',
    taskId: 'T034',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController: typed local read UNSUPPORTED; current private unauthorized retirement is also covered separately',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources002,
    expectations: _stateExpectations011,
    actions: _stateActions007,
  ),
  DesignStateCase(
    caseId: 'state-05-server-list-localUnavailable',
    originId: '05-server-list',
    taskId: 'T037',
    owner: 'ProfileList / ProfileController',
    phase: 'ProfileList / ProfileController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources003,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-06-server-overview-loading',
    originId: '06-server-overview',
    taskId: 'T035',
    owner: 'ServerOverviewSection / ServerController',
    phase: 'ServerOverviewSection / ServerController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources004,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-06-server-overview-successfulEmpty',
    originId: '06-server-overview',
    taskId: 'T035',
    owner: 'ServerOverviewSection / ServerController',
    phase: 'ServerOverviewSection / ServerController: successfulEmpty at its existing owning phase',
    category: DesignStateCategory.successfulEmpty,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources004,
    expectations: _stateExpectations014,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-06-server-overview-data',
    originId: '06-server-overview',
    taskId: 'T035',
    owner: 'ServerOverviewSection / ServerController',
    phase: 'ServerOverviewSection / ServerController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources004,
    expectations: _stateExpectations015,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-06-server-overview-validation',
    originId: '06-server-overview',
    taskId: 'T035',
    owner: 'ServerOverviewSection / ServerController',
    phase: 'ServerOverviewSection / ServerController: existing ServerController/ServerConnectionSection VALIDATION or trust/inspection context mismatch',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources004,
    expectations: _stateExpectations016,
    actions: _stateActions010,
  ),
  DesignStateCase(
    caseId: 'state-06-server-overview-denied',
    originId: '06-server-overview',
    taskId: 'T035',
    owner: 'ServerOverviewSection / ServerController',
    phase: 'ServerOverviewSection / ServerController: DTO quality=denied or existing typed owner error; keep these scopes distinct',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources004,
    expectations: _stateExpectations017,
    actions: _stateActions011,
  ),
  DesignStateCase(
    caseId: 'state-06-server-overview-unsupported',
    originId: '06-server-overview',
    taskId: 'T035',
    owner: 'ServerOverviewSection / ServerController',
    phase: 'ServerOverviewSection / ServerController: DTO quality=unsupported or existing typed owner error; keep these scopes distinct',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources004,
    expectations: _stateExpectations018,
    actions: _stateActions011,
  ),
  DesignStateCase(
    caseId: 'state-06-server-overview-stale',
    originId: '06-server-overview',
    taskId: 'T035',
    owner: 'ServerOverviewSection / ServerController',
    phase: 'ServerOverviewSection / ServerController: inherited stale=true takes priority over old quality=known',
    category: DesignStateCategory.stale,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources004,
    expectations: _stateExpectations019,
    actions: _stateActions012,
  ),
  DesignStateCase(
    caseId: 'state-06-server-overview-dropped',
    originId: '06-server-overview',
    taskId: 'T035',
    owner: 'ServerOverviewSection / ServerController',
    phase: 'ServerOverviewSection/ServerSystemSection: cacheDropped=true and actual gap markers from remote-read DTO',
    category: DesignStateCategory.dropped,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources004,
    expectations: _stateExpectations020,
    actions: _stateActions013,
  ),
  DesignStateCase(
    caseId: 'state-06-server-overview-incomplete',
    originId: '06-server-overview',
    taskId: 'T035',
    owner: 'ServerOverviewSection / ServerController',
    phase: 'ServerOverviewSection / ServerController: DTO incomplete/truncated/parseErrors flags, including old quality=known with explicit partial marker',
    category: DesignStateCategory.incomplete,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources004,
    expectations: _stateExpectations021,
    actions: _stateActions014,
  ),
  DesignStateCase(
    caseId: 'state-06-server-overview-localUnavailable',
    originId: '06-server-overview',
    taskId: 'T037',
    owner: 'ServerOverviewSection / ServerController',
    phase: 'ServerOverviewSection / ServerController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources005,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-06-server-overview-sshUnavailable',
    originId: '06-server-overview',
    taskId: 'T035',
    owner: 'ServerOverviewSection / ServerController',
    phase: 'ServerOverviewSection / ServerController: locald ready with actual selected-server connection absent/offline; use real owner status before/after modal',
    category: DesignStateCategory.sshUnavailable,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources004,
    expectations: _stateExpectations022,
    actions: _stateActions015,
  ),
  DesignStateCase(
    caseId: 'state-06-server-overview-unknown',
    originId: '06-server-overview',
    taskId: 'T035',
    owner: 'ServerOverviewSection / ServerController',
    phase: 'ServerOverviewSection / ServerController: uncertain existing connect/trust/executor write after TIMEOUT/SERVICE_UNAVAILABLE; real owner status outside closed consent',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources004,
    expectations: _stateExpectations023,
    actions: _stateActions016,
  ),
  DesignStateCase(
    caseId: 'state-07-profile-create-loading',
    originId: '07-profile-create',
    taskId: 'T034',
    owner: 'ProfileForm / MutationController',
    phase: 'ProfileForm / MutationController: submitting, result-check/readback, or explicit conflict reread is pending',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources006,
    expectations: _stateExpectations024,
    actions: _stateActions017,
  ),
  DesignStateCase(
    caseId: 'state-07-profile-create-data',
    originId: '07-profile-create',
    taskId: 'T034',
    owner: 'ProfileForm / MutationController',
    phase:
        'ProfileForm / MutationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources006,
    expectations: _stateExpectations025,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-07-profile-create-validation',
    originId: '07-profile-create',
    taskId: 'T034',
    owner: 'ProfileForm / MutationController',
    phase: 'ProfileForm / MutationController: local invalid input and explicit service validation/revisionConflict branches',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources006,
    expectations: _stateExpectations026,
    actions: _stateActions018,
  ),
  DesignStateCase(
    caseId: 'state-07-profile-create-denied',
    originId: '07-profile-create',
    taskId: 'T034',
    owner: 'ProfileForm / MutationController',
    phase: 'ProfileForm / MutationController: definitive rejected mutation FORBIDDEN and open-form typed read reason; UNAUTHORIZED follows the owner unknown/private-retirement path',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources006,
    expectations: _stateExpectations027,
    actions: _stateActions019,
  ),
  DesignStateCase(
    caseId: 'state-07-profile-create-unsupported',
    originId: '07-profile-create',
    taskId: 'T034',
    owner: 'ProfileForm / MutationController',
    phase: 'ProfileForm / MutationController: definitive rejected mutation UNSUPPORTED and open-form typed read reason',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources006,
    expectations: _stateExpectations028,
    actions: _stateActions019,
  ),
  DesignStateCase(
    caseId: 'state-07-profile-create-localUnavailable',
    originId: '07-profile-create',
    taskId: 'T037',
    owner: 'ProfileForm / MutationController',
    phase: 'ProfileForm / MutationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources007,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-07-profile-create-unknown',
    originId: '07-profile-create',
    taskId: 'T034',
    owner: 'ProfileForm / MutationController',
    phase: 'ProfileForm / MutationController: actual lost reply -> unknown -> queued/running/not-found -> explicit same-intent retry -> committed/readback -> succeeded',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources006,
    expectations: _stateExpectations029,
    actions: _stateActions020,
  ),
  DesignStateCase(
    caseId: 'state-08-profile-edit-loading',
    originId: '08-profile-edit',
    taskId: 'T034',
    owner: 'ProfileForm / MutationController',
    phase: 'ProfileForm / MutationController: submitting, result-check/readback, or explicit conflict reread is pending',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources006,
    expectations: _stateExpectations024,
    actions: _stateActions017,
  ),
  DesignStateCase(
    caseId: 'state-08-profile-edit-data',
    originId: '08-profile-edit',
    taskId: 'T034',
    owner: 'ProfileForm / MutationController',
    phase:
        'ProfileForm / MutationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources006,
    expectations: _stateExpectations025,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-08-profile-edit-validation',
    originId: '08-profile-edit',
    taskId: 'T034',
    owner: 'ProfileForm / MutationController',
    phase: 'ProfileForm / MutationController: local invalid input and explicit service validation/revisionConflict branches',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources006,
    expectations: _stateExpectations026,
    actions: _stateActions018,
  ),
  DesignStateCase(
    caseId: 'state-08-profile-edit-denied',
    originId: '08-profile-edit',
    taskId: 'T034',
    owner: 'ProfileForm / MutationController',
    phase: 'ProfileForm / MutationController: definitive rejected mutation FORBIDDEN and open-form typed read reason; UNAUTHORIZED follows the owner unknown/private-retirement path',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources006,
    expectations: _stateExpectations027,
    actions: _stateActions019,
  ),
  DesignStateCase(
    caseId: 'state-08-profile-edit-unsupported',
    originId: '08-profile-edit',
    taskId: 'T034',
    owner: 'ProfileForm / MutationController',
    phase: 'ProfileForm / MutationController: definitive rejected mutation UNSUPPORTED and open-form typed read reason',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources006,
    expectations: _stateExpectations028,
    actions: _stateActions019,
  ),
  DesignStateCase(
    caseId: 'state-08-profile-edit-localUnavailable',
    originId: '08-profile-edit',
    taskId: 'T037',
    owner: 'ProfileForm / MutationController',
    phase: 'ProfileForm / MutationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources007,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-08-profile-edit-unknown',
    originId: '08-profile-edit',
    taskId: 'T034',
    owner: 'ProfileForm / MutationController',
    phase: 'ProfileForm / MutationController: actual lost reply -> unknown -> queued/running/not-found -> explicit same-intent retry -> committed/readback -> succeeded',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources006,
    expectations: _stateExpectations029,
    actions: _stateActions020,
  ),
  DesignStateCase(
    caseId: 'state-09-profile-delete-loading',
    originId: '09-profile-delete',
    taskId: 'T034',
    owner: 'ProfileDelete / MutationController',
    phase: 'ProfileDelete / MutationController: submitting, result-check/readback, or explicit conflict reread is pending',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources008,
    expectations: _stateExpectations024,
    actions: _stateActions017,
  ),
  DesignStateCase(
    caseId: 'state-09-profile-delete-data',
    originId: '09-profile-delete',
    taskId: 'T034',
    owner: 'ProfileDelete / MutationController',
    phase:
        'ProfileDelete / MutationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources008,
    expectations: _stateExpectations025,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-09-profile-delete-validation',
    originId: '09-profile-delete',
    taskId: 'T034',
    owner: 'ProfileDelete / MutationController',
    phase: 'ProfileDelete / MutationController: local invalid input and explicit service validation/revisionConflict branches',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources008,
    expectations: _stateExpectations026,
    actions: _stateActions018,
  ),
  DesignStateCase(
    caseId: 'state-09-profile-delete-denied',
    originId: '09-profile-delete',
    taskId: 'T034',
    owner: 'ProfileDelete / MutationController',
    phase: 'ProfileDelete / MutationController: definitive rejected mutation FORBIDDEN and open-form typed read reason; UNAUTHORIZED follows the owner unknown/private-retirement path',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources008,
    expectations: _stateExpectations027,
    actions: _stateActions019,
  ),
  DesignStateCase(
    caseId: 'state-09-profile-delete-unsupported',
    originId: '09-profile-delete',
    taskId: 'T034',
    owner: 'ProfileDelete / MutationController',
    phase: 'ProfileDelete / MutationController: definitive rejected mutation UNSUPPORTED and open-form typed read reason',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources008,
    expectations: _stateExpectations028,
    actions: _stateActions019,
  ),
  DesignStateCase(
    caseId: 'state-09-profile-delete-localUnavailable',
    originId: '09-profile-delete',
    taskId: 'T037',
    owner: 'ProfileDelete / MutationController',
    phase: 'ProfileDelete / MutationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources009,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-09-profile-delete-unknown',
    originId: '09-profile-delete',
    taskId: 'T034',
    owner: 'ProfileDelete / MutationController',
    phase: 'ProfileDelete / MutationController: actual lost reply -> unknown -> queued/running/not-found -> explicit same-intent retry -> committed/readback -> succeeded',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources008,
    expectations: _stateExpectations029,
    actions: _stateActions020,
  ),
  DesignStateCase(
    caseId: 'state-10-host-trust-loading',
    originId: '10-host-trust',
    taskId: 'T035',
    owner: 'ServerTrustConfirmation / ServerPanel / ServerController',
    phase: 'ServerTrustConfirmation / ServerPanel / ServerController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources010,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-10-host-trust-data',
    originId: '10-host-trust',
    taskId: 'T035',
    owner: 'ServerTrustConfirmation / ServerPanel / ServerController',
    phase: 'ServerTrustConfirmation / ServerPanel / ServerController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources010,
    expectations: _stateExpectations030,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-10-host-trust-validation',
    originId: '10-host-trust',
    taskId: 'T035',
    owner: 'ServerTrustConfirmation / ServerPanel / ServerController',
    phase: 'ServerTrustConfirmation / ServerPanel / ServerController: existing ServerController/ServerConnectionSection VALIDATION or trust/inspection context mismatch',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources010,
    expectations: _stateExpectations016,
    actions: _stateActions021,
  ),
  DesignStateCase(
    caseId: 'state-10-host-trust-denied',
    originId: '10-host-trust',
    taskId: 'T035',
    owner: 'ServerTrustConfirmation / ServerPanel / ServerController',
    phase: 'ServerTrustConfirmation / ServerPanel / ServerController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources011,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-10-host-trust-unsupported',
    originId: '10-host-trust',
    taskId: 'T035',
    owner: 'ServerTrustConfirmation / ServerPanel / ServerController',
    phase: 'ServerTrustConfirmation / ServerPanel / ServerController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources011,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-10-host-trust-localUnavailable',
    originId: '10-host-trust',
    taskId: 'T037',
    owner: 'ServerTrustConfirmation / ServerPanel / ServerController',
    phase: 'ServerTrustConfirmation / ServerPanel / ServerController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources012,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-10-host-trust-sshUnavailable',
    originId: '10-host-trust',
    taskId: 'T035',
    owner: 'ServerTrustConfirmation / ServerPanel / ServerController',
    phase: 'ServerTrustConfirmation / ServerPanel / ServerController: locald ready with actual selected-server connection absent/offline; use real owner status before/after modal',
    category: DesignStateCategory.sshUnavailable,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources010,
    expectations: _stateExpectations022,
    actions: _stateActions015,
  ),
  DesignStateCase(
    caseId: 'state-10-host-trust-unknown',
    originId: '10-host-trust',
    taskId: 'T035',
    owner: 'ServerTrustConfirmation / ServerPanel / ServerController',
    phase: 'ServerTrustConfirmation / ServerPanel / ServerController: uncertain existing connect/trust/executor write after TIMEOUT/SERVICE_UNAVAILABLE; real owner status outside closed consent',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources010,
    expectations: _stateExpectations023,
    actions: _stateActions016,
  ),
  DesignStateCase(
    caseId: 'state-12-credential-input-loading',
    originId: '12-credential-input',
    taskId: 'T034',
    owner: 'CredentialInput in ProfileForm / MutationController',
    phase: 'CredentialInput in ProfileForm / MutationController: submitting, result-check/readback, or explicit conflict reread is pending',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources013,
    expectations: _stateExpectations033,
    actions: _stateActions017,
  ),
  DesignStateCase(
    caseId: 'state-12-credential-input-data',
    originId: '12-credential-input',
    taskId: 'T034',
    owner: 'CredentialInput in ProfileForm / MutationController',
    phase: 'CredentialInput in ProfileForm / MutationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources013,
    expectations: _stateExpectations034,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-12-credential-input-validation',
    originId: '12-credential-input',
    taskId: 'T034',
    owner: 'CredentialInput in ProfileForm / MutationController',
    phase: 'CredentialInput in ProfileForm / MutationController: local invalid input and explicit service validation/revisionConflict branches',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources013,
    expectations: _stateExpectations026,
    actions: _stateActions018,
  ),
  DesignStateCase(
    caseId: 'state-12-credential-input-denied',
    originId: '12-credential-input',
    taskId: 'T034',
    owner: 'CredentialInput in ProfileForm / MutationController',
    phase: 'CredentialInput in ProfileForm / MutationController: definitive rejected mutation FORBIDDEN and open-form typed read reason; UNAUTHORIZED follows the owner unknown/private-retirement path',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources013,
    expectations: _stateExpectations027,
    actions: _stateActions019,
  ),
  DesignStateCase(
    caseId: 'state-12-credential-input-unsupported',
    originId: '12-credential-input',
    taskId: 'T034',
    owner: 'CredentialInput in ProfileForm / MutationController',
    phase: 'CredentialInput in ProfileForm / MutationController: definitive rejected mutation UNSUPPORTED and open-form typed read reason',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources013,
    expectations: _stateExpectations028,
    actions: _stateActions019,
  ),
  DesignStateCase(
    caseId: 'state-12-credential-input-localUnavailable',
    originId: '12-credential-input',
    taskId: 'T037',
    owner: 'CredentialInput in ProfileForm / MutationController',
    phase: 'CredentialInput in ProfileForm / MutationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources014,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-12-credential-input-unknown',
    originId: '12-credential-input',
    taskId: 'T034',
    owner: 'CredentialInput in ProfileForm / MutationController',
    phase: 'CredentialInput in ProfileForm / MutationController: actual lost reply -> unknown -> queued/running/not-found -> explicit same-intent retry -> committed/readback -> succeeded',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources013,
    expectations: _stateExpectations029,
    actions: _stateActions020,
  ),
  DesignStateCase(
    caseId: 'state-13-mutation-conflict-loading',
    originId: '13-mutation-conflict',
    taskId: 'T034',
    owner: 'MutationStatus / MutationController in owning form',
    phase: 'MutationStatus / MutationController in owning form: submitting, result-check/readback, or explicit conflict reread is pending',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources015,
    expectations: _stateExpectations024,
    actions: _stateActions017,
  ),
  DesignStateCase(
    caseId: 'state-13-mutation-conflict-data',
    originId: '13-mutation-conflict',
    taskId: 'T034',
    owner: 'MutationStatus / MutationController in owning form',
    phase: 'MutationStatus / MutationController in owning form: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources015,
    expectations: _stateExpectations025,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-13-mutation-conflict-validation',
    originId: '13-mutation-conflict',
    taskId: 'T034',
    owner: 'MutationStatus / MutationController in owning form',
    phase: 'MutationStatus / MutationController in owning form: local invalid input and explicit service validation/revisionConflict branches',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources015,
    expectations: _stateExpectations026,
    actions: _stateActions018,
  ),
  DesignStateCase(
    caseId: 'state-13-mutation-conflict-denied',
    originId: '13-mutation-conflict',
    taskId: 'T034',
    owner: 'MutationStatus / MutationController in owning form',
    phase: 'MutationStatus / MutationController in owning form: definitive rejected mutation FORBIDDEN and open-form typed read reason; UNAUTHORIZED follows the owner unknown/private-retirement path',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources015,
    expectations: _stateExpectations027,
    actions: _stateActions019,
  ),
  DesignStateCase(
    caseId: 'state-13-mutation-conflict-unsupported',
    originId: '13-mutation-conflict',
    taskId: 'T034',
    owner: 'MutationStatus / MutationController in owning form',
    phase: 'MutationStatus / MutationController in owning form: definitive rejected mutation UNSUPPORTED and open-form typed read reason',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources015,
    expectations: _stateExpectations028,
    actions: _stateActions019,
  ),
  DesignStateCase(
    caseId: 'state-13-mutation-conflict-localUnavailable',
    originId: '13-mutation-conflict',
    taskId: 'T037',
    owner: 'MutationStatus / MutationController in owning form',
    phase: 'MutationStatus / MutationController in owning form visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources016,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-13-mutation-conflict-unknown',
    originId: '13-mutation-conflict',
    taskId: 'T034',
    owner: 'MutationStatus / MutationController in owning form',
    phase: 'MutationStatus / MutationController in owning form: actual lost reply -> unknown -> queued/running/not-found -> explicit same-intent retry -> committed/readback -> succeeded',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources015,
    expectations: _stateExpectations029,
    actions: _stateActions020,
  ),
  DesignStateCase(
    caseId: 'state-16-install-catalog-loading',
    originId: '16-install-catalog',
    taskId: 'T036',
    owner: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel',
    phase: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources017,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-16-install-catalog-successfulEmpty',
    originId: '16-install-catalog',
    taskId: 'T036',
    owner: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel',
    phase: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel: successfulEmpty at its existing owning phase',
    category: DesignStateCategory.successfulEmpty,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources017,
    expectations: _stateExpectations035,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-16-install-catalog-data',
    originId: '16-install-catalog',
    taskId: 'T036',
    owner: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel',
    phase: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources017,
    expectations: _stateExpectations036,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-16-install-catalog-denied',
    originId: '16-install-catalog',
    taskId: 'T036',
    owner: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel',
    phase: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources018,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-16-install-catalog-unsupported',
    originId: '16-install-catalog',
    taskId: 'T036',
    owner: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel',
    phase: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources018,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-16-install-catalog-localUnavailable',
    originId: '16-install-catalog',
    taskId: 'T037',
    owner: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel',
    phase: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources019,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-16-install-catalog-sshUnavailable',
    originId: '16-install-catalog',
    taskId: 'T036',
    owner: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel',
    phase: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel: locald ready with actual selected-server connection absent/offline; use real owner status before/after modal',
    category: DesignStateCategory.sshUnavailable,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources017,
    expectations: _stateExpectations022,
    actions: _stateActions015,
  ),
  DesignStateCase(
    caseId: 'state-16-install-catalog-unknown',
    originId: '16-install-catalog',
    taskId: 'T036',
    owner: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel',
    phase: 'SoftwarePanel / AutomationRecipesSection / AutomationPanel: actual durable request has uncertain TIMEOUT/SERVICE_UNAVAILABLE reply and retained owner action; after modal closes',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.automationWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources017,
    expectations: _stateExpectations037,
    actions: _stateActions023,
  ),
  DesignStateCase(
    caseId: 'state-17-recipe-detail-loading',
    originId: '17-recipe-detail',
    taskId: 'T036',
    owner: 'AutomationRecipesSection / AutomationPanel',
    phase: 'AutomationRecipesSection / AutomationPanel: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources020,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-17-recipe-detail-data',
    originId: '17-recipe-detail',
    taskId: 'T036',
    owner: 'AutomationRecipesSection / AutomationPanel',
    phase: 'AutomationRecipesSection / AutomationPanel: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources020,
    expectations: _stateExpectations038,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-17-recipe-detail-denied',
    originId: '17-recipe-detail',
    taskId: 'T036',
    owner: 'AutomationRecipesSection / AutomationPanel',
    phase: 'AutomationRecipesSection / AutomationPanel: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources021,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-17-recipe-detail-unsupported',
    originId: '17-recipe-detail',
    taskId: 'T036',
    owner: 'AutomationRecipesSection / AutomationPanel',
    phase: 'AutomationRecipesSection / AutomationPanel: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources021,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-17-recipe-detail-localUnavailable',
    originId: '17-recipe-detail',
    taskId: 'T037',
    owner: 'AutomationRecipesSection / AutomationPanel',
    phase: 'AutomationRecipesSection / AutomationPanel visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources022,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-17-recipe-detail-sshUnavailable',
    originId: '17-recipe-detail',
    taskId: 'T036',
    owner: 'AutomationRecipesSection / AutomationPanel',
    phase: 'AutomationRecipesSection / AutomationPanel: locald ready with actual selected-server connection absent/offline; use real owner status before/after modal',
    category: DesignStateCategory.sshUnavailable,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources020,
    expectations: _stateExpectations022,
    actions: _stateActions015,
  ),
  DesignStateCase(
    caseId: 'state-17-recipe-detail-unknown',
    originId: '17-recipe-detail',
    taskId: 'T036',
    owner: 'AutomationRecipesSection / AutomationPanel',
    phase: 'AutomationRecipesSection / AutomationPanel: actual durable request has uncertain TIMEOUT/SERVICE_UNAVAILABLE reply and retained owner action; after modal closes',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.automationWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources020,
    expectations: _stateExpectations037,
    actions: _stateActions023,
  ),
  DesignStateCase(
    caseId: 'state-18-install-preflight-loading',
    originId: '18-install-preflight',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources023,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-18-install-preflight-data',
    originId: '18-install-preflight',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources023,
    expectations: _stateExpectations039,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-18-install-preflight-validation',
    originId: '18-install-preflight',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationStatusSection in actual createRecipePlan/loadPlan phase receives legal owner VALIDATION, after original request returns.',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources023,
    expectations: <String>[
      'Show exact safe validation reason with warning/error symbol and existing reread/new-plan guidance.',
      'Preserve actual obtained plan/target without fabricating zero/successful empty or an editable input in the preflight section.',
      'Render/theme/resize performs no automatic retry/apply/approve.',
    ],
    actions: <DesignStateAction>[
      DesignStateAction(
        'render-owner-validation',
        'automaticRetryApplyApproveCallbacks',
        0,
      ),
      DesignStateAction('activate-existing-explicit-reread', 'onRefresh', 1),
    ],
  ),
  DesignStateCase(
    caseId: 'state-18-install-preflight-denied',
    originId: '18-install-preflight',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources024,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-18-install-preflight-unsupported',
    originId: '18-install-preflight',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources024,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-18-install-preflight-stale',
    originId: '18-install-preflight',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController: PLAN_STALE/PLAN_EXPIRED/TRUST_CHANGED domain invalidation, not observation age',
    category: DesignStateCategory.stale,
    meaning: DesignStateMeaning.planInvalidation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources023,
    expectations: _stateExpectations041,
    actions: _stateActions025,
  ),
  DesignStateCase(
    caseId: 'state-18-install-preflight-localUnavailable',
    originId: '18-install-preflight',
    taskId: 'T037',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources025,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-18-install-preflight-sshUnavailable',
    originId: '18-install-preflight',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController: locald ready with actual selected-server connection absent/offline; use real owner status before/after modal',
    category: DesignStateCategory.sshUnavailable,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources023,
    expectations: _stateExpectations022,
    actions: _stateActions015,
  ),
  DesignStateCase(
    caseId: 'state-18-install-preflight-unknown',
    originId: '18-install-preflight',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController: actual durable request has uncertain TIMEOUT/SERVICE_UNAVAILABLE reply and retained owner action; after modal closes',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.automationWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources023,
    expectations: _stateExpectations037,
    actions: _stateActions023,
  ),
  DesignStateCase(
    caseId: 'state-19-plan-approval-loading',
    originId: '19-plan-approval',
    taskId: 'T036',
    owner:
        'AutomationPlanDecisionDialog / AutomationPanel / AutomationController',
    phase: 'AutomationPlanDecisionDialog / AutomationPanel / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources026,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-19-plan-approval-data',
    originId: '19-plan-approval',
    taskId: 'T036',
    owner:
        'AutomationPlanDecisionDialog / AutomationPanel / AutomationController',
    phase: 'AutomationPlanDecisionDialog / AutomationPanel / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources026,
    expectations: _stateExpectations042,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-19-plan-approval-denied',
    originId: '19-plan-approval',
    taskId: 'T036',
    owner:
        'AutomationPlanDecisionDialog / AutomationPanel / AutomationController',
    phase: 'AutomationPlanDecisionDialog / AutomationPanel / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources027,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-19-plan-approval-unsupported',
    originId: '19-plan-approval',
    taskId: 'T036',
    owner:
        'AutomationPlanDecisionDialog / AutomationPanel / AutomationController',
    phase: 'AutomationPlanDecisionDialog / AutomationPanel / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources027,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-19-plan-approval-stale',
    originId: '19-plan-approval',
    taskId: 'T036',
    owner:
        'AutomationPlanDecisionDialog / AutomationPanel / AutomationController',
    phase: 'AutomationPlanDecisionDialog / AutomationPanel / AutomationController: PLAN_STALE/PLAN_EXPIRED/TRUST_CHANGED domain invalidation, not observation age',
    category: DesignStateCategory.stale,
    meaning: DesignStateMeaning.planInvalidation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources026,
    expectations: _stateExpectations041,
    actions: _stateActions025,
  ),
  DesignStateCase(
    caseId: 'state-19-plan-approval-localUnavailable',
    originId: '19-plan-approval',
    taskId: 'T037',
    owner:
        'AutomationPlanDecisionDialog / AutomationPanel / AutomationController',
    phase: 'AutomationPlanDecisionDialog / AutomationPanel / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources028,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-19-plan-approval-unknown',
    originId: '19-plan-approval',
    taskId: 'T036',
    owner:
        'AutomationPlanDecisionDialog / AutomationPanel / AutomationController',
    phase: 'AutomationPlanDecisionDialog / AutomationPanel / AutomationController: actual durable request has uncertain TIMEOUT/SERVICE_UNAVAILABLE reply and retained owner action; after modal closes',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.automationWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources026,
    expectations: _stateExpectations037,
    actions: _stateActions023,
  ),
  DesignStateCase(
    caseId: 'state-22-server-logs-loading',
    originId: '22-server-logs',
    taskId: 'T035',
    owner: 'ServerLogsSection / ServerPanel / ServerController',
    phase: 'ServerLogsSection / ServerPanel / ServerController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources029,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-22-server-logs-successfulEmpty',
    originId: '22-server-logs',
    taskId: 'T035',
    owner: 'ServerLogsSection / ServerPanel / ServerController',
    phase: 'ServerLogsSection / ServerPanel / ServerController: successfulEmpty at its existing owning phase',
    category: DesignStateCategory.successfulEmpty,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources029,
    expectations: _stateExpectations043,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-22-server-logs-data',
    originId: '22-server-logs',
    taskId: 'T035',
    owner: 'ServerLogsSection / ServerPanel / ServerController',
    phase: 'ServerLogsSection / ServerPanel / ServerController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources029,
    expectations: _stateExpectations044,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-22-server-logs-validation',
    originId: '22-server-logs',
    taskId: 'T035',
    owner: 'ServerLogsSection / ServerPanel / ServerController',
    phase: 'ServerLogsSection / ServerPanel / ServerController: existing ServerController/ServerConnectionSection VALIDATION or trust/inspection context mismatch',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources029,
    expectations: _stateExpectations016,
    actions: _stateActions010,
  ),
  DesignStateCase(
    caseId: 'state-22-server-logs-denied',
    originId: '22-server-logs',
    taskId: 'T035',
    owner: 'ServerLogsSection / ServerPanel / ServerController',
    phase: 'ServerLogsSection / ServerPanel / ServerController: DTO quality=denied or existing typed owner error; keep these scopes distinct',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources029,
    expectations: _stateExpectations017,
    actions: _stateActions011,
  ),
  DesignStateCase(
    caseId: 'state-22-server-logs-unsupported',
    originId: '22-server-logs',
    taskId: 'T035',
    owner: 'ServerLogsSection / ServerPanel / ServerController',
    phase: 'ServerLogsSection / ServerPanel / ServerController: DTO quality=unsupported or existing typed owner error; keep these scopes distinct',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources029,
    expectations: _stateExpectations018,
    actions: _stateActions011,
  ),
  DesignStateCase(
    caseId: 'state-22-server-logs-stale',
    originId: '22-server-logs',
    taskId: 'T035',
    owner: 'ServerLogsSection / ServerPanel / ServerController',
    phase: 'ServerLogsSection / ServerPanel / ServerController: legal logs DTO quality=stale preserves received rows and source/time; logs schema has no inherited stale flag',
    category: DesignStateCategory.stale,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources029,
    expectations: _stateExpectations019,
    actions: _stateActions012,
  ),
  DesignStateCase(
    caseId: 'state-22-server-logs-dropped',
    originId: '22-server-logs',
    taskId: 'T035',
    owner: 'ServerLogsSection / ServerPanel / ServerController',
    phase: 'ServerLogsSection: actual dropped>0/gaps/truncated payload',
    category: DesignStateCategory.dropped,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources029,
    expectations: _stateExpectations045,
    actions: _stateActions013,
  ),
  DesignStateCase(
    caseId: 'state-22-server-logs-incomplete',
    originId: '22-server-logs',
    taskId: 'T035',
    owner: 'ServerLogsSection / ServerPanel / ServerController',
    phase: 'ServerLogsSection / ServerPanel / ServerController: DTO incomplete/truncated/parseErrors flags, including old quality=known with explicit partial marker',
    category: DesignStateCategory.incomplete,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources029,
    expectations: _stateExpectations021,
    actions: _stateActions014,
  ),
  DesignStateCase(
    caseId: 'state-22-server-logs-localUnavailable',
    originId: '22-server-logs',
    taskId: 'T037',
    owner: 'ServerLogsSection / ServerPanel / ServerController',
    phase: 'ServerLogsSection / ServerPanel / ServerController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources030,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-22-server-logs-sshUnavailable',
    originId: '22-server-logs',
    taskId: 'T035',
    owner: 'ServerLogsSection / ServerPanel / ServerController',
    phase: 'ServerLogsSection / ServerPanel / ServerController: locald ready with actual selected-server connection absent/offline; use real owner status before/after modal',
    category: DesignStateCategory.sshUnavailable,
    meaning: DesignStateMeaning.remoteObservation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources029,
    expectations: _stateExpectations022,
    actions: _stateActions015,
  ),
  DesignStateCase(
    caseId: 'state-23-log-record-data',
    originId: '23-log-record',
    taskId: 'T035',
    owner: 'ServerLogRecordDialog, obtained through ServerLogsSection',
    phase: 'ServerLogRecordDialog, obtained through ServerLogsSection: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.localRecord,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources031,
    expectations: _stateExpectations046,
    actions: _stateActions026,
  ),
  DesignStateCase(
    caseId: 'state-23-log-record-localUnavailable',
    originId: '23-log-record',
    taskId: 'T037',
    owner: 'ServerLogRecordDialog, obtained through ServerLogsSection',
    phase: 'ServerLogRecordDialog, obtained through ServerLogsSection visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources032,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-27-job-list-loading',
    originId: '27-job-list',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-27-job-list-successfulEmpty',
    originId: '27-job-list',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: successfulEmpty at its existing owning phase',
    category: DesignStateCategory.successfulEmpty,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations047,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-27-job-list-data',
    originId: '27-job-list',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations048,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-27-job-list-denied',
    originId: '27-job-list',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources034,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-27-job-list-unsupported',
    originId: '27-job-list',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources034,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-27-job-list-localUnavailable',
    originId: '27-job-list',
    taskId: 'T037',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources035,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-27-job-list-unknown',
    originId: '27-job-list',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection: actual AutomationJobRecord unknown with effects=uncertain/safeCode=UNKNOWN_OUTCOME',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.jobOutcome,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations049,
    actions: _stateActions027,
  ),
  DesignStateCase(
    caseId: 'state-28-job-detail-loading',
    originId: '28-job-detail',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-28-job-detail-data',
    originId: '28-job-detail',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations050,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-28-job-detail-denied',
    originId: '28-job-detail',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources034,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-28-job-detail-unsupported',
    originId: '28-job-detail',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources034,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-28-job-detail-dropped',
    originId: '28-job-detail',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection: actual page dropped/droppedEvents or event droppedCount',
    category: DesignStateCategory.dropped,
    meaning: DesignStateMeaning.jobOutcome,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations051,
    actions: _stateActions013,
  ),
  DesignStateCase(
    caseId: 'state-28-job-detail-incomplete',
    originId: '28-job-detail',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection: event gap/incomplete effects or omitted postchecks in actual job payload',
    category: DesignStateCategory.incomplete,
    meaning: DesignStateMeaning.jobOutcome,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations052,
    actions: _stateActions014,
  ),
  DesignStateCase(
    caseId: 'state-28-job-detail-localUnavailable',
    originId: '28-job-detail',
    taskId: 'T037',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources035,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-28-job-detail-unknown',
    originId: '28-job-detail',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection: actual AutomationJobRecord unknown with effects=uncertain/safeCode=UNKNOWN_OUTCOME',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.jobOutcome,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations049,
    actions: _stateActions027,
  ),
  DesignStateCase(
    caseId: 'state-29-job-unknown-loading',
    originId: '29-job-unknown',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-29-job-unknown-data',
    originId: '29-job-unknown',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations050,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-29-job-unknown-denied',
    originId: '29-job-unknown',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources034,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-29-job-unknown-unsupported',
    originId: '29-job-unknown',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources034,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-29-job-unknown-dropped',
    originId: '29-job-unknown',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection: actual page dropped/droppedEvents or event droppedCount',
    category: DesignStateCategory.dropped,
    meaning: DesignStateMeaning.jobOutcome,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations051,
    actions: _stateActions013,
  ),
  DesignStateCase(
    caseId: 'state-29-job-unknown-incomplete',
    originId: '29-job-unknown',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection: event gap/incomplete effects or omitted postchecks in actual job payload',
    category: DesignStateCategory.incomplete,
    meaning: DesignStateMeaning.jobOutcome,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations052,
    actions: _stateActions014,
  ),
  DesignStateCase(
    caseId: 'state-29-job-unknown-localUnavailable',
    originId: '29-job-unknown',
    taskId: 'T037',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources035,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-29-job-unknown-unknown',
    originId: '29-job-unknown',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection: actual AutomationJobRecord unknown with effects=uncertain/safeCode=UNKNOWN_OUTCOME',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.jobOutcome,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations049,
    actions: _stateActions027,
  ),
  DesignStateCase(
    caseId: 'state-30-job-cancel-loading',
    originId: '30-job-cancel',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-30-job-cancel-data',
    originId: '30-job-cancel',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations050,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-30-job-cancel-denied',
    originId: '30-job-cancel',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources034,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-30-job-cancel-unsupported',
    originId: '30-job-cancel',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources034,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-30-job-cancel-dropped',
    originId: '30-job-cancel',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection: actual page dropped/droppedEvents or event droppedCount',
    category: DesignStateCategory.dropped,
    meaning: DesignStateMeaning.jobOutcome,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations051,
    actions: _stateActions013,
  ),
  DesignStateCase(
    caseId: 'state-30-job-cancel-incomplete',
    originId: '30-job-cancel',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection: event gap/incomplete effects or omitted postchecks in actual job payload',
    category: DesignStateCategory.incomplete,
    meaning: DesignStateMeaning.jobOutcome,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations052,
    actions: _stateActions014,
  ),
  DesignStateCase(
    caseId: 'state-30-job-cancel-localUnavailable',
    originId: '30-job-cancel',
    taskId: 'T037',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources035,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-30-job-cancel-unknown',
    originId: '30-job-cancel',
    taskId: 'T036',
    owner: 'AutomationJobsSection / AutomationController',
    phase: 'AutomationJobsSection: actual AutomationJobRecord unknown with effects=uncertain/safeCode=UNKNOWN_OUTCOME',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.jobOutcome,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources033,
    expectations: _stateExpectations049,
    actions: _stateActions027,
  ),
  DesignStateCase(
    caseId: 'state-31-recent-operations-loading',
    originId: '31-recent-operations',
    taskId: 'T034',
    owner: 'RecentOperationsButton / _History / StartupRecovery',
    phase: 'StartupRecovery.reload/receipt-floor wait in actual RecentOperationsButton/_History composition',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.confirmedReceipts,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources036,
    expectations: _stateExpectations053,
    actions: _stateActions028,
  ),
  DesignStateCase(
    caseId: 'state-31-recent-operations-successfulEmpty',
    originId: '31-recent-operations',
    taskId: 'T034',
    owner: 'RecentOperationsButton / _History / StartupRecovery',
    phase: 'RecentOperationsButton / _History / StartupRecovery: successfulEmpty at its existing owning phase',
    category: DesignStateCategory.successfulEmpty,
    meaning: DesignStateMeaning.confirmedReceipts,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources036,
    expectations: _stateExpectations054,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-31-recent-operations-data',
    originId: '31-recent-operations',
    taskId: 'T034',
    owner: 'RecentOperationsButton / _History / StartupRecovery',
    phase: 'RecentOperationsButton / _History / StartupRecovery: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.confirmedReceipts,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources036,
    expectations: _stateExpectations055,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-31-recent-operations-validation',
    originId: '31-recent-operations',
    taskId: 'T034',
    owner: 'RecentOperationsButton / _History / StartupRecovery',
    phase: 'RecentOperationsButton / _History / StartupRecovery: ErrorCode.validation from actual local read/reload, not invalid synthetic records',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.confirmedReceipts,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources036,
    expectations: _stateExpectations009,
    actions: _stateActions006,
  ),
  DesignStateCase(
    caseId: 'state-31-recent-operations-denied',
    originId: '31-recent-operations',
    taskId: 'T034',
    owner: 'RecentOperationsButton / _History / StartupRecovery',
    phase: 'RecentOperationsButton / _History / StartupRecovery: typed local read FORBIDDEN/UNAUTHORIZED; current private unauthorized retirement is also covered separately',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.confirmedReceipts,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources036,
    expectations: _stateExpectations010,
    actions: _stateActions007,
  ),
  DesignStateCase(
    caseId: 'state-31-recent-operations-unsupported',
    originId: '31-recent-operations',
    taskId: 'T034',
    owner: 'RecentOperationsButton / _History / StartupRecovery',
    phase: 'RecentOperationsButton / _History / StartupRecovery: typed local read UNSUPPORTED; current private unauthorized retirement is also covered separately',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.confirmedReceipts,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources036,
    expectations: _stateExpectations011,
    actions: _stateActions007,
  ),
  DesignStateCase(
    caseId: 'state-31-recent-operations-incomplete',
    originId: '31-recent-operations',
    taskId: 'T034',
    owner: 'RecentOperationsButton / _History / StartupRecovery',
    phase: 'Actual _History: StartupRecovery.truncated=true on received confirmed receipt sample',
    category: DesignStateCategory.incomplete,
    meaning: DesignStateMeaning.confirmedReceipts,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources036,
    expectations: _stateExpectations056,
    actions: _stateActions014,
  ),
  DesignStateCase(
    caseId: 'state-31-recent-operations-localUnavailable',
    originId: '31-recent-operations',
    taskId: 'T037',
    owner: 'RecentOperationsButton / _History / StartupRecovery',
    phase: 'RecentOperationsButton / _History / StartupRecovery visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources037,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-32-automation-profiles-loading',
    originId: '32-automation-profiles',
    taskId: 'T036',
    owner: 'AutomationProfilesSection / AutomationController',
    phase: 'AutomationProfilesSection / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources038,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-32-automation-profiles-successfulEmpty',
    originId: '32-automation-profiles',
    taskId: 'T036',
    owner: 'AutomationProfilesSection / AutomationController',
    phase: 'AutomationProfilesSection / AutomationController: successfulEmpty at its existing owning phase',
    category: DesignStateCategory.successfulEmpty,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources038,
    expectations: _stateExpectations057,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-32-automation-profiles-data',
    originId: '32-automation-profiles',
    taskId: 'T036',
    owner: 'AutomationProfilesSection / AutomationController',
    phase: 'AutomationProfilesSection / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources038,
    expectations: _stateExpectations058,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-32-automation-profiles-denied',
    originId: '32-automation-profiles',
    taskId: 'T036',
    owner: 'AutomationProfilesSection / AutomationController',
    phase: 'AutomationProfilesSection / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources039,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-32-automation-profiles-unsupported',
    originId: '32-automation-profiles',
    taskId: 'T036',
    owner: 'AutomationProfilesSection / AutomationController',
    phase: 'AutomationProfilesSection / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources039,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-32-automation-profiles-localUnavailable',
    originId: '32-automation-profiles',
    taskId: 'T037',
    owner: 'AutomationProfilesSection / AutomationController',
    phase: 'AutomationProfilesSection / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources040,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-33-profile-authoring-loading',
    originId: '33-profile-authoring',
    taskId: 'T036',
    owner: 'AutomationProfileEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationProfileEditorDialog validating; durable save is shown by actual owner AutomationStatusSection after dialog closes',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources041,
    expectations: _stateExpectations059,
    actions: _stateActions029,
  ),
  DesignStateCase(
    caseId: 'state-33-profile-authoring-data',
    originId: '33-profile-authoring',
    taskId: 'T036',
    owner: 'AutomationProfileEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationProfileEditorDialog / AutomationPanel / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources041,
    expectations: _stateExpectations060,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-33-profile-authoring-validation',
    originId: '33-profile-authoring',
    taskId: 'T036',
    owner: 'AutomationProfileEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationProfileEditorDialog / AutomationPanel / AutomationController: real editor/parameter constraint or owner validation/CAS conflict, after the actual submit boundary',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources041,
    expectations: _stateExpectations040,
    actions: _stateActions024,
  ),
  DesignStateCase(
    caseId: 'state-33-profile-authoring-denied',
    originId: '33-profile-authoring',
    taskId: 'T036',
    owner: 'AutomationProfileEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationProfileEditorDialog / AutomationPanel / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources042,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-33-profile-authoring-unsupported',
    originId: '33-profile-authoring',
    taskId: 'T036',
    owner: 'AutomationProfileEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationProfileEditorDialog / AutomationPanel / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources042,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-33-profile-authoring-localUnavailable',
    originId: '33-profile-authoring',
    taskId: 'T037',
    owner: 'AutomationProfileEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationProfileEditorDialog / AutomationPanel / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources043,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-33-profile-authoring-unknown',
    originId: '33-profile-authoring',
    taskId: 'T036',
    owner: 'AutomationProfileEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationProfileEditorDialog / AutomationPanel / AutomationController: actual durable request has uncertain TIMEOUT/SERVICE_UNAVAILABLE reply and retained owner action; after modal closes',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.automationWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources041,
    expectations: _stateExpectations037,
    actions: _stateActions023,
  ),
  DesignStateCase(
    caseId: 'state-34-profile-revisions-loading',
    originId: '34-profile-revisions',
    taskId: 'T036',
    owner: 'AutomationProfileDetailSection / AutomationController',
    phase: 'AutomationProfileDetailSection / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources044,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-34-profile-revisions-successfulEmpty',
    originId: '34-profile-revisions',
    taskId: 'T036',
    owner: 'AutomationProfileDetailSection / AutomationController',
    phase: 'AutomationProfileDetailSection / AutomationController: successfulEmpty at its existing owning phase',
    category: DesignStateCategory.successfulEmpty,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources044,
    expectations: _stateExpectations061,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-34-profile-revisions-data',
    originId: '34-profile-revisions',
    taskId: 'T036',
    owner: 'AutomationProfileDetailSection / AutomationController',
    phase: 'AutomationProfileDetailSection / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources044,
    expectations: _stateExpectations062,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-34-profile-revisions-validation',
    originId: '34-profile-revisions',
    taskId: 'T036',
    owner: 'AutomationProfileDetailSection / AutomationController',
    phase: 'AutomationProfileDetailSection / AutomationController: real editor/parameter constraint or owner validation/CAS conflict, after the actual submit boundary',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources044,
    expectations: _stateExpectations040,
    actions: _stateActions024,
  ),
  DesignStateCase(
    caseId: 'state-34-profile-revisions-denied',
    originId: '34-profile-revisions',
    taskId: 'T036',
    owner: 'AutomationProfileDetailSection / AutomationController',
    phase: 'AutomationProfileDetailSection / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources045,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-34-profile-revisions-unsupported',
    originId: '34-profile-revisions',
    taskId: 'T036',
    owner: 'AutomationProfileDetailSection / AutomationController',
    phase: 'AutomationProfileDetailSection / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources045,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-34-profile-revisions-incomplete',
    originId: '34-profile-revisions',
    taskId: 'T036',
    owner: 'AutomationProfileDetailSection / AutomationController',
    phase: 'AutomationProfileDetailSection: actual comparison truncated=true',
    category: DesignStateCategory.incomplete,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources044,
    expectations: _stateExpectations063,
    actions: _stateActions014,
  ),
  DesignStateCase(
    caseId: 'state-34-profile-revisions-localUnavailable',
    originId: '34-profile-revisions',
    taskId: 'T037',
    owner: 'AutomationProfileDetailSection / AutomationController',
    phase: 'AutomationProfileDetailSection / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources046,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-34-profile-revisions-unknown',
    originId: '34-profile-revisions',
    taskId: 'T036',
    owner: 'AutomationProfileDetailSection / AutomationController',
    phase: 'AutomationProfileDetailSection / AutomationController: actual durable request has uncertain TIMEOUT/SERVICE_UNAVAILABLE reply and retained owner action; after modal closes',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.automationWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources044,
    expectations: _stateExpectations037,
    actions: _stateActions023,
  ),
  DesignStateCase(
    caseId: 'state-35-plan-parameters-loading',
    originId: '35-plan-parameters',
    taskId: 'T036',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources047,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-35-plan-parameters-data',
    originId: '35-plan-parameters',
    taskId: 'T036',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources047,
    expectations: _stateExpectations064,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-35-plan-parameters-validation',
    originId: '35-plan-parameters',
    taskId: 'T036',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController: real editor/parameter constraint or owner validation/CAS conflict, after the actual submit boundary',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources047,
    expectations: _stateExpectations040,
    actions: _stateActions024,
  ),
  DesignStateCase(
    caseId: 'state-35-plan-parameters-denied',
    originId: '35-plan-parameters',
    taskId: 'T036',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources048,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-35-plan-parameters-unsupported',
    originId: '35-plan-parameters',
    taskId: 'T036',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources048,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-35-plan-parameters-localUnavailable',
    originId: '35-plan-parameters',
    taskId: 'T037',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources049,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-35-plan-parameters-sshUnavailable',
    originId: '35-plan-parameters',
    taskId: 'T036',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController: locald ready with actual selected-server connection absent/offline; use real owner status before/after modal',
    category: DesignStateCategory.sshUnavailable,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources047,
    expectations: _stateExpectations022,
    actions: _stateActions015,
  ),
  DesignStateCase(
    caseId: 'state-35-plan-parameters-unknown',
    originId: '35-plan-parameters',
    taskId: 'T036',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController: actual durable request has uncertain TIMEOUT/SERVICE_UNAVAILABLE reply and retained owner action; after modal closes',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.automationWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources047,
    expectations: _stateExpectations037,
    actions: _stateActions023,
  ),
  DesignStateCase(
    caseId: 'state-36-ai-grants-loading',
    originId: '36-ai-grants',
    taskId: 'T036',
    owner: 'AutomationGrantsSection / AutomationPanel / AutomationController',
    phase: 'AutomationGrantsSection / AutomationPanel / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources050,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-36-ai-grants-successfulEmpty',
    originId: '36-ai-grants',
    taskId: 'T036',
    owner: 'AutomationGrantsSection / AutomationPanel / AutomationController',
    phase: 'AutomationGrantsSection / AutomationPanel / AutomationController: successfulEmpty at its existing owning phase',
    category: DesignStateCategory.successfulEmpty,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources050,
    expectations: _stateExpectations065,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-36-ai-grants-data',
    originId: '36-ai-grants',
    taskId: 'T036',
    owner: 'AutomationGrantsSection / AutomationPanel / AutomationController',
    phase: 'AutomationGrantsSection / AutomationPanel / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources050,
    expectations: _stateExpectations066,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-36-ai-grants-validation',
    originId: '36-ai-grants',
    taskId: 'T036',
    owner: 'AutomationGrantsSection / AutomationPanel / AutomationController',
    phase: 'Actual grant revoke confirmation closes, owner revokeGrant returns REVISION_CONFLICT or VALIDATION, and AutomationStatusSection presents rejection; the grants section retains service-owned metadata.',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources050,
    expectations: <String>[
      'Explain grant revision conflict/rejection without observation stale/unknown outcome claim.',
      'No automatic new revocation, replacement, permission grant or payload revision update; existing explicit refresh remains available under owner gating.',
      'Closing/back in revoke confirmation does not call onRevoke.',
    ],
    actions: <DesignStateAction>[
      DesignStateAction(
        'render-cas-rejection',
        'automaticRevokeOrReplaceCallbacks',
        0,
      ),
      DesignStateAction('activate-existing-grants-refresh', 'onRefresh', 1),
      DesignStateAction('cancel-revoke-confirmation', 'onRevoke', 0),
    ],
  ),
  DesignStateCase(
    caseId: 'state-36-ai-grants-denied',
    originId: '36-ai-grants',
    taskId: 'T036',
    owner: 'AutomationGrantsSection / AutomationPanel / AutomationController',
    phase: 'AutomationGrantsSection / AutomationPanel / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources051,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-36-ai-grants-unsupported',
    originId: '36-ai-grants',
    taskId: 'T036',
    owner: 'AutomationGrantsSection / AutomationPanel / AutomationController',
    phase: 'AutomationGrantsSection / AutomationPanel / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources051,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-36-ai-grants-localUnavailable',
    originId: '36-ai-grants',
    taskId: 'T037',
    owner: 'AutomationGrantsSection / AutomationPanel / AutomationController',
    phase: 'AutomationGrantsSection / AutomationPanel / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources052,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-36-ai-grants-unknown',
    originId: '36-ai-grants',
    taskId: 'T036',
    owner: 'AutomationGrantsSection / AutomationPanel / AutomationController',
    phase: 'AutomationGrantsSection / AutomationPanel / AutomationController: actual durable request has uncertain TIMEOUT/SERVICE_UNAVAILABLE reply and retained owner action; after modal closes',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.automationWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources050,
    expectations: _stateExpectations037,
    actions: _stateActions023,
  ),
  DesignStateCase(
    caseId: 'state-37-ai-grant-form-loading',
    originId: '37-ai-grant-form',
    taskId: 'T036',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources047,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-37-ai-grant-form-data',
    originId: '37-ai-grant-form',
    taskId: 'T036',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources047,
    expectations: _stateExpectations067,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-37-ai-grant-form-validation',
    originId: '37-ai-grant-form',
    taskId: 'T036',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController: real editor/parameter constraint or owner validation/CAS conflict, after the actual submit boundary',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources047,
    expectations: _stateExpectations040,
    actions: _stateActions024,
  ),
  DesignStateCase(
    caseId: 'state-37-ai-grant-form-denied',
    originId: '37-ai-grant-form',
    taskId: 'T036',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources048,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-37-ai-grant-form-unsupported',
    originId: '37-ai-grant-form',
    taskId: 'T036',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources048,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-37-ai-grant-form-localUnavailable',
    originId: '37-ai-grant-form',
    taskId: 'T037',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources049,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-37-ai-grant-form-unknown',
    originId: '37-ai-grant-form',
    taskId: 'T036',
    owner:
        'AutomationJsonEditorDialog / AutomationPanel / AutomationController',
    phase: 'AutomationJsonEditorDialog / AutomationPanel / AutomationController: actual durable request has uncertain TIMEOUT/SERVICE_UNAVAILABLE reply and retained owner action; after modal closes',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.automationWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources047,
    expectations: _stateExpectations037,
    actions: _stateActions023,
  ),
  DesignStateCase(
    caseId: 'state-38-mcp-client-config-loading',
    originId: '38-mcp-client-config',
    taskId: 'T036',
    owner: 'AutomationGrantsSection configuration / AutomationController',
    phase: 'AutomationGrantsSection configuration / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources050,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-38-mcp-client-config-data',
    originId: '38-mcp-client-config',
    taskId: 'T036',
    owner: 'AutomationGrantsSection configuration / AutomationController',
    phase: 'AutomationGrantsSection configuration / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources050,
    expectations: _stateExpectations068,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-38-mcp-client-config-denied',
    originId: '38-mcp-client-config',
    taskId: 'T036',
    owner: 'AutomationGrantsSection configuration / AutomationController',
    phase: 'AutomationGrantsSection configuration / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources051,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-38-mcp-client-config-unsupported',
    originId: '38-mcp-client-config',
    taskId: 'T036',
    owner: 'AutomationGrantsSection configuration / AutomationController',
    phase: 'AutomationGrantsSection configuration / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources051,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-38-mcp-client-config-localUnavailable',
    originId: '38-mcp-client-config',
    taskId: 'T037',
    owner: 'AutomationGrantsSection configuration / AutomationController',
    phase: 'AutomationGrantsSection configuration / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources052,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-39-delegations-loading',
    originId: '39-delegations',
    taskId: 'T036',
    owner: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController',
    phase: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources053,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-39-delegations-successfulEmpty',
    originId: '39-delegations',
    taskId: 'T036',
    owner: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController',
    phase: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController: successfulEmpty at its existing owning phase',
    category: DesignStateCategory.successfulEmpty,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources053,
    expectations: _stateExpectations069,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-39-delegations-data',
    originId: '39-delegations',
    taskId: 'T036',
    owner: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController',
    phase: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources053,
    expectations: _stateExpectations070,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-39-delegations-validation',
    originId: '39-delegations',
    taskId: 'T036',
    owner: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController',
    phase: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController: real editor/parameter constraint or owner validation/CAS conflict, after the actual submit boundary',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources053,
    expectations: _stateExpectations040,
    actions: _stateActions024,
  ),
  DesignStateCase(
    caseId: 'state-39-delegations-denied',
    originId: '39-delegations',
    taskId: 'T036',
    owner: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController',
    phase: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources054,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-39-delegations-unsupported',
    originId: '39-delegations',
    taskId: 'T036',
    owner: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController',
    phase: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources054,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-39-delegations-localUnavailable',
    originId: '39-delegations',
    taskId: 'T037',
    owner: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController',
    phase: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources055,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-39-delegations-unknown',
    originId: '39-delegations',
    taskId: 'T036',
    owner: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController',
    phase: 'AutomationAuthoritiesSection + AutomationJsonEditorDialog / AutomationController: actual durable request has uncertain TIMEOUT/SERVICE_UNAVAILABLE reply and retained owner action; after modal closes',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.automationWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources053,
    expectations: _stateExpectations037,
    actions: _stateActions023,
  ),
  DesignStateCase(
    caseId: 'state-40-executor-binding-loading',
    originId: '40-executor-binding',
    taskId: 'T035',
    owner: 'ServerExecutorConfirmation / ServerPanel / ServerController',
    phase: 'ServerExecutorConfirmation / ServerPanel / ServerController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources056,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-40-executor-binding-data',
    originId: '40-executor-binding',
    taskId: 'T035',
    owner: 'ServerExecutorConfirmation / ServerPanel / ServerController',
    phase: 'ServerExecutorConfirmation / ServerPanel / ServerController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources056,
    expectations: _stateExpectations071,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-40-executor-binding-validation',
    originId: '40-executor-binding',
    taskId: 'T035',
    owner: 'ServerExecutorConfirmation / ServerPanel / ServerController',
    phase: 'ServerExecutorConfirmation / ServerPanel / ServerController: existing ServerController/ServerConnectionSection VALIDATION or trust/inspection context mismatch',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources056,
    expectations: _stateExpectations016,
    actions: _stateActions021,
  ),
  DesignStateCase(
    caseId: 'state-40-executor-binding-denied',
    originId: '40-executor-binding',
    taskId: 'T035',
    owner: 'ServerExecutorConfirmation / ServerPanel / ServerController',
    phase: 'ServerExecutorConfirmation / ServerPanel / ServerController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources057,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-40-executor-binding-unsupported',
    originId: '40-executor-binding',
    taskId: 'T035',
    owner: 'ServerExecutorConfirmation / ServerPanel / ServerController',
    phase: 'ServerExecutorConfirmation / ServerPanel / ServerController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources057,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-40-executor-binding-localUnavailable',
    originId: '40-executor-binding',
    taskId: 'T037',
    owner: 'ServerExecutorConfirmation / ServerPanel / ServerController',
    phase: 'ServerExecutorConfirmation / ServerPanel / ServerController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources058,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-40-executor-binding-sshUnavailable',
    originId: '40-executor-binding',
    taskId: 'T035',
    owner: 'ServerExecutorConfirmation / ServerPanel / ServerController',
    phase: 'ServerExecutorConfirmation / ServerPanel / ServerController: locald ready with actual selected-server connection absent/offline; use real owner status before/after modal',
    category: DesignStateCategory.sshUnavailable,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources056,
    expectations: _stateExpectations022,
    actions: _stateActions015,
  ),
  DesignStateCase(
    caseId: 'state-40-executor-binding-unknown',
    originId: '40-executor-binding',
    taskId: 'T035',
    owner: 'ServerExecutorConfirmation / ServerPanel / ServerController',
    phase: 'ServerExecutorConfirmation / ServerPanel / ServerController: uncertain existing connect/trust/executor write after TIMEOUT/SERVICE_UNAVAILABLE; real owner status outside closed consent',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.trustWrite,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources056,
    expectations: _stateExpectations023,
    actions: _stateActions016,
  ),
  DesignStateCase(
    caseId: 'state-84-settings-loading',
    originId: '84-settings',
    taskId: 'T034',
    owner: 'SettingsView / ProfileController',
    phase: 'SettingsView / ProfileController: loaded=false while a coherent current snapshot is pending',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources059,
    expectations: _stateExpectations006,
    actions: _stateActions004,
  ),
  DesignStateCase(
    caseId: 'state-84-settings-data',
    originId: '84-settings',
    taskId: 'T034',
    owner: 'SettingsView / ProfileController',
    phase:
        'SettingsView / ProfileController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources059,
    expectations: _stateExpectations072,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-84-settings-validation',
    originId: '84-settings',
    taskId: 'T034',
    owner: 'SettingsView / ProfileController',
    phase: 'SettingsView / ProfileController: ErrorCode.validation from actual local read/reload, not invalid synthetic records',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources059,
    expectations: _stateExpectations009,
    actions: _stateActions006,
  ),
  DesignStateCase(
    caseId: 'state-84-settings-denied',
    originId: '84-settings',
    taskId: 'T034',
    owner: 'SettingsView / ProfileController',
    phase: 'SettingsView / ProfileController: typed local read FORBIDDEN/UNAUTHORIZED; current private unauthorized retirement is also covered separately',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources059,
    expectations: _stateExpectations010,
    actions: _stateActions007,
  ),
  DesignStateCase(
    caseId: 'state-84-settings-unsupported',
    originId: '84-settings',
    taskId: 'T034',
    owner: 'SettingsView / ProfileController',
    phase: 'SettingsView / ProfileController: typed local read UNSUPPORTED; current private unauthorized retirement is also covered separately',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.localSnapshot,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources059,
    expectations: _stateExpectations011,
    actions: _stateActions007,
  ),
  DesignStateCase(
    caseId: 'state-84-settings-localUnavailable',
    originId: '84-settings',
    taskId: 'T037',
    owner: 'SettingsView / ProfileController',
    phase: 'SettingsView / ProfileController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources060,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-85-settings-form-loading',
    originId: '85-settings-form',
    taskId: 'T034',
    owner: 'SettingsForm / MutationController',
    phase: 'SettingsForm / MutationController: submitting, result-check/readback, or explicit conflict reread is pending',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources061,
    expectations: _stateExpectations024,
    actions: _stateActions017,
  ),
  DesignStateCase(
    caseId: 'state-85-settings-form-data',
    originId: '85-settings-form',
    taskId: 'T034',
    owner: 'SettingsForm / MutationController',
    phase:
        'SettingsForm / MutationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources061,
    expectations: _stateExpectations073,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-85-settings-form-validation',
    originId: '85-settings-form',
    taskId: 'T034',
    owner: 'SettingsForm / MutationController',
    phase: 'SettingsForm / MutationController: local invalid input and explicit service validation/revisionConflict branches',
    category: DesignStateCategory.validation,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources061,
    expectations: _stateExpectations026,
    actions: _stateActions018,
  ),
  DesignStateCase(
    caseId: 'state-85-settings-form-denied',
    originId: '85-settings-form',
    taskId: 'T034',
    owner: 'SettingsForm / MutationController',
    phase: 'SettingsForm / MutationController: definitive rejected mutation FORBIDDEN and open-form typed read reason; UNAUTHORIZED follows the owner unknown/private-retirement path',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources061,
    expectations: _stateExpectations027,
    actions: _stateActions019,
  ),
  DesignStateCase(
    caseId: 'state-85-settings-form-unsupported',
    originId: '85-settings-form',
    taskId: 'T034',
    owner: 'SettingsForm / MutationController',
    phase: 'SettingsForm / MutationController: definitive rejected mutation UNSUPPORTED and open-form typed read reason',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources061,
    expectations: _stateExpectations028,
    actions: _stateActions019,
  ),
  DesignStateCase(
    caseId: 'state-85-settings-form-localUnavailable',
    originId: '85-settings-form',
    taskId: 'T037',
    owner: 'SettingsForm / MutationController',
    phase: 'SettingsForm / MutationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources062,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-85-settings-form-unknown',
    originId: '85-settings-form',
    taskId: 'T034',
    owner: 'SettingsForm / MutationController',
    phase: 'SettingsForm / MutationController: actual lost reply -> unknown -> queued/running/not-found -> explicit same-intent retry -> committed/readback -> succeeded',
    category: DesignStateCategory.unknown,
    meaning: DesignStateMeaning.localMutation,
    scope: DesignStateScope.localOwnerIntegration,
    sources: _stateSources061,
    expectations: _stateExpectations029,
    actions: _stateActions020,
  ),
  DesignStateCase(
    caseId: 'state-94-plan-invalidated-loading',
    originId: '94-plan-invalidated',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController: existing owner request pending; use AutomationStatusSection or ServerConnectionSection before/after the real modal, not invented body props',
    category: DesignStateCategory.loading,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources023,
    expectations: _stateExpectations013,
    actions: _stateActions009,
  ),
  DesignStateCase(
    caseId: 'state-94-plan-invalidated-data',
    originId: '94-plan-invalidated',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController: data at its existing owning phase',
    category: DesignStateCategory.data,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources023,
    expectations: _stateExpectations074,
    actions: _stateActions005,
  ),
  DesignStateCase(
    caseId: 'state-94-plan-invalidated-denied',
    originId: '94-plan-invalidated',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController: legal outer TrustedLocalError FORBIDDEN/UNAUTHORIZED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.denied,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources024,
    expectations: _stateExpectations031,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-94-plan-invalidated-unsupported',
    originId: '94-plan-invalidated',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController: legal outer TrustedLocalError UNSUPPORTED mapped by actual panel/status; durable pending label alone never establishes unknown',
    category: DesignStateCategory.unsupported,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources024,
    expectations: _stateExpectations032,
    actions: _stateActions022,
  ),
  DesignStateCase(
    caseId: 'state-94-plan-invalidated-stale',
    originId: '94-plan-invalidated',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController: PLAN_STALE/PLAN_EXPIRED/TRUST_CHANGED domain invalidation, not observation age',
    category: DesignStateCategory.stale,
    meaning: DesignStateMeaning.planInvalidation,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources023,
    expectations: _stateExpectations041,
    actions: _stateActions025,
  ),
  DesignStateCase(
    caseId: 'state-94-plan-invalidated-localUnavailable',
    originId: '94-plan-invalidated',
    taskId: 'T037',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController visible private context retires through FoundationApp; late/current generations are distinct',
    category: DesignStateCategory.localUnavailable,
    meaning: DesignStateMeaning.privateRetirement,
    scope: DesignStateScope.privateEpochComposition,
    sources: _stateSources025,
    expectations: _stateExpectations012,
    actions: _stateActions008,
  ),
  DesignStateCase(
    caseId: 'state-94-plan-invalidated-sshUnavailable',
    originId: '94-plan-invalidated',
    taskId: 'T036',
    owner: 'AutomationPlanSection / AutomationPanel / AutomationController',
    phase: 'AutomationPlanSection / AutomationPanel / AutomationController: locald ready with actual selected-server connection absent/offline; use real owner status before/after modal',
    category: DesignStateCategory.sshUnavailable,
    meaning: DesignStateMeaning.automationRead,
    scope: DesignStateScope.productionPresentation,
    sources: _stateSources023,
    expectations: _stateExpectations022,
    actions: _stateActions015,
  ),
];

final designStateCasesById = Map<String, DesignStateCase>.unmodifiable({
  for (final item in designStateCases) item.caseId: item,
});
