import 'dart:io';

import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' hide ReadinessView;
import 'package:serverdeck_protocol/profile_validation.dart';
import 'package:serverdeck_windows/profile_input.dart';

import '../bootstrap/local_api_client.dart';
import '../shell/readiness_view.dart';
import '../shell/form_keyboard.dart';
import 'credential_input.dart';
import 'mutation_controller.dart';
import 'mutation_status.dart';
import 'profile_controller.dart';

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
  const ProfileForm({super.key, required this.model, this.initial});
  final ProfileController model;
  final ProfileView? initial;
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
  bool _reloading = false;

  @override
  void initState() {
    super.initState();
    id = widget.initial?.id ?? newRequestId();
    _populate(widget.initial);
    mutation = MutationController(model: widget.model)..addListener(_outcome);
  }

  void _populate(ProfileView? profile) {
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
    if (_reloading || mutation.busy) return;
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

  void _close() {
    _credential.currentState?.clear();
    Navigator.of(context).maybePop();
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
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: SubmitOnEnter(
      enabled: enabled && field != 'tags',
      child: TextFormField(
        key: ValueKey('profile-$field'),
        controller: controller,
        enabled: enabled,
        autofocus: field == 'name',
        onFieldSubmitted: field == 'tags' ? null : (_) => _save().ignore(),
        decoration: InputDecoration(labelText: label),
        validator: (value) => _validate(field, value),
        minLines: field == 'tags' ? 2 : 1,
        maxLines: field == 'tags' ? 4 : 1,
        textInputAction: field == 'tags'
            ? TextInputAction.newline
            : TextInputAction.done,
      ),
    ),
  );

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
          ready && !_reloading && mutation.state == MutationPresentation.idle;
      return FormKeyboard(
        onSubmit: () => _save().ignore(),
        onClose: _close,
        child: Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Offstage(
                    offstage: !ready,
                    child: ExcludeFocus(
                      excluding: !ready,
                      child: Form(
                        key: _form,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.initial == null
                                  ? 'Новый профиль'
                                  : 'Редактирование профиля',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            _field(_name, 'name', 'Название', editable),
                            _field(
                              _address,
                              'address',
                              'Адрес (IP или имя домена)',
                              editable,
                            ),
                            _field(_port, 'port', 'Порт SSH', editable),
                            _field(_user, 'user', 'Пользователь SSH', editable),
                            _field(
                              _tags,
                              'tags',
                              'Метки (одна на строку)',
                              editable,
                            ),
                            CredentialInput(
                              key: _credential,
                              readReadyEpoch: () =>
                                  widget.model.bootstrap.state ==
                                      ReadinessState.ready
                                  ? widget.model.bootstrap.readinessEpoch
                                  : null,
                              onSubmit: () => _save().ignore(),
                              creating: revision == null,
                              enabled: editable,
                            ),
                            if (inputError != null) Text(inputError!),
                            const SizedBox(height: 16),
                            MutationStatus(
                              controller: mutation,
                              onReload: () => _reload().ignore(),
                            ),
                            if (mutation.state != MutationPresentation.idle)
                              const Text(
                                'Закрытие формы не отменяет уже отправленное сохранение',
                              ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                  onPressed: editable && widget.model.loaded
                                      ? () => _save().ignore()
                                      : null,
                                  child: const Text('Сохранить'),
                                ),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                  onPressed: _close,
                                  child: Text(
                                    mutation.state == MutationPresentation.idle
                                        ? 'Отмена'
                                        : 'Закрыть',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!ready)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ReadinessView(
                          state: widget.model.bootstrap.state,
                          reason: widget.model.bootstrap.reason,
                          retryInProgress:
                              widget.model.bootstrap.retryInProgress,
                          onRetry: () =>
                              widget.model.bootstrap.retry().ignore(),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: _close,
                          child: const Text('Закрыть'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
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
