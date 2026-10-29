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
import '../ui/deck_icon.dart';
import '../ui/deck_page.dart';

String automationPageDescription(String screenId) => switch (screenId) {
  '17-recipe-detail' ||
  '34-profile-revisions' ||
  '38-mcp-client-config' => 'Сведения, наблюдения и доступные действия',
  '18-install-preflight' || '19-plan-approval' =>
    'Проверьте цель, последствия и условия выбранного действия',
  '28-job-detail' ||
  '30-job-cancel' => 'Состояние шагов, события и результат выполнения',
  '29-job-unknown' =>
    'Уточните результат прежней операции перед следующим действием',
  '94-plan-invalidated' =>
    'Для продолжения нужна новая проверка исходного состояния',
  '93-protected-effect-blocked' => 'Исполнение плана не разрешено',
  _ => 'Просматривайте данные, состояние и доступные действия',
};

/// Shared production composition. Fixture transports may supply the same body
/// widgets without constructing an authenticated runtime controller.
class AutomationPageFrame extends StatelessWidget {
  const AutomationPageFrame({
    super.key,
    required this.title,
    this.description,
    this.screenId,
    this.catalog = false,
    this.contextBar,
    required this.section,
    required this.onSelected,
    this.actions = const [],
    required this.child,
  });
  final String title;
  final String? description, screenId;
  final bool catalog;
  final Widget? contextBar;
  final String section;
  final ValueChanged<String> onSelected;
  final List<Widget> actions;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final catalogList =
        screenId == '16-install-catalog' ||
        screenId == null &&
            catalog &&
            section == 'catalog' &&
            title == 'Каталог установки';
    return DeckPage(
      title: title,
      description: description,
      eyebrow:
          screenId == '36-ai-grants' ||
              screenId == '38-mcp-client-config' ||
              section == 'grants'
          ? 'Настройки / Рабочее пространство'
          : catalog
          ? 'ПО / Рабочее пространство'
          : 'Задания / Рабочее пространство',
      actions: actions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (catalogList) ...[
            DeckTabs(
              labels: const ['Каталог', 'Планы установки'],
              selected: section == 'plans' ? 1 : 0,
              onSelected: (index) =>
                  onSelected(index == 0 ? 'catalog' : 'plans'),
            ),
            const DeckTabsGap(),
          ],
          if (catalogList && contextBar != null) ...[
            contextBar!,
            const SizedBox(height: 20),
          ],
          child,
        ],
      ),
    );
  }
}

/// Shared list-header controls. Each callback is supplied by the existing
/// owner; this builder only places the canonical controls in their page region.
List<Widget> automationPageActions({
  required String section,
  required AutomationActionAvailability availability,
  required VoidCallback onRefresh,
  required VoidCallback onCreate,
  required VoidCallback onLoadRecipes,
  VoidCallback? onOpenJob,
  VoidCallback? onSelectRecipe,
  VoidCallback? onEdit,
  bool detail = false,
}) {
  if (detail) return const [];
  return switch (section) {
    'catalog' => [
      OutlinedButton(
        clipBehavior: Clip.none,
        onPressed: availability.read ? onLoadRecipes : null,
        child: const Text('Подключиться и открыть рецепты'),
      ),
      OutlinedButton(
        clipBehavior: Clip.none,
        onPressed: onSelectRecipe,
        child: const Text('Выбрать программу'),
      ),
    ],
    'profiles' => [
      OutlinedButton(
        clipBehavior: Clip.none,
        onPressed: availability.mutate ? onCreate : null,
        child: const Text('Новый профиль'),
      ),
      OutlinedButton(
        clipBehavior: Clip.none,
        onPressed: availability.read ? onRefresh : null,
        child: const DeckButtonLabel(
          icon: 'refresh',
          label: 'Обновить профили',
        ),
      ),
    ],
    'jobs' => [
      OutlinedButton(
        clipBehavior: Clip.none,
        onPressed: availability.read ? onRefresh : null,
        child: const DeckButtonLabel(icon: 'refresh', label: 'Обновить'),
      ),
      OutlinedButton(
        clipBehavior: Clip.none,
        onPressed: availability.read ? onOpenJob : null,
        child: const Text('Открыть задание'),
      ),
    ],
    'grants' => [
      OutlinedButton(
        clipBehavior: Clip.none,
        onPressed: availability.mutate ? onCreate : null,
        child: const Text('Выдать доступ'),
      ),
      OutlinedButton(
        clipBehavior: Clip.none,
        onPressed: availability.mutate ? onEdit : null,
        child: const Text('Изменить права'),
      ),
    ],
    'authorities' => [
      OutlinedButton(
        clipBehavior: Clip.none,
        onPressed: availability.read ? onRefresh : null,
        child: const Text('Обновить разрешения'),
      ),
    ],
    _ => const [],
  };
}

class AutomationPanel extends StatefulWidget {
  const AutomationPanel({
    super.key,
    required this.client,
    this.serverId,
    this.installationCatalog = false,
    this.serverProfiles = const [],
    this.initialSection,
    this.contextBar,
    this.contextBarBuilder,
    this.workspaceActions = const [],
    this.onPlanReview,
  });
  final TrustedApiClient client;
  final String? serverId;
  final bool installationCatalog;
  final List<ProfileView> serverProfiles;
  final String? initialSection;
  final Widget? contextBar;
  final Widget Function(String? environment)? contextBarBuilder;
  final List<Widget> workspaceActions;

  /// Temporarily presents the plan review in Jobs without changing its owner.
  final VoidCallback Function()? onPlanReview;
  @override
  State<AutomationPanel> createState() => _AutomationPanelState();
}

class _AutomationPanelState extends State<AutomationPanel> {
  late AutomationController model;
  String _section = 'profiles';
  bool _profileDetail = false,
      _jobDetail = false,
      _recipeDetail = false,
      _planReviewed = false;
  String? _lastPlanId, _closedPlanId, _lastJobId, _selectedGrantId;
  bool _configurationDetail = false;
  final _recipesKey = GlobalKey<AutomationRecipesSectionState>();
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
    _section =
        widget.initialSection ??
        (widget.installationCatalog ? 'catalog' : 'profiles');
    _lastPlanId = _closedPlanId = _lastJobId = _selectedGrantId = null;
    _configurationDetail = false;
    _profileDetail = _jobDetail = _recipeDetail = _planReviewed = false;
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
    if (oldWidget.initialSection != widget.initialSection &&
        widget.initialSection != null) {
      _section = widget.initialSection!;
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
    if (planId != null && planId != _lastPlanId) {
      _lastPlanId = planId;
      _closedPlanId = null;
      _section = 'plans';
      _planReviewed = false;
    }
    final jobId = model.job?['id'] as String?;
    if (jobId != null && jobId != _lastJobId) {
      _lastJobId = jobId;
      _section = 'jobs';
      _jobDetail = true;
    }
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
    final now = DateTime.now();
    final deadlines =
        [
              model.plan?['expiresAt'],
              for (final grant in model.grants) grant['expiresAt'],
            ]
            .map((value) => DateTime.tryParse('$value'))
            .whereType<DateTime>()
            .where((value) => value.isAfter(now))
            .toList()
          ..sort();
    final expiry = deadlines.firstOrNull;
    if (expiry != null) {
      _expiry = Timer(
        expiry.difference(now) + const Duration(milliseconds: 1),
        () {
          if (mounted) {
            _changed();
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

  Rect? _workspaceBounds() {
    if (!mounted) return null;
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize)
      return null;
    return render.localToGlobal(Offset.zero) & render.size;
  }

  EdgeInsetsGeometry _workspaceInsets() =>
      mounted ? DeckPageInsets.of(context) : EdgeInsets.zero;

  Future<void> _jsonEditor(
    String title,
    Map<String, Object?> initial,
    Future<void> Function(Map<String, Object?>) submit, {
    required AutomationUiPhase phase,
    String? purpose,
    String? target,
    String? clientLabel,
    Map<String, Object?>? contextDetails,
    List<String> targetServerIds = const [],
    bool Function()? contextCurrent,
    Map<String, Object?> parameterDefinitions = const {},
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
        barrierColor: Colors.transparent,
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
                workspaceBounds: _workspaceBounds,
                pageInsets: _workspaceInsets,
                title: title,
                eyebrow: switch (phase) {
                  AutomationUiPhase.saveGrant ||
                  AutomationUiPhase.replaceGrant =>
                    'Настройки / Рабочее пространство',
                  _ => 'Задания / Рабочее пространство',
                },
                formKind: switch (phase) {
                  AutomationUiPhase.createPlan =>
                    AutomationEditorKind.planParameters,
                  AutomationUiPhase.delegate => AutomationEditorKind.delegation,
                  _ => AutomationEditorKind.generic,
                },
                input: input,
                parameterDefinitions: parameterDefinitions,
                submitLabel: switch (phase) {
                  AutomationUiPhase.createPlan => 'Создать план',
                  AutomationUiPhase.saveGrant => 'Выдать доступ',
                  AutomationUiPhase.replaceGrant => 'Изменить права',
                  AutomationUiPhase.delegate => 'Делегировать версию',
                  _ => 'Продолжить',
                },
                error: submission.error,
                preview: preview,
                purpose: purpose,
                target: target,
                clientLabel: clientLabel,
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
        barrierColor: Colors.transparent,
        builder: (dialog) => ListenableBuilder(
          listenable: Listenable.merge([submission, _modalChanges]),
          builder: (context, _) => StatefulBuilder(
            builder: (context, update) {
              observe();
              return AutomationProfileEditorDialog(
                workspaceBounds: _workspaceBounds,
                pageInsets: _workspaceInsets,
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
    var alternate = false;
    final endReview = widget.onPlanReview?.call();
    try {
      result = await showMotionDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        builder: (dialog) => ListenableBuilder(
          listenable: _modalChanges,
          builder: (context, _) => AutomationPlanDecisionDialog(
            workspaceBounds: _workspaceBounds,
            pageInsets: _workspaceInsets,
            plan: plan,
            serverProfiles: widget.serverProfiles,
            automationProfile: _profileForPlan(plan),
            contextCurrent: current(),
            approve: approve,
            onBack: () => Navigator.pop(dialog, false),
            onAlternate: () {
              if (!current()) return;
              alternate = true;
              Navigator.pop(dialog, false);
            },
            onConfirm: () => Navigator.pop(dialog, true),
          ),
        ),
      );
    } finally {
      _modalObservers.remove(observe);
      endReview?.call();
    }
    if (alternate && current()) {
      await _decision(plan, !approve);
      return;
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
    final grantStamp = pretty(grant);
    bool delegationCurrent() =>
        current() &&
        grantCurrent(grant) &&
        controller.grants.any(
          (row) => row['id'] == grant['id'] && pretty(row) == grantStamp,
        );
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
      'Делегирование версии',
      {'lifetimeSeconds': 3600, 'predicates': predicates},
      (value) => controller.createDelegation(
        displayedRevision: selected,
        grantId: grant['id'] as String,
        lifetimeSeconds: value['lifetimeSeconds'] as int,
        predicates: value['predicates'] as Map<String, Object?>,
      ),
      phase: AutomationUiPhase.delegate,
      clientLabel: grant['label'] as String,
      purpose: 'Разрешить запуск только этой неизменной версии в заданных границах параметров. Новые версии потребуют отдельного делегирования.',
      target:
          'Ansible-профиль: ${controller.profile?.name ?? 'Название профиля недоступно'} · версия ${selected['revision']}. Доступ клиента до: ${grant['expiresAt']} (UTC).',
      targetServerIds: [if (targetId != null) targetId],
      contextCurrent: delegationCurrent,
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
          ? 'Выдать доступ ИИ'
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

  Future<void> _selectAutomationProfile(String id) async {
    final captured = model;
    await _present(AutomationUiPhase.version, () => captured.selectProfile(id));
    if (mounted &&
        identical(captured, model) &&
        captured.error == null &&
        captured.profile?.id == id)
      setState(() => _profileDetail = true);
  }

  Future<void> _configureGrant(String id) async {
    final captured = model;
    await _present(
      AutomationUiPhase.configuration,
      () => captured.configurationForGrant(id),
    );
    if (mounted &&
        identical(captured, model) &&
        captured.error == null &&
        captured.launchConfiguration != null)
      setState(() => _configurationDetail = true);
  }

  Future<void> _selectVersion() async {
    final selected = model.profile, revision = model.revision;
    if (selected == null || revision == null) return;
    await _jsonEditor(
      'Версия профиля',
      {'revision': revision['revision']},
      (value) =>
          model.selectProfile(selected.id, version: value['revision'] as int),
      phase: AutomationUiPhase.version,
    );
  }

  Future<void> _selectJob(String id) async {
    final captured = model;
    await _present(AutomationUiPhase.job, () => captured.selectJob(id));
    if (mounted &&
        identical(captured, model) &&
        captured.error == null &&
        captured.job?['id'] == id)
      setState(() => _jobDetail = true);
  }

  Future<void> _refreshSection() => switch (_section) {
    'profiles' => _present(AutomationUiPhase.profiles, model.refreshProfiles),
    'grants' => _present(AutomationUiPhase.grants, model.refreshGrants),
    'authorities' => _present(
      AutomationUiPhase.authorities,
      model.refreshAuthorities,
    ),
    _ => _present(AutomationUiPhase.jobs, model.refreshJobs),
  };

  Future<void> _openPlan(String id) async {
    final captured = model;
    await _present(AutomationUiPhase.plan, () => captured.loadPlan(id));
    if (mounted &&
        identical(captured, model) &&
        captured.error == null &&
        captured.plan?['id'] == id)
      setState(() {
        _closedPlanId = null;
        _section = 'plans';
      });
  }

  Future<void> _editPlanSource(Map<String, Object?> plan) async {
    final captured = model,
        revision = captured.revision,
        profile = captured.profile;
    if (!captured.canMutate ||
        revision == null ||
        profile == null ||
        profile.archived ||
        profile.id != plan['profileId'] ||
        profile.workspaceId != plan['workspaceId'] ||
        widget.serverId != plan['serverId'] ||
        revision['profileId'] != plan['profileId'] ||
        revision['revision'] != plan['profileRevision'] ||
        revision['digest'] != plan['profileDigest'])
      return;
    final parameters =
        (revision['body'] as Map<String, Object?>)['parameters']
            as Map<String, Object?>;
    if (parameters.isEmpty) {
      await _editProfile(existing: profile);
      return;
    }
    final stamp = pretty(revision), targetId = widget.serverId;
    await _jsonEditor(
      'Параметры плана',
      Map<String, Object?>.of(plan['exactParams'] as Map<String, Object?>),
      captured.createPlan,
      phase: AutomationUiPhase.createPlan,
      parameterDefinitions: parameters,
      target:
          'Ansible-профиль: ${profile.name} · версия ${revision['revision']}.',
      targetServerIds: [if (targetId != null) targetId],
      contextDetails: {
        'profileId': plan['profileId'],
        'revision': plan['profileRevision'],
        'bodyDigest': plan['profileDigest'],
        'serverId': targetId,
      },
      purpose: 'Изменение создаст новый план. Прежний заблокированный или устаревший план останется неизменным.',
      contextCurrent: () =>
          identical(captured, model) &&
          widget.serverId == targetId &&
          pretty(captured.revision) == stamp,
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
    var jobsTitle = 'Задания';
    if (_jobDetail && job != null)
      jobsTitle = job['state'] == 'unknown'
          ? 'Неизвестный исход задания'
          : job['cancelRequested'] == true
          ? 'Остановка задания'
          : 'Ход задания';
    final firstJob = model.jobs.firstOrNull?['job'];
    final openJobId =
        job?['id'] ??
        (firstJob is Map<String, Object?> ? firstJob['id'] : null);
    final screenId = switch (_section) {
      'catalog' => _recipeDetail ? '17-recipe-detail' : '16-install-catalog',
      'profiles' =>
        _profileDetail ? '34-profile-revisions' : '32-automation-profiles',
      'grants' =>
        _configurationDetail ? '38-mcp-client-config' : '36-ai-grants',
      'jobs' =>
        !_jobDetail
            ? '27-job-list'
            : jobsTitle == 'Неизвестный исход задания'
            ? '29-job-unknown'
            : jobsTitle == 'Остановка задания'
            ? '30-job-cancel'
            : '28-job-detail',
      'plans' =>
        expired || invalidPlan
            ? '94-plan-invalidated'
            : plan?['status'] == 'blocked'
            ? '93-protected-effect-blocked'
            : widget.installationCatalog && !_planReviewed
            ? '18-install-preflight'
            : '19-plan-approval',
      _ => '39-delegations',
    };
    final chosenGrant = model.grants
        .where(
          (row) =>
              row['id'] ==
              (_selectedGrantId ?? model.grants.firstOrNull?['id']),
        )
        .firstOrNull;
    return AbsorbPointer(
      absorbing: false,
      child: AutomationPageFrame(
        screenId: screenId,
        section: _section,
        catalog: widget.installationCatalog,
        onSelected: (next) => setState(() => _section = next),
        actions: [
          ...automationPageActions(
            section: _section,
            availability: actions,
            onRefresh: () => _refreshSection().ignore(),
            onCreate: () => _section == 'grants'
                ? _grantEditor().ignore()
                : _editProfile().ignore(),
            onLoadRecipes: () => _loadRecipes().ignore(),
            onSelectRecipe:
                model.catalog == null ||
                    model.catalog!['recipes'] is! List ||
                    (model.catalog!['recipes'] as List).isEmpty
                ? null
                : () => _recipesKey.currentState?.selectFirst(),
            onEdit: chosenGrant == null || chosenGrant['revokedAt'] != null
                ? null
                : () => _grantEditor(existing: chosenGrant).ignore(),
            onOpenJob: openJobId is String
                ? () => _selectJob(openJobId).ignore()
                : null,
            detail: _section == 'jobs'
                ? _jobDetail
                : _section == 'profiles'
                ? _profileDetail
                : _section == 'catalog'
                ? _recipeDetail
                : _section == 'grants'
                ? _configurationDetail
                : false,
          ),
          if (_section == 'jobs' && !_jobDetail) ...widget.workspaceActions,
        ],
        title: switch (_section) {
          'catalog' => _recipeDetail ? 'Рецепт установки' : 'Каталог установки',
          'jobs' => jobsTitle,
          'grants' =>
            _configurationDetail ? 'Подключение MCP-клиента' : 'Доступ ИИ',
          'authorities' => 'Согласования и делегирование',
          'plans' =>
            plan == null || plan['id'] == _closedPlanId
                ? 'Планы'
                : expired || invalidPlan
                ? 'План требует новой проверки'
                : plan['status'] == 'blocked'
                ? 'План заблокирован'
                : widget.installationCatalog && !_planReviewed
                ? 'Проверка готовности к установке'
                : 'Подтверждение плана',
          _ =>
            _profileDetail ? 'Версии и сравнение профиля' : 'Ansible-профили',
        },
        description: automationPageDescription(screenId),
        contextBar:
            widget.contextBarBuilder?.call(
              model.catalog?['environment'] as String?,
            ) ??
            widget.contextBar,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            if (_section == 'catalog' && model.catalog != null)
              AutomationRecipesSection(
                key: _recipesKey,
                catalog: model.catalog!,
                serverId: widget.serverId,
                serverProfiles: widget.serverProfiles,
                onSelectionChanged: (value) =>
                    setState(() => _recipeDetail = value),
                canMutate: actions.mutate,
                onCreatePlan: (digest) => _createRecipePlan(digest).ignore(),
              ),
            if (_section == 'profiles' && !_profileDetail)
              AutomationProfilesSection(
                onSelectVersion: selected != null && revision != null
                    ? () => _selectVersion().ignore()
                    : null,
                profiles: model.profiles,
                loaded: model.profilesLoaded,
                hasMore: model.profilesCursor != null,
                selectedId: selected?.id,
                actions: actions,
                onSelect: (id) => _selectAutomationProfile(id).ignore(),
                onMore: () => _present(
                  AutomationUiPhase.profiles,
                  () => model.refreshProfiles(more: true),
                ).ignore(),
              ),
            if (_section == 'grants')
              AutomationGrantsSection(
                onSelectionChanged: (row) =>
                    setState(() => _selectedGrantId = row['id'] as String),
                onConfigurationChanged: (value) =>
                    setState(() => _configurationDetail = value),
                showHeaderActions: false,
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
                onConfigure: (id) => _configureGrant(id).ignore(),
                onEdit: (row) => _grantEditor(existing: row).ignore(),
                onRevoke: (row) => _revokeGrant(row).ignore(),
                onCopyConfiguration: () => Clipboard.setData(
                  ClipboardData(text: pretty(model.launchConfiguration)),
                ).ignore(),
              ),
            if (_section == 'profiles' && _profileDetail)
              TextButton(
                clipBehavior: Clip.none,
                onPressed: () => setState(() => _profileDetail = false),
                child: const Text('К профилям'),
              ),
            if (_section == 'profiles' &&
                _profileDetail &&
                selected != null &&
                revision != null)
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
                    parameterDefinitions: parameters,
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
            if (_section == 'plans' &&
                plan != null &&
                plan['id'] != _closedPlanId)
              AutomationPlanSection(
                plan: plan,
                showPreflight: widget.installationCatalog,
                showRefresh: false,
                allowApply: model.approvals.any(
                  (row) =>
                      row['planId'] == plan['id'] && row['state'] == 'approved',
                ),
                onViewPlan: () => setState(() => _planReviewed = true),
                onShowAuthorities: () =>
                    setState(() => _section = 'authorities'),
                currentServerId: widget.serverId,
                sourceRevision: model.revision,
                onEditSource: () => _editPlanSource(plan).ignore(),
                onClose: () => setState(() {
                  _closedPlanId = plan['id'] as String;
                  _section = widget.installationCatalog ? 'catalog' : 'jobs';
                }),
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
            if (_section == 'plans' &&
                (plan == null || plan['id'] == _closedPlanId))
              const DeckEmptyState(
                title: 'Нет открытого плана',
                description:
                    'Выберите рецепт или версию профиля и создайте план.',
                icon: 'jobs',
              ),
            if (widget.serverId != null && _section == 'jobs') ...[
              AutomationJobsSection(
                scopeSelector: widget.contextBar,
                showHeaderActions: false,
                onDetailChanged: (value) => setState(() => _jobDetail = value),
                serverId: widget.serverId,
                serverProfiles: widget.serverProfiles,
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
                onSelect: (id) => _selectJob(id).ignore(),
                onMore: () => _present(
                  AutomationUiPhase.jobs,
                  () => model.refreshJobs(more: true),
                ).ignore(),
                onShowPlan: () =>
                    _openPlan(job!['immutablePlanId'] as String).ignore(),
                onCancel: () => _present(
                  AutomationUiPhase.cancelJob,
                  () => model.jobAction(job!['id'] as String, reconcile: false),
                ).ignore(),
                onReconcile: () => _present(
                  AutomationUiPhase.reconcile,
                  () => model.jobAction(job!['id'] as String, reconcile: true),
                ).ignore(),
              ),
            ],
            if (_section == 'authorities')
              AutomationAuthoritiesSection(
                approvals: model.approvals,
                delegations: model.delegations,
                loaded: model.authoritiesLoaded,
                hasMoreApprovals: model.approvalsNext != null,
                hasMoreDelegations: model.delegationsNext != null,
                actions: actions,
                onOpenPlan: (id) => _openPlan(id).ignore(),
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
        ),
      ),
    );
  }
}
