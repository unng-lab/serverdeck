import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/models.dart';
import '../domain/error_presentation.dart';
import '../ui/deck_components.dart';
import 'profile_controller.dart';

class ProfileForm extends StatefulWidget {
  const ProfileForm({
    super.key,
    required this.controller,
    required this.pickKey,
    this.profile,
  });
  final ProfileController controller;
  final ProfileView? profile;
  final Future<Uint8List?> Function() pickKey;
  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  late final _name = TextEditingController(
    text: widget.profile?.displayName ?? '',
  );
  late final _host = TextEditingController(text: widget.profile?.host ?? '');
  late final _port = TextEditingController(
    text: '${widget.profile?.port ?? 22}',
  );
  late final _user = TextEditingController(
    text: widget.profile?.username ?? '',
  );
  final _password = TextEditingController(),
      _passphrase = TextEditingController();
  late AuthKind _kind = widget.profile?.authKind ?? AuthKind.password;
  late String _mutationId = widget.controller.newId();
  Uint8List? _key;
  OperationFailure? _error;
  bool _pending = false, _replace = false, _encryptedPhrase = false;
  void _changed(String _) {
    _mutationId = widget.controller.newId();
    if (_error != null) setState(() => _error = null);
  }

  void _clearKey() {
    _key?.fillRange(0, _key!.length, 0);
    _key = null;
  }

  Future<void> _pick() async {
    try {
      final bytes = await widget.pickKey();
      if (!mounted) {
        bytes?.fillRange(0, bytes.length, 0);
        return;
      }
      if (bytes != null) {
        setState(() {
          _clearKey();
          _key = bytes;
          _changed('');
        });
      }
    } on PlatformException catch (error) {
      if (mounted)
        setState(
          () => _error = OperationFailure(
            error.code == 'INVALID_ARGUMENT'
                ? FailureCode.invalidArgument
                : FailureCode.storageUnavailable,
            field: OperationField.authentication,
          ),
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _error = const OperationFailure(
            FailureCode.storageUnavailable,
            field: OperationField.authentication,
          ),
        );
    }
  }

  Future<void> _save() async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    AuthenticationInput? auth;
    try {
      final port = int.tryParse(_port.text);
      if (port == null || port < 1 || port > 65535)
        throw const OperationFailure(
          FailureCode.invalidArgument,
          field: OperationField.port,
        );
      if (widget.profile == null || _replace) {
        if (_kind == AuthKind.password)
          auth = PasswordInput(_password.text);
        else {
          if (_key == null)
            throw const OperationFailure(
              FailureCode.invalidArgument,
              field: OperationField.authentication,
            );
          auth = PrivateKeyInput(
            _key!,
            passphrase: _encryptedPhrase ? _passphrase.text : null,
          );
        }
      }
      final p = widget.profile;
      final failure = p == null
          ? await widget.controller.create(
              ProfileDraft(
                displayName: _name.text,
                host: _host.text,
                port: port,
                username: _user.text,
                authentication: auth!,
              ),
              _mutationId,
            )
          : await widget.controller.update(
              p,
              ProfilePatch(
                displayName: _name.text,
                host: _host.text,
                port: port,
                username: _user.text,
                authentication: auth,
              ),
              _mutationId,
            );
      if (!mounted) return;
      if (failure == null) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _error = failure;
          if (failure.code == FailureCode.passphraseRequired)
            _encryptedPhrase = true;
        });
      }
    } on OperationFailure catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      auth?.dispose();
      _passphrase.clear();
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_pending,
    child: DeckDialogLayout(
      title: widget.profile == null ? 'Добавить сервер' : 'Изменить сервер',
      child: DeckFormSection(
        title: 'Профиль SSH',
        children: [
          DeckTextField(
            label: 'Название',
            controller: _name,
            enabled: !_pending,
            onChanged: _changed,
          ),
          DeckTextField(
            label: 'Хост',
            controller: _host,
            enabled: !_pending,
            onChanged: _changed,
          ),
          DeckTextField(
            label: 'Порт',
            controller: _port,
            enabled: !_pending,
            onChanged: _changed,
            keyboardType: TextInputType.number,
          ),
          DeckTextField(
            label: 'Пользователь',
            controller: _user,
            enabled: !_pending,
            onChanged: _changed,
          ),
          if (widget.profile != null)
            CheckboxListTile(
              title: const Text('Заменить учётные данные'),
              value: _replace,
              onChanged: _pending
                  ? null
                  : (v) => setState(() {
                      _replace = v!;
                      _password.clear();
                      _passphrase.clear();
                      _clearKey();
                      _changed('');
                    }),
            ),
          if (widget.profile == null || _replace) ...[
            DropdownButtonFormField<AuthKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Способ входа'),
              items: const [
                DropdownMenuItem(
                  value: AuthKind.password,
                  child: Text('Пароль'),
                ),
                DropdownMenuItem(
                  value: AuthKind.privateKey,
                  child: Text('Приватный ключ OpenSSH'),
                ),
              ],
              onChanged: _pending
                  ? null
                  : (v) => setState(() {
                      _kind = v!;
                      _password.clear();
                      _passphrase.clear();
                      _clearKey();
                      _changed('');
                    }),
            ),
            if (_kind == AuthKind.password)
              DeckTextField(
                label: 'Пароль',
                secret: true,
                controller: _password,
                enabled: !_pending,
                onChanged: _changed,
              )
            else ...[
              DeckButton(
                onPressed: _pending ? null : _pick,
                child: Text(
                  _key == null
                      ? 'Выбрать файл ключа'
                      : 'Ключ выбран — заменить',
                ),
              ),
              CheckboxListTile(
                title: const Text('Указать passphrase для проверки ключа'),
                value: _encryptedPhrase,
                onChanged: _pending
                    ? null
                    : (v) => setState(() {
                        _encryptedPhrase = v!;
                        _passphrase.clear();
                        _changed('');
                      }),
              ),
              if (_encryptedPhrase)
                DeckTextField(
                  label: 'Passphrase',
                  secret: true,
                  controller: _passphrase,
                  enabled: !_pending,
                  onChanged: _changed,
                ),
              const Text(
                'Passphrase используется только для проверки. При подключении она будет запрошена снова.',
              ),
            ],
          ],
          if (_error != null)
            DeckNotice(
              title: 'Не удалось сохранить',
              message: OperationPresentation.of(_error!).message,
              nextStep: OperationPresentation.of(_error!).nextStep,
              tone: DeckTone.error,
            ),
        ],
      ),
      actions: [
        DeckButton(
          onPressed: _pending ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        DeckButton(
          onPressed: _pending ? null : _save,
          pending: _pending,
          kind: DeckButtonKind.primary,
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    _clearKey();
    for (final c in [_name, _host, _port, _user, _password, _passphrase]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }
}
