import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:serverdeck_protocol/automation/profile_body.dart';
import 'package:serverdeck_protocol/automation/profile_records.dart';
import 'package:serverdeck_protocol/automation/values.dart';
import 'package:serverdeck_protocol/codec.dart';

/// Display vocabulary only. Native admission and outcome remain owner decisions.
String automationMessage(String code) => switch (code) {
  'TRUST_REQUIRED' => 'Сначала подтвердите SSH-ключ сервера.',
  'TRUST_CHANGED' =>
    'Доверие серверу изменилось. Проверьте SSH-ключ и создайте новый план.',
  'EXECUTOR_UNAVAILABLE' => 'Executor сервера недоступен.',
  'APPROVAL_REQUIRED' => 'Для запуска подтвердите этот план.',
  'PLAN_STALE' => 'Состояние сервера изменилось. Создайте новый план.',
  'PLAN_EXPIRED' => 'Срок плана истёк. Создайте новый план.',
  'REVISION_CONFLICT' => 'Данные изменились. Перечитайте текущее состояние перед новым подтверждением.',
  'FORBIDDEN' => 'Недостаточно прав для операции.',
  'UNAUTHORIZED' => 'Не удалось подтвердить доступ к локальной службе.',
  'UNSUPPORTED' => 'Операция не поддерживается в текущем окружении.',
  'VALIDATION' => 'Проверьте входные данные и ограничения операции.',
  'NOT_READY' => 'Локальное пространство ещё не готово.',
  'STORAGE_BLOCKED' =>
    'Защищённое локальное хранилище недоступно. Проверьте его состояние.',
  'SERVICE_UNAVAILABLE' =>
    'Локальная служба недоступна. Проверьте её состояние.',
  'DISCONNECTED' || 'CONNECTION_FAILED' => 'Подключение к серверу не установлено. Проверьте доступ и доверие в разделе «Серверы».',
  'AUTHENTICATION_FAILED' =>
    'Сервер отклонил параметры доступа. Проверьте профиль в разделе «Серверы».',
  'UNKNOWN_OUTCOME' => 'Исход не подтверждён. Уточните результат задания.',
  'RESOURCE_LIMIT' || 'HOST_BUSY' => 'Операция ограничена текущими ресурсами. Дождитесь завершения действующих операций.',
  'RUNTIME_INCOMPATIBLE' => 'Среда исполнения несовместима с этим планом.',
  'CHECK_FAILED' =>
    'Проверка не пройдена. Изучите результат и проверки задания.',
  'CANCELLED' => 'Ожидание результата остановлено.',
  'TIMEOUT' => 'Ответ локальной службы не получен вовремя.',
  _ => 'Не удалось выполнить запрос. Проверьте состояние локальной службы.',
};

/// Result captured at the completion of one durable owner callback. Later reads
/// have their own error and cannot reinterpret this retained write.
class AutomationWriteOutcome {
  const AutomationWriteOutcome({required this.label, required this.errorCode});
  final String label;
  final String? errorCode;
  bool get unconfirmed => const {
    'TIMEOUT',
    'SERVICE_UNAVAILABLE',
    'CANCELLED',
    'DISCONNECTED',
    'UNKNOWN_OUTCOME',
  }.contains(errorCode);
}

class AutomationUiResult {
  const AutomationUiResult({this.errorCode, this.pendingLabel});
  final String? errorCode, pendingLabel;
}

enum AutomationUiPhase {
  initialize('Проверка профилей и доступа'),
  profiles('Профили'),
  version('Версия профиля'),
  validate('Проверка профиля'),
  compare('Сравнение версий'),
  saveProfile('Сохранение профиля'),
  archive('Архивирование профиля'),
  catalog('Подключение и загрузка рецептов'),
  recipePlan('План установки'),
  createPlan('Создание плана'),
  apply('Запуск плана'),
  plan('Чтение плана'),
  approve('Подтверждение плана'),
  deny('Отклонение плана'),
  jobs('Задания'),
  job('Состояние задания'),
  cancelJob('Остановка задания'),
  reconcile('Уточнение результата'),
  authorities('Разрешения'),
  grants('Доступ ИИ'),
  saveGrant('Подключение ИИ'),
  replaceGrant('Изменение доступа ИИ'),
  revokeGrant('Отзыв доступа ИИ'),
  configuration('Конфигурация MCP'),
  delegate('Делегирование профиля'),
  revokeDelegation('Отзыв делегирования'),
  retry('Повтор сохранённого запроса');

  const AutomationUiPhase(this.label);
  final String label;

  bool get durable => const {
    saveProfile,
    archive,
    recipePlan,
    createPlan,
    apply,
    approve,
    deny,
    cancelJob,
    reconcile,
    saveGrant,
    replaceGrant,
    revokeGrant,
    delegate,
    revokeDelegation,
    retry,
  }.contains(this);
}

Map<String, Object?> parseAutomationDraft(String source) =>
    StrictCodec().decode(utf8.encode(source), maxBytes: 256 * 1024);

String automationDraftInputError({bool profileBody = false}) => profileBody
    ? 'Проверьте формат профиля и допустимые значения'
    : 'Проверьте JSON и типы значений';

class AutomationDraftContextChanged implements Exception {
  const AutomationDraftContextChanged();
}

class AutomationDraftTargetUnavailable implements Exception {
  const AutomationDraftTargetUnavailable();
}

/// Form state only: the route owns its exact text and the borrowed owner owns
/// admission, payload, request identity, execution and recovery.
class AutomationJsonDraftSubmission extends ChangeNotifier {
  AutomationJsonDraftSubmission(this.phase);
  final AutomationUiPhase phase;
  bool saving = false, requestRetained = false;
  bool _disposed = false, _retired = false;
  Object? _token;
  String? error, errorCode;
  bool get retired => _retired;
  AutomationWriteOutcome? get writeOutcome => requestRetained
      ? AutomationWriteOutcome(label: phase.label, errorCode: errorCode)
      : null;

  Future<void> submit({
    required String source,
    required bool Function() current,
    required bool Function() completionCurrent,
    required bool Function() canSubmit,
    bool Function(Map<String, Object?>)? draftCurrent,
    required bool Function(Map<String, Object?>) targetsAvailable,
    required Future<void> Function(Map<String, Object?>, VoidCallback) submit,
    required AutomationUiResult? Function() result,
    required VoidCallback close,
  }) {
    if (_disposed ||
        _retired ||
        saving ||
        requestRetained ||
        !current() ||
        !canSubmit())
      return Future<void>.value();
    final token = Object();
    _token = token;
    saving = true;
    error = errorCode = null;
    var admitted = false;
    try {
      final work = submitAutomationDraft(
        source: source,
        current: (value) => current() && (draftCurrent?.call(value) ?? true),
        targetsAvailable: targetsAvailable,
        submit: (value) => submit(value, () => admitted = true),
      );
      if (!admitted) {
        saving = false;
        _token = null;
        if (!_disposed) notifyListeners();
        return work;
      }
      if (!_disposed) notifyListeners();
      return _complete(
        work,
        token: token,
        current: current,
        completionCurrent: completionCurrent,
        result: result,
        close: close,
      );
    } on AutomationDraftContextChanged {
      _retired = true;
    } on AutomationDraftTargetUnavailable {
      error = 'Не удалось проверить целевые серверы. Проверьте локальные профили и идентификаторы.';
    } catch (_) {
      error = automationDraftInputError();
    }
    saving = false;
    _token = null;
    if (!_disposed) notifyListeners();
    return Future<void>.value();
  }

  Future<void> _complete(
    Future<void> work, {
    required Object token,
    required bool Function() current,
    required bool Function() completionCurrent,
    required AutomationUiResult? Function() result,
    required VoidCallback close,
  }) {
    void completed({String? failure}) {
      if (_disposed || !identical(_token, token) || !completionCurrent())
        return;
      final snapshot = result();
      if (snapshot == null) return;
      final code = failure ?? snapshot.errorCode;
      final retained = phase.durable && snapshot.pendingLabel != null;
      // Own successful readback can change the reviewed DTO. Closing this
      // completed form gives no new consent and requires the live route owner.
      if (code == null && !retained) {
        close();
        return;
      }
      if (_retired || !current()) return;
      requestRetained = retained;
      errorCode = code;
      error = code == null ? null : automationMessage(code);
    }

    return work
        .then(
          (_) => completed(),
          onError: (Object _) {
            completed(failure: 'SERVICE_UNAVAILABLE');
          },
        )
        .whenComplete(() {
          if (_disposed || !identical(_token, token)) return;
          _token = null;
          saving = false;
          if (completionCurrent()) notifyListeners();
        });
  }

  Future<void> retrySaved({
    required bool Function() current,
    required bool Function() completionCurrent,
    required bool Function() canRetry,
    required Future<void> Function(VoidCallback) retry,
    required AutomationUiResult? Function() result,
    required VoidCallback close,
  }) {
    if (_disposed ||
        _retired ||
        saving ||
        !requestRetained ||
        !current() ||
        !canRetry())
      return Future<void>.value();
    final token = Object();
    _token = token;
    saving = true;
    var admitted = false;
    try {
      final work = retry(() => admitted = true);
      if (!admitted) {
        saving = false;
        _token = null;
        return work;
      }
      error = errorCode = null;
      notifyListeners();
      return _complete(
        work,
        token: token,
        current: current,
        completionCurrent: completionCurrent,
        result: result,
        close: close,
      );
    } catch (_) {
      saving = false;
      _token = null;
      error = automationMessage('SERVICE_UNAVAILABLE');
      notifyListeners();
      return Future<void>.value();
    }
  }

  void dismissSaved({
    required bool Function() completionCurrent,
    required VoidCallback dismiss,
    required String? Function() pendingLabel,
  }) {
    if (_disposed || saving || !requestRetained || !completionCurrent()) return;
    dismiss();
    if (pendingLabel() == null) {
      requestRetained = false;
      error = errorCode = null;
      notifyListeners();
    }
  }

  void observe({required bool current, required String? pendingLabel}) {
    if (_disposed) return;
    if (!current) _retired = true;
    if (!saving && pendingLabel == null) requestRetained = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _token = null;
    super.dispose();
  }
}

/// Existing presentation pre-dispatch order, shared by the live editor routes.
/// The borrowed callback still owns revisions, IDs, authority and durable work.
Future<void> submitAutomationDraft({
  required String source,
  required bool Function(Map<String, Object?> value) current,
  required bool Function(Map<String, Object?> value) targetsAvailable,
  required Future<void> Function(Map<String, Object?> value) submit,
  bool profileBody = false,
}) {
  final value = parseAutomationDraft(source);
  if (!current(value)) throw const AutomationDraftContextChanged();
  if (!targetsAvailable(value)) throw const AutomationDraftTargetUnavailable();
  if (profileBody) AutomationBody.fromJson(value);
  return submit(value);
}

/// Shared live profile-editor submission boundary. The owner still creates the
/// request and performs all authoritative validation/admission.
class AutomationProfileMetadataError implements Exception {
  const AutomationProfileMetadataError({this.nameError, this.descriptionError});
  final String? nameError, descriptionError;
}

Future<void> submitAutomationProfileDraft({
  required String name,
  required String description,
  required String source,
  required bool Function() current,
  required Future<void> Function(
    String name,
    String description,
    Map<String, Object?> body,
  )
  submit,
}) {
  String? nameError, descriptionError;
  try {
    automationText(name, min: 1, max: 100);
  } on FormatException {
    nameError = 'Проверьте название: от 1 до 100 допустимых символов Unicode, без переводов строк и управляющих знаков.';
  }
  try {
    automationText(description, max: 2000, multiline: true);
  } on FormatException {
    descriptionError = 'Проверьте описание: до 2000 допустимых символов Unicode. Разрешены перенос строки и табуляция.';
  }
  if (nameError != null || descriptionError != null) {
    throw AutomationProfileMetadataError(
      nameError: nameError,
      descriptionError: descriptionError,
    );
  }
  return submitAutomationDraft(
    source: source,
    current: (_) => current(),
    targetsAvailable: (_) => true,
    profileBody: true,
    submit: (body) => submit(name, description, body),
  );
}

/// An existing immutable revision reviewed in this dialog. The owner still
/// derives request identity and performs its expectedRevision check.
class AutomationProfileBasis {
  const AutomationProfileBasis({
    required this.profile,
    required this.revision,
    required this.digest,
  });
  final AutomationProfileRecord profile;
  final int revision;
  final String digest;
  static AutomationProfileBasis? fromOwner(
    AutomationProfileRecord? profile,
    Map<String, Object?>? version, {
    bool currentHead = false,
  }) {
    if (profile == null ||
        version == null ||
        version['profileId'] != profile.id ||
        version['workspaceId'] != profile.workspaceId ||
        version['revision'] is! int ||
        version['digest'] is! String ||
        currentHead &&
            (profile.archived || version['revision'] != profile.headRevision))
      return null;
    return AutomationProfileBasis(
      profile: profile,
      revision: version['revision'] as int,
      digest: version['digest'] as String,
    );
  }

  bool matches(
    AutomationProfileRecord? current,
    Map<String, Object?>? version,
  ) =>
      current != null &&
      version?['profileId'] == profile.id &&
      version?['workspaceId'] == profile.workspaceId &&
      jsonEncode(current.toJson()) == jsonEncode(profile.toJson()) &&
      version?['revision'] == revision &&
      version?['digest'] == digest;
}

/// Form-only state; all controllers remain owned by the actual dialog route.
class AutomationProfileDraftSubmission extends ChangeNotifier {
  AutomationProfileDraftSubmission({this.initialBasis});
  final AutomationProfileBasis? initialBasis;
  AutomationProfileBasis? _acceptedBasis, _candidateBasis;
  AutomationProfileBasis? get acceptedBasis => _acceptedBasis;
  AutomationProfileBasis? get candidateBasis => _candidateBasis;
  AutomationProfileBasis? get currentBasis => _acceptedBasis ?? initialBasis;
  bool _basisReviewAllowed = false, _basisRequired = false;
  bool _acceptedRetired = false, _contextRetired = false;
  bool get requiresNewBasis => _basisRequired || _acceptedRetired;
  bool get canReadBasis =>
      _basisReviewAllowed && initialBasis != null && !_contextRetired;
  bool get contextRetired => _contextRetired;
  bool basisLoading = false;
  Object? _basisToken;
  String? nameError, descriptionError, error, saveError;
  String? _saveErrorCode;
  bool get saveUnconfirmed => AutomationWriteOutcome(
    label: AutomationUiPhase.saveProfile.label,
    errorCode: _saveErrorCode,
  ).unconfirmed;
  bool saving = false, _disposed = false;

  Future<void> save({
    required String name,
    required String description,
    required String source,
    required bool Function() current,
    bool Function()? canSubmit,
    bool Function(AutomationProfileBasis)? basisCurrent,
    required Future<void> Function(
      String name,
      String description,
      Map<String, Object?> body,
    )
    submit,
    required String? Function() resultError,
    String? Function()? pendingLabel,
    required VoidCallback close,
  }) {
    if (_disposed ||
        _contextRetired ||
        saving ||
        requiresNewBasis ||
        !current() ||
        !(canSubmit?.call() ?? true) ||
        currentBasis != null && !(basisCurrent?.call(currentBasis!) ?? true))
      return Future<void>.value();
    nameError = descriptionError = error = saveError = _saveErrorCode = null;
    try {
      final work = submitAutomationProfileDraft(
        name: name,
        description: description,
        source: source,
        current: current,
        submit: submit,
      );
      return _completeWrite(
        work,
        current: current,
        resultError: resultError,
        pendingLabel: pendingLabel,
        close: close,
      );
    } on AutomationProfileMetadataError catch (failure) {
      nameError = failure.nameError;
      descriptionError = failure.descriptionError;
      if (!_disposed) notifyListeners();
      return Future<void>.value();
    } on FormatException {
      error = automationDraftInputError(profileBody: true);
      if (!_disposed) notifyListeners();
      return Future<void>.value();
    }
  }

  Future<void> _completeWrite(
    Future<void> work, {
    required bool Function() current,
    required String? Function() resultError,
    String? Function()? pendingLabel,
    required VoidCallback close,
  }) {
    saving = true;
    _basisReviewAllowed = _basisRequired = false;
    _candidateBasis = null;
    _basisToken = null;
    if (!_disposed) notifyListeners();
    return work
        .then((_) {
          if (_disposed || _contextRetired || !current()) return;
          final code = resultError();
          _saveErrorCode = code;
          saveError = code == null ? null : automationMessage(code);
          _basisReviewAllowed = _basisRequired =
              code == 'REVISION_CONFLICT' && initialBasis != null;
          if (code == null && pendingLabel?.call() == null) close();
        })
        .whenComplete(() {
          saving = false;
          if (!_disposed) notifyListeners();
        });
  }

  Future<void> retrySaved({
    required Future<void> Function() retry,
    required bool Function() canRetry,
    required bool Function() current,
    required String? Function() resultError,
    required String? Function() pendingLabel,
    required VoidCallback close,
  }) {
    if (_disposed || _contextRetired || saving || !current() || !canRetry())
      return Future<void>.value();
    return _completeWrite(
      retry(),
      current: current,
      resultError: resultError,
      pendingLabel: pendingLabel,
      close: close,
    );
  }

  void dismissSaved({
    required VoidCallback dismiss,
    required String? Function() pendingLabel,
  }) {
    if (_disposed || _contextRetired || saving) return;
    dismiss();
    if (pendingLabel() == null) {
      if (!_basisRequired) {
        saveError = _saveErrorCode = null;
      }
      notifyListeners();
    }
  }

  Future<void> readBasis({
    required Future<AutomationProfileBasis?> Function() read,
    required bool Function() current,
    required bool Function() canRead,
    required String? Function() pendingLabel,
  }) async {
    if (_disposed ||
        !canReadBasis ||
        saving ||
        basisLoading ||
        pendingLabel() != null ||
        !current() ||
        !canRead())
      return;
    final token = Object();
    _basisToken = token;
    _candidateBasis = null;
    basisLoading = true;
    notifyListeners();
    try {
      final candidate = await read();
      if (_disposed ||
          _contextRetired ||
          !identical(token, _basisToken) ||
          !current() ||
          !canReadBasis)
        return;
      final original = initialBasis!.profile;
      if (candidate != null &&
          !candidate.profile.archived &&
          candidate.profile.id == original.id &&
          candidate.profile.workspaceId == original.workspaceId &&
          candidate.revision == candidate.profile.headRevision)
        _candidateBasis = candidate;
    } finally {
      if (!_disposed && identical(token, _basisToken)) {
        basisLoading = false;
        _basisToken = null;
        notifyListeners();
      }
    }
  }

  bool acceptBasis({
    required bool Function() current,
    required bool Function() canAccept,
    required bool Function(AutomationProfileBasis) unchanged,
  }) {
    final candidate = _candidateBasis;
    if (_disposed ||
        _contextRetired ||
        saving ||
        basisLoading ||
        !canReadBasis ||
        candidate == null ||
        !current() ||
        !canAccept() ||
        !unchanged(candidate))
      return false;
    _acceptedBasis = candidate;
    _candidateBasis = null;
    _basisRequired = _acceptedRetired = false;
    saveError = _saveErrorCode = null;
    notifyListeners();
    return true;
  }

  /// Invoked by the modal's synchronous existing context observer. A changed
  /// candidate/accepted head cannot regain old consent by changing back.
  void observeBasis({
    required bool current,
    required bool Function(AutomationProfileBasis) unchanged,
  }) {
    if (_disposed) return;
    if (!current) {
      _contextRetired = true;
      _basisToken = null;
      _candidateBasis = null;
    }
    if (_candidateBasis != null && !unchanged(_candidateBasis!))
      _candidateBasis = null;
    if (!saving && _acceptedBasis != null && !unchanged(_acceptedBasis!))
      _acceptedRetired = true;
  }

  @override
  void dispose() {
    _disposed = true;
    _basisToken = null;
    _candidateBasis = null;
    super.dispose();
  }
}

/// A label for one existing UI callback. It never starts/retries/cancels work on
/// its own, gates admission, or exposes a retained native action.
class AutomationUiOperation extends ChangeNotifier {
  String? _label;
  Object? _token;
  bool _disposed = false;
  String? get label => _label;
  AutomationWriteOutcome? _writeOutcome;
  String? _readErrorCode;
  AutomationWriteOutcome? get writeOutcome => _writeOutcome;
  String? get readErrorCode => _readErrorCode;

  Future<T> run<T>(
    AutomationUiPhase phase,
    Future<T> Function() action, {
    AutomationUiResult Function()? result,
    bool Function()? admitted,
  }) {
    final token = Object();
    final previousWrite = _writeOutcome, previousReadError = _readErrorCode;
    if (!_disposed) {
      _token = token;
      _label = phase.label;
      _readErrorCode = null;
      if (phase.durable && phase != AutomationUiPhase.retry) {
        _writeOutcome = null;
      }
      notifyListeners();
    }
    void finished({bool capture = true}) {
      if (!_disposed && identical(token, _token)) {
        final completed = capture ? result?.call() : null;
        if (!capture) {
          _writeOutcome = previousWrite;
          _readErrorCode = previousReadError;
        }
        if (completed != null) {
          if (phase.durable) {
            _writeOutcome = completed.pendingLabel == null
                ? null
                : AutomationWriteOutcome(
                    label: completed.pendingLabel!,
                    errorCode: completed.errorCode,
                  );
          } else {
            _readErrorCode = completed.errorCode;
            if (completed.pendingLabel == null) _writeOutcome = null;
          }
        }
        _label = null;
        _token = null;
        notifyListeners();
      }
    }

    try {
      final work = action();
      if (admitted?.call() == false) {
        finished(capture: false);
        return work;
      }
      return work.whenComplete(finished);
    } catch (_) {
      finished(capture: false);
      rethrow;
    }
  }

  /// Owner background reads/closure may notify outside a UI callback. They may
  /// clear a retired request or update a read error, never assign a write result.
  void observeOwner(AutomationUiResult result) {
    if (_disposed || _token != null) return;
    if (result.pendingLabel == null) _writeOutcome = null;
    _readErrorCode = result.errorCode;
  }

  void dismiss(VoidCallback action, AutomationUiResult Function() result) {
    action();
    if (result().pendingLabel == null) reset();
  }

  void reset() {
    if (_disposed) return;
    _token = null;
    _label = null;
    _writeOutcome = null;
    _readErrorCode = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _token = null;
    _label = null;
    super.dispose();
  }
}

bool automationPlanExpired(Map<String, Object?> plan, {DateTime? now}) {
  return automationDeadlineExpired(plan['expiresAt'], now: now);
}

bool automationDeadlineExpired(Object? expiresAt, {DateTime? now}) {
  final deadline = DateTime.tryParse('$expiresAt');
  return deadline == null || !deadline.isAfter(now ?? DateTime.now());
}

bool automationGrantCurrent(Map<String, Object?> row, {DateTime? now}) {
  final basis = now ?? DateTime.now().toUtc();
  return row['revokedAt'] == null &&
      !DateTime.parse(row['issuedAt'] as String).isAfter(basis) &&
      DateTime.parse(row['expiresAt'] as String).isAfter(basis);
}
