import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/profile_validation.dart';
import 'package:serverdeck_windows/profile_input.dart';

import '../theme/motion.dart';
import '../theme/brand_tokens.dart';
import '../shell/form_keyboard.dart';
import '../ui/deck_components.dart';

enum CredentialChoice { keep, remove, password, privateKey }

class CredentialInput extends StatefulWidget {
  const CredentialInput({
    super.key,
    required this.creating,
    required this.enabled,
    this.pickKey = pickPrivateKey,
    this.onSubmit,
    this.readReadyEpoch,
  });
  final bool creating, enabled;
  final Future<String?> Function() pickKey;
  final VoidCallback? onSubmit;
  final int? Function()? readReadyEpoch;
  @override
  State<CredentialInput> createState() => CredentialInputState();
}

class CredentialInputState extends State<CredentialInput> {
  final password = TextEditingController(),
      keyInput = TextEditingController(),
      passphrase = TextEditingController();
  late CredentialChoice choice = widget.creating
      ? CredentialChoice.remove
      : CredentialChoice.keep;
  bool revealed = false, picking = false;
  String? error;
  int _pickerEpoch = 0;

  @override
  void didUpdateWidget(covariant CredentialInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _pickerEpoch++;
  }

  Map<String, Object?> action() => normalizeCredential(switch (choice) {
    CredentialChoice.keep => {'action': 'keep'},
    CredentialChoice.remove => {'action': 'remove'},
    CredentialChoice.password => {
      'action': 'replace',
      'kind': 'password',
      'password': password.text,
    },
    CredentialChoice.privateKey => {
      'action': 'replace',
      'kind': 'privateKey',
      'privateKey': keyInput.text,
      'passphrase': passphrase.text.isEmpty ? null : passphrase.text,
    },
  }, creating: widget.creating);

  void clear() {
    _pickerEpoch++;
    password.clear();
    keyInput.clear();
    passphrase.clear();
    revealed = false;
  }

  void resetChoice() {
    clear();
    setState(
      () => choice = widget.creating
          ? CredentialChoice.remove
          : CredentialChoice.keep,
    );
  }

  Future<void> _pick() async {
    if (!widget.enabled || picking) return;
    final readyEpoch = widget.readReadyEpoch?.call();
    if (widget.readReadyEpoch != null && readyEpoch == null) return;
    bool current() =>
        mounted &&
        widget.enabled &&
        (widget.readReadyEpoch == null ||
            widget.readReadyEpoch!() == readyEpoch);
    final epoch = ++_pickerEpoch;
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final key = await widget.pickKey();
      if (!current() || epoch != _pickerEpoch) return;
      if (key != null) keyInput.text = key;
    } on Object {
      if (current() && epoch == _pickerEpoch)
        setState(
          () => error = 'Не удалось прочитать ключ: выберите файл UTF-8 размером не более 64 КиБ',
        );
    } finally {
      // A retired picker still owns the pending native dialog. Release the
      // busy flag when it finishes, without publishing its result or error.
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  void dispose() {
    clear();
    password.dispose();
    keyInput.dispose();
    passphrase.dispose();
    super.dispose();
  }

  Widget _keyInstruction() => Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final decorator = context
          .findAncestorWidgetOfExactType<InputDecorator>()!;
      final states = <WidgetState>{
        if (!decorator.decoration.enabled) WidgetState.disabled,
        if (decorator.isFocused) WidgetState.focused,
        if (decorator.isHovering) WidgetState.hovered,
        if (decorator.decoration.error != null ||
            decorator.decoration.errorText != null)
          WidgetState.error,
      };
      // A custom helper does not inherit InputDecorator's helperStyle. Retain
      // its Material3 typography/role and effective theme/state overrides.
      // Keep the instruction opaque when the editor is locked, like its value.
      final style = theme.textTheme.bodySmall!
          .copyWith(color: theme.colorScheme.onSurfaceVariant)
          .merge(
            WidgetStateProperty.resolveAs(
              decorator.decoration.helperStyle,
              states,
            ),
          );
      return Text(
        'Для ввода ключа включите показ или выберите файл',
        style: style.copyWith(color: style.color?.withAlpha(255)),
        overflow: TextOverflow.visible,
      );
    },
  );

  Widget _secret(
    TextEditingController controller,
    String label, {
    required String id,
    bool multiline = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Floating InputDecorator labels elide long instructions at200%.
      // Keep the complete instruction visible, associated with its input.
      ExcludeSemantics(
        child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
      ),
      const SizedBox(height: BrandSpacing.space8),
      Semantics(
        label: label,
        child: SubmitOnEnter(
          enabled:
              widget.enabled &&
              !picking &&
              !(revealed && multiline) &&
              widget.onSubmit != null,
          child: TextFormField(
            key: ValueKey('credential-$id'),
            controller: controller,
            enabled: widget.enabled && !picking,
            // Material's default disabled style reduces value opacity to 0.38.
            style: Theme.of(context).textTheme.bodyLarge,
            // Flutter's obscured one-line editor strips LF on platform edits.
            // PEM must remain verbatim: editing uses the explicitly revealed
            // multiline view, while a picked key can stay hidden throughout.
            readOnly: multiline && !revealed,
            decoration: InputDecoration(
              helper: multiline && !revealed ? _keyInstruction() : null,
            ),
            obscureText: !revealed,
            onFieldSubmitted: revealed && multiline
                ? null
                : (_) => widget.onSubmit?.call(),
            minLines: revealed && multiline ? 3 : 1,
            maxLines: revealed && multiline ? 6 : 1,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [],
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => DeckFormSection(
    title: 'Доступ к серверу',
    description: 'Существующий секрет не читается в форму. Сохранение не подключает сервер.',
    children: [
      MotionDropdown<CredentialChoice>(
        initialValue: choice,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Секрет доступа'),
        items: CredentialChoice.values
            .where((v) => !widget.creating || v != CredentialChoice.keep)
            .map(
              (v) => DropdownMenuItem(
                value: v,
                child: Text(switch (v) {
                  CredentialChoice.keep => 'Сохранить существующий',
                  CredentialChoice.remove => 'Без секрета / удалить',
                  CredentialChoice.password => 'Новый пароль',
                  CredentialChoice.privateKey => 'Новый приватный ключ',
                }),
              ),
            )
            .toList(),
        onChanged: widget.enabled && !picking
            ? (value) => setState(() {
                clear();
                choice = value!;
                error = null;
              })
            : null,
      ),
      if (choice == CredentialChoice.password)
        _secret(password, 'Пароль', id: 'password'),
      if (choice == CredentialChoice.privateKey) ...[
        _secret(keyInput, 'Приватный ключ', id: 'private-key', multiline: true),
        _secret(passphrase, 'Passphrase (необязательно)', id: 'passphrase'),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: widget.enabled && !picking ? _pick : null,
          child: Text(picking ? 'Чтение ключа' : 'Выбрать файл ключа'),
        ),
        if (picking)
          const DeckStatus(label: 'Ожидаем выбор файла ключа', pending: true),
      ],
      if (choice == CredentialChoice.password ||
          choice == CredentialChoice.privateKey)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const DeckFocusLabel(child: Text('Показать введённый секрет')),
          value: revealed,
          onChanged: widget.enabled && !picking
              ? (value) => setState(() => revealed = value!)
              : null,
        ),
      if (error != null) DeckNotice(message: error!, tone: DeckTone.error),
    ],
  );
}
