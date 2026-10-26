import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serverdeck_protocol/automation/profile_records.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

import 'automation_controller.dart';
import 'automation_sections.dart';
import 'automation_presentation.dart';
import '../servers/server_controller.dart';
import '../theme/motion.dart';
import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';

class AutomationPanel extends StatefulWidget {
  const AutomationPanel({
    super.key,
    required this.client,
    this.serverId,
    this.installationCatalog = false,
    this.serverProfiles = const [],
  });
  final TrustedApiClient client;
  final String? serverId;
  final bool installationCatalog;
  final List<ProfileView> serverProfiles;
  @override
  State<AutomationPanel> createState() => _AutomationPanelState();
}

class _AutomationPanelState extends State<AutomationPanel> {
  late AutomationController model;
  Timer? _expiry;
  ServerController? _recipeConnection;
  bool _openingRecipes = false;
  String? _recipeConnectionError;
  String? _invalidPlanId, _invalidPlanReason;
  final _planAnchor = GlobalKey();
  final _modalChanges = ValueNotifier<int>(0);
  final _modalObservers = <VoidCallback>{};
  final _presentation = AutomationUiOperation();
  String pretty(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(value);
  @override
  void initState() {
    super.initState();
    _presentation.addListener(_presentationChanged);
    _create();
  }

  void _presentationChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _present(
    AutomationUiPhase phase,
    Future<void> Function() action, {
    VoidCallback? onAdmitted,
    ValueChanged<AutomationUiResult>? onCompleted,
  }) {
    final captured = model;
    if (captured.busy ||
        captured.client.isClosed ||
        phase.durable &&
            !(phase == AutomationUiPhase.retry
                ? captured.canRetry
                : captured.canMutate)) {
      return action();
    }
    return _presentation.run(
      phase,
      () {
        final work = action();
        if (captured.busy) onAdmitted?.call();
        return work;
      },
      result: () {
        final result = _result(captured);
        onCompleted?.call(result);
        return result;
      },
      admitted: () => captured.busy,
    );
  }

  AutomationUiResult _result(AutomationController controller) =>
      AutomationUiResult(
        errorCode: controller.error,
        pendingLabel: controller.pendingLabel,
      );

  void _create() {
    model = AutomationController(
      client: widget.client,
      serverId: widget.serverId,
    )..addListener(_changed);
    _presentation.reset();
    _present(AutomationUiPhase.initialize, model.initialize).ignore();
    _openingRecipes = false;
    _recipeConnectionError = null;
    _invalidPlanId = _invalidPlanReason = null;
    _recipeConnection = widget.installationCatalog && widget.serverId != null
        ? ServerController(client: widget.client, profileId: widget.serverId!)
        : null;
  }

  @override
  void didUpdateWidget(covariant AutomationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client) ||
        oldWidget.serverId != widget.serverId ||
        oldWidget.installationCatalog != widget.installationCatalog) {
      _expiry?.cancel();
      model.removeListener(_changed);
      model.dispose();
      _recipeConnection?.dispose();
      _create();
    }
    _notifyModalContext();
  }

  void _notifyModalContext() {
    // Retire consent synchronously, even if metadata changes back before paint.
    for (final observe in List<VoidCallback>.of(_modalObservers)) {
      observe();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _modalChanges.value++;
    });
  }

  AutomationProfileRecord? _profileForPlan(Map<String, Object?> plan) =>
      [if (model.profile != null) model.profile!, ...model.profiles]
          .where(
            (row) =>
                row.id == plan['profileId'] &&
                row.workspaceId == plan['workspaceId'],
          )
          .firstOrNull;

  void _changed() {
    _expiry?.cancel();
    if (!mounted) return;
    _presentation.observeOwner(_result(model));
    final planId = model.plan?['id'] as String?;
    if (_invalidPlanId != planId) _invalidPlanId = _invalidPlanReason = null;
    if (planId != null &&
        const {
          'PLAN_STALE',
          'PLAN_EXPIRED',
          'TRUST_CHANGED',
        }.contains(model.error)) {
      _invalidPlanId = planId;
      _invalidPlanReason = message(model.error!);
    }
    setState(() {});
    _notifyModalContext();
    final expiry = DateTime.tryParse('${model.plan?['expiresAt']}');
    if (expiry != null && expiry.isAfter(DateTime.now())) {
      _expiry = Timer(
        expiry.difference(DateTime.now()) + const Duration(milliseconds: 1),
        () {
          if (mounted) {
            setState(() {});
            _notifyModalContext();
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _presentation.removeListener(_presentationChanged);
    _presentation.dispose();
    model.removeListener(_changed);
    model.dispose();
    _recipeConnection?.dispose();
    _modalChanges.dispose();
    super.dispose();
  }

  Future<void> _loadRecipes() async {
    final captured = model, connection = _recipeConnection;
    if (connection == null) {
      await _present(AutomationUiPhase.catalog, captured.loadRecipes);
      return;
    }
    if (_openingRecipes) return;
    setState(() {
      _openingRecipes = true;
      _recipeConnectionError = null;
    });
    try {
      // Only this explicit user action connects; page construction never does.
      await connection.connect();
      if (!mounted || !identical(captured, model)) return;
      if (connection.error != null) {
        setState(() => _recipeConnectionError = connection.error);
        return;
      }
      await _present(AutomationUiPhase.catalog, captured.loadRecipes);
    } finally {
      if (mounted && identical(captured, model)) {
        setState(() => _openingRecipes = false);
      }
    }
  }

  Future<void> _createRecipePlan(String digest) async {
    final captured = model;
    await _present(
      AutomationUiPhase.recipePlan,
      () => captured.createRecipePlan(digest),
    );
    if (!mounted || !identical(captured, model) || captured.error != null)
      return;
    final id = captured.plan?['id'];
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(captured, model) || model.plan?['id'] != id)
        return;
      final anchor = _planAnchor.currentContext;
      if (anchor != null) Scrollable.ensureVisible(anchor).ignore();
    });
  }

  Map<String, Object?> parse(String source) => parseAutomationDraft(source);

  Future<void> _jsonEditor(
    String title,
    Map<String, Object?> initial,
    Future<void> Function(Map<String, Object?>) submit, {
    required AutomationUiPhase phase,
    String? purpose,
    String? target,
    Map<String, Object?>? contextDetails,
    List<String> targetServerIds = const [],
    bool Function()? contextCurrent,
  }) async {
    final captured = model;
    final serverProfiles = List<ProfileView>.unmodifiable(
      widget.serverProfiles,
    );
    final input = TextEditingController(text: pretty(initial));
    Map<String, Object?>? preview = initial;
    final submission = AutomationJsonDraftSubmission(phase);
    AutomationUiResult? ownResult;
    var invalidated = false;
    bool current(Map<String, Object?>? value) =>
        mounted &&
        identical(captured, model) &&
        !captured.client.isClosed &&
        (contextCurrent?.call() ?? true) &&
        automationTargetsUnchanged(
          [
            ...targetServerIds,
            if (value?['serverIds'] is List)
              ...(value!['serverIds'] as List).whereType<String>(),
          ],
          serverProfiles,
          widget.serverProfiles,
        );
    final reviewCurrent = automationReviewGuard(() => current(preview));
    void observe() {
      invalidated = invalidated || !reviewCurrent();
      submission.observe(
        current: !invalidated,
        pendingLabel: captured.pendingLabel,
      );
    }

    _modalObservers.add(observe);
    try {
      if (!mounted) return;
      await showMotionDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialog) => ListenableBuilder(
          listenable: Listenable.merge([submission, _modalChanges]),
          builder: (context, _) => StatefulBuilder(
            builder: (context, update) {
              observe();
              bool live() =>
                  mounted &&
                  identical(captured, model) &&
                  !captured.client.isClosed &&
                  dialog.mounted;
              bool dispatchCurrent() =>
                  live() && !invalidated && current(preview);
              void close() {
                if (live()) Navigator.pop(dialog);
              }

              return AutomationJsonEditorDialog(
                title: title,
                input: input,
                error: submission.error,
                preview: preview,
                purpose: purpose,
                target: target,
                contextDetails: contextDetails,
                serverProfiles: serverProfiles,
                targetServerIds: targetServerIds,
                contextCurrent: !invalidated,
                saving: submission.saving,
                requestRetained: submission.requestRetained,
                canContinue: phase.durable
                    ? captured.canMutate
                    : !captured.busy,
                ownerStatus:
                    !live() ||
                        !(submission.saving || submission.requestRetained)
                    ? null
                    : AutomationStatusSection(
                        busy: submission.saving,
                        openingRecipes: false,
                        canRetry:
                            !invalidated &&
                            submission.requestRetained &&
                            captured.canRetry,
                        errorCode: phase.durable ? null : submission.errorCode,
                        writeOutcome: submission.writeOutcome,
                        pendingLabel: submission.requestRetained
                            ? phase.label
                            : null,
                        operationLabel: submission.saving ? phase.label : null,
                        onRetry: () => submission
                            .retrySaved(
                              current: dispatchCurrent,
                              completionCurrent: live,
                              canRetry: () => captured.canRetry,
                              retry: (admitted) {
                                ownResult = null;
                                return _present(
                                  AutomationUiPhase.retry,
                                  captured.retryPending,
                                  onAdmitted: admitted,
                                  onCompleted: (value) => ownResult = value,
                                );
                              },
                              result: () => ownResult,
                              close: close,
                            )
                            .ignore(),
                        onDismiss: () => submission.dismissSaved(
                          completionCurrent: live,
                          dismiss: () => _presentation.dismiss(
                            captured.dismissPending,
                            () => _result(captured),
                          ),
                          pendingLabel: () => captured.pendingLabel,
                        ),
                        onStopWaiting: () {
                          if (live() && submission.saving)
                            captured.cancelInterest().ignore();
                        },
                      ),
                onChanged: (_) => update(() {
                  try {
                    preview = parse(input.text);
                  } on FormatException {
                    preview = null;
                  }
                }),
                onClose: () => Navigator.pop(dialog),
                onContinue: () async {
                  observe();
                  if (invalidated) return;
                  await submission.submit(
                    source: input.text,
                    current: dispatchCurrent,
                    draftCurrent: current,
                    completionCurrent: live,
                    canSubmit: () =>
                        phase.durable ? captured.canMutate : !captured.busy,
                    targetsAvailable: (value) => automationTargetsAvailable([
                      ...targetServerIds,
                      if (value['serverIds'] is List)
                        ...(value['serverIds'] as List).whereType<String>(),
                    ], serverProfiles),
                    submit: (value, admitted) {
                      ownResult = null;
                      return _present(
                        phase,
                        () => submit(value),
                        onAdmitted: admitted,
                        onCompleted: (value) => ownResult = value,
                      );
                    },
                    result: () => ownResult,
                    close: close,
                  );
                },
              );
            },
          ),
        ),
      );
    } finally {
      _modalObservers.remove(observe);
      submission.dispose();
      input.dispose();
    }
  }

  Future<void> _editProfile({AutomationProfileRecord? existing}) async {
    final controller = model;
    final baseRevision = existing == null
        ? null
        : controller.revision!['revision'] as int;
    final name = TextEditingController(text: existing?.name ?? 'Новый профиль');
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    final body = TextEditingController(
      text: pretty(
        existing == null
            ? {
                'format': 1,
                'environment': 'ubuntu24.04-amd64-systemd',
                'parameters': <String, Object?>{},
                'steps': [
                  {
                    'id': 'motd',
                    'kind': 'config_file',
                    'resourceId': 'system.motd',
                    'values': {'text': 'Managed by ServerDeck'},
                  },
                ],
              }
            : controller.revision!['body'],
      ),
    );
    final submission = AutomationProfileDraftSubmission(
      initialBasis: existing == null
          ? null
          : AutomationProfileBasis(
              profile: existing,
              revision: baseRevision!,
              digest: controller.revision!['digest'] as String,
            ),
    );
    bool current() =>
        mounted &&
        identical(controller, model) &&
        !controller.client.isClosed &&
        !submission.contextRetired;
    bool basisCurrent(AutomationProfileBasis basis) =>
        basis.matches(controller.profile, controller.revision);
    void observe() =>
        submission.observeBasis(current: current(), unchanged: basisCurrent);
    _modalObservers.add(observe);
    Future<void> readBasis(BuildContext dialog) => submission.readBasis(
      current: () => current() && dialog.mounted,
      canRead: () => controller.canMutate,
      pendingLabel: () => controller.pendingLabel,
      read: () async {
        await _present(
          AutomationUiPhase.version,
          () => controller.selectProfile(existing!.id),
        );
        if (!current() || !dialog.mounted || controller.error != null)
          return null;
        final profile = controller.profile, revision = controller.revision;
        if (profile == null || revision == null) return null;
        return AutomationProfileBasis.fromOwner(
          profile,
          revision,
          currentHead: true,
        );
      },
    );
    String? error;
    var validating = false;
    Map<String, Object?>? draftValidation;
    try {
      if (!mounted) return;
      await showMotionDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialog) => ListenableBuilder(
          listenable: Listenable.merge([submission, _modalChanges]),
          builder: (context, _) => StatefulBuilder(
            builder: (context, update) {
              observe();
              return AutomationProfileEditorDialog(
                existing: submission.currentBasis?.profile ?? existing,
                baseRevision: baseRevision,
                name: name,
                description: description,
                body: body,
                validation: draftValidation,
                error: submission.error ?? error,
                nameError: submission.nameError,
                descriptionError: submission.descriptionError,
                saveError: submission.saveError,
                saveUnconfirmed: submission.saveUnconfirmed,
                saving: submission.saving,
                contextCurrent: current(),
                requestRetained: controller.pendingLabel != null,
                canSave:
                    !submission.saving &&
                    current() &&
                    controller.canMutate &&
                    !submission.requiresNewBasis &&
                    (submission.currentBasis == null ||
                        basisCurrent(submission.currentBasis!)),
                ownerStatus: !current()
                    ? null
                    : AutomationStatusSection(
                        busy: controller.busy,
                        openingRecipes: false,
                        canRetry: controller.canRetry,
                        errorCode: _presentation.readErrorCode,
                        writeOutcome: _presentation.writeOutcome,
                        pendingLabel: controller.pendingLabel,
                        operationLabel: _presentation.label,
                        onRetry: () => submission
                            .retrySaved(
                              retry: () => _present(
                                AutomationUiPhase.retry,
                                controller.retryPending,
                              ),
                              canRetry: () => controller.canRetry,
                              current: () => current() && dialog.mounted,
                              resultError: () => controller.error,
                              pendingLabel: () => controller.pendingLabel,
                              close: () {
                                if (current() && dialog.mounted)
                                  Navigator.pop(dialog);
                              },
                            )
                            .ignore(),
                        onDismiss: () {
                          if (!current()) return;
                          submission.dismissSaved(
                            dismiss: () => _presentation.dismiss(
                              controller.dismissPending,
                              () => _result(controller),
                            ),
                            pendingLabel: () => controller.pendingLabel,
                          );
                        },
                        onStopWaiting: () {
                          if (current()) controller.cancelInterest().ignore();
                        },
                      ),
                basisReview: AutomationProfileBasisReview(
                  submission: submission,
                  requestRetained: controller.pendingLabel != null,
                  canRead:
                      current() && controller.canMutate && !submission.saving,
                  canAccept: current() && controller.canMutate,
                  onRead: () => readBasis(dialog).ignore(),
                  onAccept: () => submission.acceptBasis(
                    current: () => current() && dialog.mounted,
                    canAccept: () => controller.canMutate,
                    unchanged: basisCurrent,
                  ),
                ),
                validating: validating,
                canValidate: !validating && !model.busy,
                onBodyChanged: (_) {
                  if (current() && context.mounted)
                    update(() => draftValidation = null);
                },
                onClose: () {
                  if (dialog.mounted) Navigator.pop(dialog);
                },
                onSave: () => submission
                    .save(
                      name: name.text,
                      description: description.text,
                      source: body.text,
                      current: () => current() && dialog.mounted,
                      canSubmit: () => controller.canMutate,
                      basisCurrent: basisCurrent,
                      submit: (capturedName, capturedDescription, parsed) =>
                          _present(
                            AutomationUiPhase.saveProfile,
                            () => controller.saveProfile(
                              name: capturedName,
                              description: capturedDescription,
                              body: parsed,
                              existing:
                                  submission.currentBasis?.profile ?? existing,
                            ),
                          ),
                      resultError: () => controller.error,
                      pendingLabel: () => controller.pendingLabel,
                      close: () {
                        if (dialog.mounted) Navigator.pop(dialog);
                      },
                    )
                    .ignore(),
                onValidate: () async {
                  if (!current() ||
                      !dialog.mounted ||
                      !context.mounted ||
                      validating ||
                      controller.busy)
                    return;
                  final source = body.text;
                  try {
                    final input = parse(source);
                    update(() {
                      validating = true;
                      error = null;
                      draftValidation = null;
                    });
                    await _present(
                      AutomationUiPhase.validate,
                      () => controller.validateBody(input),
                    );
                    if (!current() || !dialog.mounted || !context.mounted)
                      return;
                    update(() {
                      if (body.text == source) {
                        draftValidation = controller.validation;
                        error = controller.error == null
                            ? null
                            : message(controller.error!);
                      } else {
                        error = 'Черновик изменён — проверьте его ещё раз';
                      }
                    });
                  } on FormatException {
                    if (current() && context.mounted)
                      update(() => error = 'Проверьте формат JSON');
                  } finally {
                    if (current() && context.mounted)
                      update(() => validating = false);
                  }
                },
              );
            },
          ),
        ),
      );
    } finally {
      _modalObservers.remove(observe);
      submission.dispose();
      name.dispose();
      description.dispose();
      body.dispose();
    }
  }

  Future<void> _decision(Map<String, Object?> plan, bool approve) async {
    final captured = model;
    final serverProfiles = List<ProfileView>.unmodifiable(
      widget.serverProfiles,
    );
    final profileStamp = pretty(_profileForPlan(plan)?.toJson());
    final planStamp = pretty(plan);
    final current = automationReviewGuard(
      () =>
          mounted &&
          identical(captured, model) &&
          !captured.client.isClosed &&
          pretty(captured.plan) == planStamp &&
          pretty(_profileForPlan(plan)?.toJson()) == profileStamp &&
          automationTargetsUnchanged(
            [if (plan['serverId'] is String) plan['serverId'] as String],
            serverProfiles,
            widget.serverProfiles,
          ),
    );
    void observe() {
      current();
    }

    _modalObservers.add(observe);
    bool? result;
    try {
      result = await showMotionDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialog) => ListenableBuilder(
          listenable: _modalChanges,
          builder: (context, _) => AutomationPlanDecisionDialog(
            plan: plan,
            serverProfiles: widget.serverProfiles,
            automationProfile: _profileForPlan(plan),
            contextCurrent: current(),
            approve: approve,
            onBack: () => Navigator.pop(dialog, false),
            onConfirm: () => Navigator.pop(dialog, true),
          ),
        ),
      );
    } finally {
      _modalObservers.remove(observe);
    }
    final deadline = DateTime.tryParse('${plan['expiresAt']}');
    if (result == true &&
        current() &&
        (!approve ||
            automationPlanTargetAvailable(plan, widget.serverProfiles) &&
                _profileForPlan(plan) != null) &&
        captured.plan?['id'] == plan['id'] &&
        _invalidPlanId != plan['id'] &&
        deadline != null &&
        deadline.isAfter(DateTime.now())) {
      await _present(
        approve ? AutomationUiPhase.approve : AutomationUiPhase.deny,
        () => captured.approvePlan(plan, approve: approve),
      );
    }
  }

  Future<void> _delegate() async {
    final controller = model, selected = model.revision;
    final body = selected?['body'] as Map<String, Object?>?;
    if (body == null || selected == null) return;
    final revisionStamp = pretty(selected);
    final profileStamp = pretty(controller.profile?.toJson());
    final targetId = widget.serverId;
    bool current() =>
        mounted &&
        identical(controller, model) &&
        widget.serverId == targetId &&
        pretty(controller.revision) == revisionStamp &&
        pretty(controller.profile?.toJson()) == profileStamp;
    await _present(AutomationUiPhase.grants, controller.refreshGrants);
    if (!current()) return;
    final eligible = controller.grants
        .where(
          (row) =>
              grantCurrent(row) &&
              (row['scopes'] as List).contains('apply') &&
              (row['scopes'] as List).contains('plan') &&
              (row['serverIds'] as List).contains(widget.serverId),
        )
        .toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Выдайте клиенту ИИ права plan и apply на этот сервер в разделе доступа.',
          ),
        ),
      );
      return;
    }
    final grant = await showMotionDialog<Map<String, Object?>>(
      context: context,
      barrierDismissible: true,
      builder: (dialog) => AutomationDelegationGrantDialog(
        grants: eligible,
        onSelect: (row) => Navigator.pop(dialog, row),
      ),
    );
    if (grant == null || !current()) return;
    final definitions = body['parameters'] as Map<String, Object?>;
    final predicates = <String, Object?>{};
    for (final row in definitions.entries) {
      final value = (row.value as Map<String, Object?>)['default'];
      predicates[row.key] = value is int
          ? {'type': 'integer', 'minimum': value, 'maximum': value}
          : {
              'type': 'enum',
              'values': [value],
            };
    }
    await _jsonEditor(
      'Делегирование «${grant['label']}» · версия ${selected['revision']}',
      {'lifetimeSeconds': 3600, 'predicates': predicates},
      (value) => controller.createDelegation(
        displayedRevision: selected,
        grantId: grant['id'] as String,
        lifetimeSeconds: value['lifetimeSeconds'] as int,
        predicates: value['predicates'] as Map<String, Object?>,
      ),
      phase: AutomationUiPhase.delegate,
      purpose: 'Разрешить запуск только этой неизменной версии в заданных границах параметров. Новые версии потребуют отдельного делегирования.',
      target:
          'Ansible-профиль: ${controller.profile?.name ?? 'Название профиля недоступно'} · версия ${selected['revision']}. Доступ клиента до: ${grant['expiresAt']} (UTC).',
      targetServerIds: [if (targetId != null) targetId],
      contextCurrent: current,
      contextDetails: {
        'profileId': selected['profileId'],
        'revision': selected['revision'],
        'bodyDigest': selected['digest'],
        'serverId': widget.serverId,
        'grantId': grant['id'],
      },
    );
  }

  bool grantCurrent(Map<String, Object?> row) {
    return automationGrantCurrent(row);
  }

  Future<void> _grantEditor({Map<String, Object?>? existing}) {
    final captured = model;
    final stamp = pretty(existing);
    return _jsonEditor(
      existing == null
          ? 'Выдать ИИ доступ через MCP'
          : 'Изменить права и перевыпустить доступ',
      {
        'label': existing?['label'] ?? 'ИИ-клиент',
        'scopes':
            existing?['scopes'] ??
            (widget.serverId == null
                ? ['author']
                : ['read', 'logs', 'author', 'plan']),
        'serverIds':
            existing?['serverIds'] ??
            (widget.serverId == null ? <String>[] : [widget.serverId]),
        'lifetimeSeconds': existing == null
            ? 28800
            : DateTime.parse(existing['expiresAt'] as String)
                  .difference(DateTime.parse(existing['issuedAt'] as String))
                  .inSeconds,
      },
      (value) => captured.saveGrant(value, existing: existing),
      phase: existing == null
          ? AutomationUiPhase.saveGrant
          : AutomationUiPhase.replaceGrant,
      contextCurrent: () =>
          existing == null ||
          captured.grants.any(
            (row) => row['id'] == existing['id'] && pretty(row) == stamp,
          ),
      purpose: existing == null
          ? 'Выдайте только необходимые права на перечисленные серверы. Сохранение выдаст доступ клиенту ИИ на указанный срок.'
          : 'Сохранение заменит права и перевыпустит доступ клиента ИИ на указанный срок.',
    );
  }

  Future<void> _revokeGrant(Map<String, Object?> row) async {
    final captured = model;
    final yes = await showMotionDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialog) => AutomationConfirmationDialog(
        title: 'Отозвать доступ «${row['label']}»?',
        message: 'Текущий шаг задания может завершиться. Следующие шаги потребуют действующих прав.',
        confirmLabel: 'Отозвать доступ',
        onBack: () => Navigator.pop(dialog, false),
        onConfirm: () => Navigator.pop(dialog, true),
      ),
    );
    if (yes == true && mounted && identical(captured, model))
      await _present(
        AutomationUiPhase.revokeGrant,
        () => captured.revokeGrant(row),
      );
  }

  Future<void> _archiveProfile(AutomationProfileRecord selected) async {
    final captured = model;
    final yes = await showMotionDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialog) => AutomationConfirmationDialog(
        title: 'Архивировать «${selected.name}»?',
        message: 'История версий и заданий сохранится.',
        confirmLabel: 'Архивировать',
        onBack: () => Navigator.pop(dialog, false),
        onConfirm: () => Navigator.pop(dialog, true),
      ),
    );
    if (yes == true && mounted && identical(captured, model))
      await _present(
        AutomationUiPhase.archive,
        () => captured.archiveProfile(selected),
      );
  }

  String message(String code) => automationMessage(code);

  @override
  Widget build(BuildContext context) {
    final selected = model.profile,
        revision = model.revision,
        plan = model.plan,
        job = model.job;
    final deadline = DateTime.tryParse('${plan?['expiresAt']}');
    final invalidPlan = _invalidPlanId != null && _invalidPlanId == plan?['id'];
    final runnable =
        !invalidPlan &&
        plan?['status'] == 'runnable' &&
        deadline != null &&
        deadline.isAfter(DateTime.now());
    final expired = deadline != null && !deadline.isAfter(DateTime.now());
    final actions = AutomationActionAvailability(
      read: !_openingRecipes && !model.busy && !widget.client.isClosed,
      mutate: !_openingRecipes && model.canMutate,
      select: !model.busy && !_openingRecipes,
    );
    return AbsorbPointer(
      absorbing: _openingRecipes,
      child: DeckSurface(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: widget.installationCatalog,
          title: DeckFocusLabel(
            child: Text(
              widget.installationCatalog
                  ? 'ПО и планы установки'
                  : widget.serverId == null
                  ? 'ИИ-доступ и Ansible-профили'
                  : 'Автоматизация',
            ),
          ),
          childrenPadding: const EdgeInsets.all(BrandSpacing.space16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AutomationStatusSection(
              busy: model.busy,
              openingRecipes: _openingRecipes,
              canRetry: model.canRetry,
              recipeConnectionError: _recipeConnectionError == null
                  ? null
                  : message(_recipeConnectionError!),
              errorCode: _presentation.readErrorCode,
              writeOutcome: _presentation.writeOutcome,
              operationLabel: _presentation.label,
              pendingLabel: model.pendingLabel,
              onRetry: () => _present(
                AutomationUiPhase.retry,
                model.retryPending,
              ).ignore(),
              onDismiss: () => _presentation.dismiss(
                model.dismissPending,
                () => _result(model),
              ),
              onStopWaiting: () => model.cancelInterest().ignore(),
            ),
            AutomationProfileActions(
              actions: actions,
              hasServer: widget.serverId != null,
              installationCatalog: widget.installationCatalog,
              onRefresh: () => _present(
                AutomationUiPhase.profiles,
                model.refreshProfiles,
              ).ignore(),
              onCreate: () => _editProfile().ignore(),
              onLoadRecipes: () => _loadRecipes().ignore(),
            ),
            if (model.catalog != null)
              AutomationRecipesSection(
                catalog: model.catalog!,
                canMutate: actions.mutate,
                onCreatePlan: (digest) => _createRecipePlan(digest).ignore(),
              ),
            AutomationProfilesSection(
              profiles: model.profiles,
              loaded: model.profilesLoaded,
              hasMore: model.profilesCursor != null,
              selectedId: selected?.id,
              actions: actions,
              onSelect: (id) => _present(
                AutomationUiPhase.version,
                () => model.selectProfile(id),
              ).ignore(),
              onMore: () => _present(
                AutomationUiPhase.profiles,
                () => model.refreshProfiles(more: true),
              ).ignore(),
              beforeProfiles: AutomationGrantsSection(
                serverProfiles: widget.serverProfiles,
                grants: [
                  for (final row in model.grants)
                    AutomationGrantPresentation(
                      value: row,
                      current: grantCurrent(row),
                    ),
                ],
                loaded: model.grantsLoaded,
                actions: actions,
                launchConfiguration: model.launchConfiguration,
                onRefresh: () => _present(
                  AutomationUiPhase.grants,
                  model.refreshGrants,
                ).ignore(),
                onCreate: () => _grantEditor().ignore(),
                onConfigure: (id) => _present(
                  AutomationUiPhase.configuration,
                  () => model.configurationForGrant(id),
                ).ignore(),
                onEdit: (row) => _grantEditor(existing: row).ignore(),
                onRevoke: (row) => _revokeGrant(row).ignore(),
                onCopyConfiguration: () => Clipboard.setData(
                  ClipboardData(text: pretty(model.launchConfiguration)),
                ).ignore(),
              ),
            ),
            if (selected != null && revision != null)
              AutomationProfileDetailSection(
                profile: selected,
                revision: revision,
                validation: model.validation,
                comparison: model.comparison,
                hasServer: widget.serverId != null,
                actions: actions,
                onSelectVersion: () => _jsonEditor(
                  'Версия профиля',
                  {'revision': revision['revision']},
                  (value) => model.selectProfile(
                    selected.id,
                    version: value['revision'] as int,
                  ),
                  phase: AutomationUiPhase.version,
                ).ignore(),
                onValidate: () => _present(
                  AutomationUiPhase.validate,
                  () => model.validateBody(
                    revision['body'] as Map<String, Object?>,
                  ),
                ).ignore(),
                onCompare: () => _jsonEditor(
                  'Сравнение шагов двух версий',
                  {
                    'fromRevision': (revision['revision'] as int) > 1
                        ? (revision['revision'] as int) - 1
                        : 1,
                    'toRevision': revision['revision'],
                  },
                  (value) => model.compareVersions(value),
                  phase: AutomationUiPhase.compare,
                ).ignore(),
                onEdit: () => _editProfile(existing: selected).ignore(),
                onCreatePlan: () {
                  final captured = model;
                  final revisionStamp = pretty(revision);
                  final profileStamp = pretty(selected.toJson());
                  final targetId = widget.serverId;
                  final parameters =
                      (revision['body'] as Map<String, Object?>)['parameters']
                          as Map<String, Object?>;
                  _jsonEditor(
                    'Параметры плана',
                    {
                      for (final row in parameters.entries)
                        row.key: (row.value as Map<String, Object?>)['default'],
                    },
                    (value) => captured.createPlan(value),
                    phase: AutomationUiPhase.createPlan,
                    purpose: 'Проверьте параметры для выбранной версии. Продолжение создаст план; запуск потребует отдельного подтверждения.',
                    target:
                        'Ansible-профиль: ${selected.name} · версия ${revision['revision']}.',
                    targetServerIds: [if (targetId != null) targetId],
                    contextCurrent: () =>
                        widget.serverId == targetId &&
                        pretty(captured.revision) == revisionStamp &&
                        pretty(captured.profile?.toJson()) == profileStamp,
                    contextDetails: {
                      'profileId': selected.id,
                      'revision': revision['revision'],
                      'bodyDigest': revision['digest'],
                      'serverId': widget.serverId,
                    },
                  ).ignore();
                },
                onDelegate: () => _delegate().ignore(),
                onArchive: () => _archiveProfile(selected).ignore(),
              ),
            if (plan != null)
              AutomationPlanSection(
                plan: plan,
                serverProfiles: widget.serverProfiles,
                automationProfile: _profileForPlan(plan),
                runnable: runnable,
                expired: expired,
                invalidReason: invalidPlan ? _invalidPlanReason : null,
                planAnchor: _planAnchor,
                actions: actions,
                onApprove: () => _decision(plan, true).ignore(),
                onDeny: () => _decision(plan, false).ignore(),
                onApply: () {
                  if (!automationPlanExpired(plan) &&
                      _invalidPlanId != plan['id'] &&
                      pretty(model.plan) == pretty(plan) &&
                      automationPlanTargetAvailable(
                        plan,
                        widget.serverProfiles,
                      ) &&
                      _profileForPlan(plan) != null) {
                    _present(
                      AutomationUiPhase.apply,
                      () => model.applyPlan(plan),
                    ).ignore();
                  }
                },
                onRefresh: () => _present(
                  AutomationUiPhase.plan,
                  () => model.loadPlan(plan['id'] as String),
                ).ignore(),
              ),
            if (widget.serverId != null) ...[
              AutomationJobsSection(
                serverId: widget.serverId,
                jobs: model.jobs,
                job: job,
                events: model.events,
                loaded: model.jobsLoaded,
                hasMore: model.jobsCursor != null,
                droppedEvents: model.droppedEvents,
                canCancel:
                    job != null &&
                    !AutomationController.terminal.contains(job['state']) &&
                    job['cancelRequested'] != true,
                canReconcile: job?['state'] == 'unknown',
                actions: actions,
                onRefresh: () => _present(
                  AutomationUiPhase.jobs,
                  model.refreshJobs,
                ).ignore(),
                onRefreshAuthorities: () => _present(
                  AutomationUiPhase.authorities,
                  model.refreshAuthorities,
                ).ignore(),
                onSelect: (id) => _present(
                  AutomationUiPhase.job,
                  () => model.selectJob(id),
                ).ignore(),
                onMore: () => _present(
                  AutomationUiPhase.jobs,
                  () => model.refreshJobs(more: true),
                ).ignore(),
                onShowPlan: () => _present(
                  AutomationUiPhase.plan,
                  () => model.loadPlan(job!['immutablePlanId'] as String),
                ).ignore(),
                onCancel: () => _present(
                  AutomationUiPhase.cancelJob,
                  () => model.jobAction(job!['id'] as String, reconcile: false),
                ).ignore(),
                onReconcile: () => _present(
                  AutomationUiPhase.reconcile,
                  () => model.jobAction(job!['id'] as String, reconcile: true),
                ).ignore(),
              ),
              AutomationAuthoritiesSection(
                approvals: model.approvals,
                delegations: model.delegations,
                loaded: model.authoritiesLoaded,
                hasMoreApprovals: model.approvalsNext != null,
                hasMoreDelegations: model.delegationsNext != null,
                actions: actions,
                onOpenPlan: (id) => _present(
                  AutomationUiPhase.plan,
                  () => model.loadPlan(id),
                ).ignore(),
                onRevokeDelegation: (row) => _present(
                  AutomationUiPhase.revokeDelegation,
                  () => model.revokeDelegation(row),
                ).ignore(),
                onMoreApprovals: () => _present(
                  AutomationUiPhase.authorities,
                  () => model.moreAuthorities(approvals: true),
                ).ignore(),
                onMoreDelegations: () => _present(
                  AutomationUiPhase.authorities,
                  () => model.moreAuthorities(approvals: false),
                ).ignore(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
