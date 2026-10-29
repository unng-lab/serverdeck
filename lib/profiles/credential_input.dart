import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/profile_validation.dart';
import 'package:serverdeck_windows/profile_input.dart';

import '../theme/motion.dart';
import '../theme/brand_tokens.dart';
import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';
import '../shell/form_keyboard.dart';
import '../ui/deck_components.dart';
import '../ui/deck_control_target.dart';
import '../ui/deck_input_border.dart';
import 'profile_presentation.dart';

enum CredentialChoice { keep, remove, password, privateKey }

class CredentialInput extends StatefulWidget {
  const CredentialInput({
    super.key,
    required this.creating,
    required this.enabled,
    this.pickKey = pickPrivateKey,
    this.onSubmit,
    this.readReadyEpoch,
    this.compact = false,
    this.pageTarget,
    this.onPickingChanged,
    this.onPresentationChanged,
    this.inlinePageActions = true,
    this.choiceLabel,
  });
  final bool creating, enabled;
  final bool compact;
  final String? pageTarget;
  final ValueChanged<bool>? onPickingChanged;
  final VoidCallback? onPresentationChanged;
  final bool inlinePageActions;
  final String? choiceLabel;
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
  bool _pickedFile = false;
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
    _pickedFile = false;
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
    widget.onPickingChanged?.call(true);
    try {
      final key = await widget.pickKey();
      if (!current() || epoch != _pickerEpoch) return;
      if (key != null) {
        keyInput.text = key;
        _pickedFile = true;
      }
    } on Object {
      if (current() && epoch == _pickerEpoch)
        setState(
          () => error = 'Не удалось прочитать ключ: выберите файл UTF-8 размером не более 64 КиБ',
        );
    } finally {
      // A retired picker still owns the pending native dialog. Release the
      // busy flag when it finishes, without publishing its result or error.
      if (mounted) {
        setState(() => picking = false);
        widget.onPickingChanged?.call(false);
      }
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
  }) => DeckHitOverflow(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Floating InputDecorator labels elide long instructions at200%.
        // Keep the complete instruction visible, associated with its input.
        ExcludeSemantics(
          child: !widget.compact && widget.pageTarget == null
              ? Text(label, style: Theme.of(context).textTheme.bodyLarge)
              : ProfileFieldLabel(label: label, required: id != 'passphrase'),
        ),
        SizedBox(
          height: !widget.compact && widget.pageTarget == null
              ? BrandSpacing.space8
              : 7,
        ),
        DeckControlTarget(
          visibleHeight:
              (widget.compact || widget.pageTarget != null) &&
                  MediaQuery.sizeOf(context).width > 520
              ? 42
              : 44,
          child: Semantics(
            label: label,
            isRequired: id != 'passphrase',
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
                style: widget.compact || widget.pageTarget != null
                    ? deckFormTextStyle(
                        context,
                        monospace: revealed && multiline,
                      )
                    : Theme.of(context).textTheme.bodyLarge,
                // Flutter's obscured one-line editor strips LF on platform edits.
                // PEM must remain verbatim: editing uses the explicitly revealed
                // multiline view, while a picked key can stay hidden throughout.
                readOnly: multiline && !revealed,
                decoration:
                    (widget.compact || widget.pageTarget != null
                            ? deckFormDecoration(context)
                            : const InputDecoration())
                        .copyWith(
                          helper: multiline && !revealed
                              ? _keyInstruction()
                              : null,
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
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.pageTarget != null) return _pageFields();
    final children = <Widget>[
      if (widget.compact) ...[
        ExcludeSemantics(
          child: ProfileFieldLabel(
            label: widget.choiceLabel ?? 'Способ доступа',
          ),
        ),
        const SizedBox(height: 6),
      ],
      ..._controls(),
    ];
    if (widget.compact)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    return DeckFormSection(
      title: 'Доступ к серверу',
      description: 'Существующий секрет не читается в форму. Сохранение не подключает сервер.',
      children: children,
    );
  }

  Widget _label(String label, Widget child, {bool required = false}) =>
      DeckHitOverflow(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Text.rich(
                TextSpan(
                  text: label,
                  children: [
                    if (required)
                      TextSpan(
                        text: ' *',
                        style: TextStyle(
                          color: Theme.of(context)
                              .extension<BrandColors>()!['accent'],
                        ),
                      ),
                  ],
                ),
                style: BrandTypography.caption.copyWith(
                  height: 20 / 12,
                  fontFamily: BrandAssets.semiboldFamily,
                  fontWeight: BrandTypography.semiboldWeight,
                  fontVariations: BrandTypography.semiboldVariations,
                ),
              ),
            ),
            const SizedBox(height: 7),
            DeckControlTarget(
              visibleHeight: MediaQuery.sizeOf(context).width <= 520 ? 44 : 42,
              child: Semantics(
                label: label,
                isRequired: required,
                child: child,
              ),
            ),
          ],
        ),
      );

  InputDecoration get _pageDecoration => deckFormDecoration(context);

  Widget _readonly(
    String label,
    String value, {
    bool required = false,
    bool multiline = false,
  }) => _label(
    label,
    Semantics(
      readOnly: true,
      child: DeckReadonlyInput(value: value, multiline: multiline),
    ),
    required: required,
  );

  Widget _pageFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ProfileFieldGrid(
        fullWidthIndexes: const {2},
        children: [
          _readonly('Цель', widget.pageTarget!, required: true),
          _label('Доступ', _choice(_pageDecoration), required: true),
          _readonly(
            'Файл ключа',
            picking
                ? 'Ожидаем выбор файла ключа'
                : _pickedFile
                ? 'Имя файла не возвращается: загружено содержимое'
                : 'Файл не выбран; имя и путь не сохраняются в форме',
            multiline: true,
          ),
          if (choice == CredentialChoice.privateKey)
            _secret(
              keyInput,
              'Приватный ключ',
              id: 'private-key',
              multiline: true,
            )
          else if (choice == CredentialChoice.password)
            _secret(password, 'Пароль', id: 'password')
          else
            _readonly(
              'Приватный ключ',
              choice == CredentialChoice.keep
                  ? 'Существующий секрет не возвращается в форму'
                  : 'Новый секрет не задан',
            ),
          if (choice == CredentialChoice.privateKey)
            _secret(passphrase, 'Passphrase', id: 'passphrase')
          else
            _readonly('Passphrase', 'Используется только для нового ключа'),
          _readonly('Хранение', 'Защита ОС текущего пользователя'),
        ],
      ),
      if (picking) ...[
        const SizedBox(height: 16),
        const DeckStatus(label: 'Ожидаем выбор файла ключа', pending: true),
      ],
      if (error != null) ...[
        const SizedBox(height: 16),
        DeckNotice(message: error!, tone: DeckTone.error),
      ],
      if (widget.inlinePageActions) ...[
        const SizedBox(height: 16),
        pageActionBar(trailing: const []),
      ],
    ],
  );

  /// Uses this same secret/picker owner in the containing form's action footer.
  Widget pageActionBar({required List<Widget> trailing}) => DeckFormActions(
    children: [
      Tooltip(
        message: choice == CredentialChoice.privateKey
            ? 'Выбрать локальный файл приватного ключа'
            : 'Выберите способ доступа «Новый приватный ключ»',
        child: FilledButton(
          clipBehavior: Clip.none,
          style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
          onPressed:
              widget.enabled &&
                  !picking &&
                  choice == CredentialChoice.privateKey
              ? _pick
              : null,
          child: Text(picking ? 'Чтение ключа' : 'Выбрать файл ключа'),
        ),
      ),
      Semantics(
        toggled: revealed,
        child: OutlinedButton(
          clipBehavior: Clip.none,
          style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
          onPressed:
              widget.enabled &&
                  !picking &&
                  (choice == CredentialChoice.password ||
                      choice == CredentialChoice.privateKey)
              ? () {
                  setState(() => revealed = !revealed);
                  widget.onPresentationChanged?.call();
                }
              : null,
          child: const Text('Показать введённый секрет'),
        ),
      ),
      ...trailing,
    ],
  );

  Widget _choice(InputDecoration decoration) =>
      MotionDropdown<CredentialChoice>(
        initialValue: choice,
        isExpanded: true,
        decoration: decoration,
        items: CredentialChoice.values
            .where((v) => !widget.creating || v != CredentialChoice.keep)
            .map(
              (v) => DropdownMenuItem(
                value: v,
                child: Text(
                  switch (v) {
                    CredentialChoice.keep => 'Сохранить существующий',
                    CredentialChoice.remove => 'Без секрета / удалить',
                    CredentialChoice.password => 'Новый пароль',
                    CredentialChoice.privateKey => 'Новый приватный ключ',
                  },
                  style: widget.compact || widget.pageTarget != null
                      ? deckFormTextStyle(context)
                      : null,
                ),
              ),
            )
            .toList(),
        onChanged: widget.enabled && !picking
            ? (value) {
                setState(() {
                  clear();
                  choice = value!;
                  error = null;
                });
                widget.onPresentationChanged?.call();
              }
            : null,
      );

  List<Widget> _controls() => [
    if (widget.compact)
      DeckControlTarget(
        visibleHeight: MediaQuery.sizeOf(context).width <= 520 ? 44 : 42,
        child: Semantics(
          label: widget.choiceLabel ?? 'Способ доступа',
          child: _choice(_pageDecoration),
        ),
      )
    else
      _choice(const InputDecoration(labelText: 'Секрет доступа')),
    if (choice == CredentialChoice.password)
      _secret(password, 'Пароль', id: 'password'),
    if (choice == CredentialChoice.privateKey) ...[
      _secret(keyInput, 'Приватный ключ', id: 'private-key', multiline: true),
      _secret(passphrase, 'Passphrase (необязательно)', id: 'passphrase'),
      OutlinedButton(
        clipBehavior: Clip.none,
        style: OutlinedButton.styleFrom(
          minimumSize: Size(widget.compact ? 44 : 48, widget.compact ? 44 : 48),
        ),
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
  ];
}
