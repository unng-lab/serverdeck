import 'dart:io';

import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' hide ReadinessView;
import 'package:serverdeck_protocol/profile_validation.dart';
import 'package:serverdeck_windows/profile_input.dart';

import '../bootstrap/local_api_client.dart';
import '../shell/readiness_view.dart';
import '../shell/error_view.dart';
import '../shell/form_keyboard.dart';
import '../theme/brand_tokens.dart';
import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';
import '../ui/deck_components.dart';
import '../ui/deck_control_target.dart';
import '../ui/deck_input_border.dart';
import 'credential_input.dart';
import 'mutation_controller.dart';
import 'mutation_status.dart';
import 'profile_controller.dart';
import 'profile_presentation.dart';

Map<String, Object?> buildProfileInput({
  required String name,
  required String address,
  required String port,
  required String user,
  required String tags,
}) {
  final normalized = normalizeText(address, trim: true);
  final target = InternetAddress.tryParse(normalized) == null
      ? domainToAscii(normalized)
      : normalized;
  return normalizeProfileFields({
    'name': name,
    'address': target,
    'port': int.tryParse(port.trim()),
    'sshUser': user,
    'tags': tags.trim().isEmpty ? <String>[] : tags.split(RegExp(r'\r?\n')),
  });
}

class ProfileForm extends StatefulWidget {
  const ProfileForm({
    super.key,
    required this.model,
    this.initial,
    this.asPage = false,
    this.onClose,
    this.credentialOnly = false,
  });
  final ProfileController model;
  final ProfileView? initial;
  final bool asPage, credentialOnly;
  final VoidCallback? onClose;
  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  final _form = GlobalKey<FormState>();
  final _credential = GlobalKey<CredentialInputState>();
  final _name = TextEditingController(),
      _address = TextEditingController(),
      _port = TextEditingController(),
      _user = TextEditingController(),
      _tags = TextEditingController();
  late final MutationController mutation;
  late final String id;
  String? revision, inputError;
  ProfileView? _targetProfile;
  bool _reloading = false;
  bool _readingError = false;

  @override
  void initState() {
    super.initState();
    id = widget.initial?.id ?? newRequestId();
    _populate(widget.initial);
    mutation = MutationController(model: widget.model)..addListener(_outcome);
  }

  void _populate(ProfileView? profile) {
    _targetProfile = profile;
    _name.text = profile?.name ?? '';
    _address.text = profile?.address ?? '';
    _port.text = '${profile?.port ?? 22}';
    _user.text = profile?.sshUser ?? '';
    _tags.text = profile?.tags.join('\n') ?? '';
    revision = profile?.revision;
  }

  void _outcome() {
    if (mutation.state == MutationPresentation.succeeded)
      _credential.currentState?.clear();
  }

  Future<void> _save() async {
    if (_reloading ||
        _readingError ||
        widget.model.bootstrap.state != ReadinessState.ready ||
        mutation.state != MutationPresentation.idle ||
        !widget.model.loaded ||
        _credential.currentState?.picking == true)
      return;
    if (!(_form.currentState?.validate() ?? false)) return;
    try {
      final fields = buildProfileInput(
        name: _name.text,
        address: _address.text,
        port: _port.text,
        user: _user.text,
        tags: _tags.text,
      );
      fields['credential'] = _credential.currentState!.action();
      fields['profileId'] = id;
      if (revision != null) fields['expectedRevision'] = revision;
      setState(() => inputError = null);
      await mutation.submit(
        revision == null ? ApiMethod.profilesCreate : ApiMethod.profilesUpdate,
        fields,
      );
    } on Object {
      if (mounted)
        setState(
          () => inputError = 'Проверьте поля профиля и введённый секрет',
        );
    }
  }

  Future<void> _reload() async {
    if (_reloading || _readingError || mutation.busy) return;
    setState(() => _reloading = true);
    await widget.model.refresh();
    if (!mounted) return;
    ProfileView? current;
    for (final profile in widget.model.profiles) {
      if (profile.id == id) current = profile;
    }
    setState(() {
      _reloading = false;
      if (!widget.model.loaded) {
        inputError =
            'Не удалось перечитать профиль; введённые данные сохранены';
      } else if (current == null) {
        inputError = 'Профиль удалён другим окном. Закройте форму';
      } else {
        _populate(current);
        _credential.currentState?.resetChoice();
        inputError = null;
        mutation.reset();
      }
    });
  }

  Future<void> _readAgain() async {
    if (_readingError ||
        _reloading ||
        (mutation.busy && mutation.state == MutationPresentation.committed))
      return;
    final model = widget.model;
    setState(() => _readingError = true);
    try {
      await model.refresh();
    } finally {
      if (mounted && identical(widget.model, model)) {
        setState(() => _readingError = false);
      }
    }
  }

  void _readCommitted() {
    if (_readingError || _reloading) return;
    mutation.refreshCommitted().ignore();
  }

  void _close() {
    _credential.currentState?.clear();
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  String? _validate(String field, String? value) {
    final values = {
      'name': 'n',
      'address': 'host.example',
      'port': '22',
      'user': 'u',
      'tags': '',
    };
    values[field] = value ?? '';
    try {
      buildProfileInput(
        name: values['name']!,
        address: values['address']!,
        port: values['port']!,
        user: values['user']!,
        tags: values['tags']!,
      );
      return null;
    } on Object {
      return 'Проверьте значение поля';
    }
  }

  Widget _field(
    TextEditingController controller,
    String field,
    String label,
    bool enabled,
  ) => DeckHitOverflow(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Floating InputDecorator labels elide long instructions at200%. Keep
        // the whole label visible and associate it with the same keyed input.
        ExcludeSemantics(
          child: widget.asPage
              ? ProfileFieldLabel(label: label, required: field != 'tags')
              : Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
        SizedBox(height: widget.asPage ? 7 : BrandSpacing.space8),
        DeckControlTarget(
          visibleHeight: widget.asPage && MediaQuery.sizeOf(context).width > 520
              ? 42
              : 44,
          child: Semantics(
            label: label,
            isRequired: field != 'tags',
            child: SubmitOnEnter(
              enabled: enabled && field != 'tags',
              child: TextFormField(
                key: ValueKey('profile-$field'),
                controller: controller,
                enabled: enabled,
                // Keep the canonical opaque body style while the draft is locked.
                style: widget.asPage
                    ? deckFormTextStyle(context)
                    : Theme.of(context).textTheme.bodyLarge,
                autofocus: field == 'name',
                onFieldSubmitted: field == 'tags'
                    ? null
                    : (_) => _save().ignore(),
                decoration: widget.asPage
                    ? deckFormDecoration(context)
                    : const InputDecoration(),
                validator: (value) => _validate(field, value),
                minLines: field == 'tags' && !widget.asPage ? 2 : 1,
                maxLines: field == 'tags' ? 4 : 1,
                textInputAction: field == 'tags'
                    ? TextInputAction.newline
                    : TextInputAction.done,
              ),
            ),
          ),
        ),
        if (widget.asPage && (field == 'address' || field == 'port')) ...[
          const SizedBox(height: 6),
          Text(
            field == 'address'
                ? 'IP-адрес или доменное имя сервера'
                : 'Стандартный порт SSH — 22',
            style: BrandTypography.caption.copyWith(
              height: MediaQuery.sizeOf(context).width <= 520
                  ? 20 / 12
                  : 18 / 12,
              color: Theme.of(context).extension<BrandColors>()!['muted'],
            ),
          ),
        ],
      ],
    ),
  );

  String? get _capturedTargetCaption {
    final target = _targetProfile;
    if (target == null) return null;
    final address = target.address.contains(':')
        ? '[${target.address}]'
        : target.address;
    return '${target.name} · $address:${target.port}';
  }

  Widget _targetField() {
    return DeckHitOverflow(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProfileFieldLabel(label: 'Сервер', required: true),
          const SizedBox(height: 7),
          DeckControlTarget(
            visibleHeight: MediaQuery.sizeOf(context).width <= 520 ? 44 : 42,
            child: Semantics(
              label: 'Сервер',
              readOnly: true,
              child: DeckReadonlyInput(
                key: const ValueKey('profile-target'),
                value: _capturedTargetCaption!,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _profileFields(bool editable) {
    final editPage = widget.asPage && widget.initial != null;
    final access = CredentialInput(
      key: _credential,
      compact: true,
      choiceLabel: editPage ? 'Доступ' : 'Способ доступа',
      readReadyEpoch: () => widget.model.bootstrap.state == ReadinessState.ready
          ? widget.model.bootstrap.readinessEpoch
          : null,
      onSubmit: () => _save().ignore(),
      onPickingChanged: (_) {
        if (mounted) setState(() {});
      },
      creating: revision == null,
      enabled: editable,
    );
    return [
      if (editPage) _targetField(),
      _field(_name, 'name', 'Название', editable),
      _field(
        _address,
        'address',
        widget.asPage ? 'Адрес' : 'Адрес (IP или имя домена)',
        editable,
      ),
      _field(_port, 'port', 'Порт SSH', editable),
      _field(_user, 'user', 'Пользователь SSH', editable),
      if (editPage) access,
      _field(
        _tags,
        'tags',
        widget.asPage ? 'Метки' : 'Метки (одна на строку)',
        editable,
      ),
      if (!editPage) access,
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.model,
      widget.model.bootstrap,
      mutation,
    ]),
    builder: (context, _) {
      final ready = widget.model.bootstrap.state == ReadinessState.ready;
      final editable =
          ready &&
          !_reloading &&
          !_readingError &&
          mutation.state == MutationPresentation.idle;
      final close = OutlinedButton(
        clipBehavior: Clip.none,
        style: OutlinedButton.styleFrom(
          minimumSize: Size(widget.asPage ? 44 : 48, widget.asPage ? 44 : 48),
        ),
        onPressed: _close,
        child: Text(
          !ready || mutation.state != MutationPresentation.idle
              ? 'Закрыть'
              : 'Отмена',
        ),
      );
      final saveLabel = widget.initial == null
          ? 'Сохранить без подключения'
          : widget.credentialOnly
          ? 'Сохранить доступ'
          : 'Сохранить';
      final save =
          editable &&
              widget.model.loaded &&
              _credential.currentState?.picking != true
          ? () => _save().ignore()
          : null;
      final actions = <Widget>[
        if (ready && widget.initial == null)
          const Tooltip(
            message: 'Сохранение с подключением будет доступно в пакете 004. Сейчас сохраните профиль без подключения.',
            child: FilledButton(
              clipBehavior: Clip.none,
              onPressed: null,
              child: Text('Сохранить и подключить'),
            ),
          ),
        if (ready)
          if (widget.credentialOnly)
            OutlinedButton(
              clipBehavior: Clip.none,
              style: OutlinedButton.styleFrom(
                minimumSize: Size(
                  widget.asPage ? 44 : 48,
                  widget.asPage ? 44 : 48,
                ),
              ),
              onPressed: save,
              child: Text(saveLabel),
            )
          else
            FilledButton(
              clipBehavior: Clip.none,
              style: FilledButton.styleFrom(
                minimumSize: Size(
                  widget.asPage ? 44 : 48,
                  widget.asPage ? 44 : 48,
                ),
              ),
              onPressed: save,
              child: Text(saveLabel),
            ),
        close,
      ];
      final form = FormKeyboard(
        onSubmit: () => _save().ignore(),
        onClose: _close,
        child: ProfileEditorFrame(
          asPage: widget.asPage,
          description: widget.credentialOnly
              ? 'Укажите параметры и проверьте их перед продолжением'
              : widget.initial != null
              ? 'Измените параметры сохранённого подключения'
              : 'Укажите адрес и доступ для подключения по SSH',
          title: !ready
              ? 'Локальное пространство недоступно'
              : widget.initial == null
              ? 'Добавление сервера'
              : widget.credentialOnly
              ? 'Настройка доступа'
              : 'Редактирование профиля',
          target:
              ready &&
                  widget.initial != null &&
                  !widget.credentialOnly &&
                  !widget.asPage
              ? DeckKeyValue(
                  label: 'Цель изменения',
                  value: '${_name.text} · ${_address.text}:${_port.text}',
                )
              : null,
          actions: actions,
          footer: widget.credentialOnly && ready
              ? Builder(
                  builder: (_) =>
                      _credential.currentState?.pageActionBar(
                        trailing: actions,
                      ) ??
                      DeckFormActions(children: actions),
                )
              : null,
          // Removing the form disposes its credential editors and retires any
          // native picker. Ordinary theme/size changes keep this same subtree.
          child: !ready
              ? ReadinessView(
                  state: widget.model.bootstrap.state,
                  reason: widget.model.bootstrap.reason,
                  retryInProgress: widget.model.bootstrap.retryInProgress,
                  onRetry: () => widget.model.bootstrap.retry().ignore(),
                )
              : Form(
                  key: _form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Параметры подключения',
                        style: BrandTypography.body.copyWith(
                          height: 22 / 14,
                          fontFamily: BrandAssets.semiboldFamily,
                          fontWeight: BrandTypography.semiboldWeight,
                          fontVariations: BrandTypography.semiboldVariations,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Укажите адрес сервера и способ доступа.',
                        style: BrandTypography.caption.copyWith(
                          height: 20 / 12,
                          color: Theme.of(context)
                              .extension<BrandColors>()!['muted'],
                        ),
                      ),
                      SizedBox(
                        height: MediaQuery.sizeOf(context).width <= 520
                            ? 20
                            : 18,
                      ),
                      if (widget.credentialOnly)
                        CredentialInput(
                          key: _credential,
                          compact: true,
                          inlinePageActions: false,
                          pageTarget:
                              '${_name.text} · ${_address.text.contains(':') ? '[${_address.text}]' : _address.text}:${_port.text}',
                          readReadyEpoch: () =>
                              widget.model.bootstrap.state ==
                                  ReadinessState.ready
                              ? widget.model.bootstrap.readinessEpoch
                              : null,
                          onSubmit: () => _save().ignore(),
                          onPickingChanged: (_) {
                            if (mounted) setState(() {});
                          },
                          onPresentationChanged: () {
                            if (mounted) setState(() {});
                          },
                          creating: revision == null,
                          enabled: editable,
                        )
                      else
                        ProfileFieldGrid(children: _profileFields(editable)),
                      const SizedBox(height: 16),
                      const Text(
                        'Существующий секрет не возвращается в форму. Хранение защищено ОС текущего пользователя.',
                      ),
                      if (widget.initial == null) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Сохранить и подключить: будет доступно в пакете 004. Сохранение без подключения доступно сейчас.',
                        ),
                      ],
                      if (widget.model.error case final code?) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        ReadErrorView(
                          code: code,
                          reading: _readingError || _reloading,
                          pendingLabel: 'Чтение актуального профиля',
                          onReadAgain: () => _readAgain().ignore(),
                          onCheckService: () =>
                              widget.model.bootstrap.retry().ignore(),
                        ),
                      ],
                      if (_readingError && widget.model.error == null) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        const DeckStatus(
                          label: 'Чтение актуального профиля',
                          pending: true,
                        ),
                      ],
                      if (inputError != null) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        DeckNotice(message: inputError!, tone: DeckTone.error),
                      ],
                      if (!widget.asPage &&
                          mutation.state != MutationPresentation.idle) ...[
                        const SizedBox(height: BrandSpacing.space16),
                        MutationStatus(
                          asPage: widget.asPage,
                          controller: mutation,
                          reloading: _reloading,
                          readPending: _readingError,
                          onReadCommitted: _readCommitted,
                          onReload: () => _reload().ignore(),
                        ),
                        const SizedBox(height: BrandSpacing.space12),
                        const Text(
                          'Закрытие формы не отменяет уже отправленное сохранение',
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      );
      return MutationPresentationSwitch(
        enabled: widget.asPage,
        showReview:
            widget.asPage &&
            ready &&
            mutation.state != MutationPresentation.idle,
        form: form,
        review: MutationReviewPage(
          controller: mutation,
          targetCaption: _capturedTargetCaption,
          reloading: _reloading,
          readPending: _readingError,
          onReadCommitted: _readCommitted,
          onReload: () => _reload().ignore(),
          onClose: _close,
        ),
      );
    },
  );

  @override
  void dispose() {
    mutation.removeListener(_outcome);
    mutation.dispose();
    for (final controller in [_name, _address, _port, _user, _tags]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }
}
