import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/automation/values.dart'
    show automationIdentifier;

import '../ui/deck_components.dart';
import '../ui/deck_page.dart';
import '../ui/deck_icon.dart';
import '../ui/deck_input_border.dart';
import '../ui/deck_control_target.dart';
import '../theme/motion.dart';
import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';

Map<String, Object?>? _decode(String value) {
  try {
    return (jsonDecode(value) as Map).cast<String, Object?>();
  } catch (_) {
    return null;
  }
}

// Rendering safety is separate from document validity: ordinary scalar editing
// intermediates remain visible. The route keeps the exact draft; the existing
// protocol/owner still performs admission and complete validation.
bool _numberDraftShape(Object? value) => value is int || value is String;

String? _parameterControlError(Object? raw, String path) {
  if (raw is! Map<String, Object?>) return path;
  switch (raw['type']) {
    case 'enum':
      final values = raw['values'];
      if (values is! List || values.any((value) => value is! String)) {
        return '$path.values';
      }
    // Empty/duplicate values and an invalid default have safe source fields.
    // Only their ambiguous dropdown is withheld, without changing the draft.
    case 'boolean':
      if (raw['default'] is! bool) return '$path.default';
    case 'integer':
      for (final field in ['minimum', 'maximum', 'default']) {
        if (!_numberDraftShape(raw[field])) return '$path.$field';
      }
    case 'string':
      if (!_numberDraftShape(raw['maxLength'])) return '$path.maxLength';
      if (raw['default'] is! String) return '$path.default';
    default:
      return '$path.type';
  }
  return null;
}

String? _parameterShapeError(Object? raw, String path) {
  if (raw is! Map<String, Object?>) return path;
  switch (raw['type']) {
    case 'enum':
      final values = raw['values'];
      if (values is! List ||
          values.isEmpty ||
          values.length > 32 ||
          values.any((value) => value is! String) ||
          values.toSet().length != values.length) {
        return '$path.values';
      }
      if (raw['default'] is! String || !values.contains(raw['default'])) {
        return '$path.default';
      }
    case 'boolean':
      if (raw['default'] is! bool) return '$path.default';
    case 'integer':
      for (final field in ['minimum', 'maximum', 'default']) {
        if (raw[field] is! int) return '$path.$field';
      }
      final minimum = raw['minimum'] as int, maximum = raw['maximum'] as int;
      if (minimum < 0 || minimum > 1000000) return '$path.minimum';
      if (maximum < minimum || maximum > 1000000) return '$path.maximum';
      if ((raw['default'] as int) < minimum ||
          (raw['default'] as int) > maximum) {
        return '$path.default';
      }
    case 'string':
      if (raw['maxLength'] is! int) return '$path.maxLength';
      if (raw['default'] is! String) return '$path.default';
      if ((raw['maxLength'] as int) < 1 || (raw['maxLength'] as int) > 4096) {
        return '$path.maxLength';
      }
    default:
      return '$path.type';
  }
  return null;
}

String? _constraintControlError(Object? raw, String path) {
  if (raw is! Map<String, Object?>) return path;
  if (raw['type'] == 'integer') {
    if (!_numberDraftShape(raw['minimum'])) return '$path.minimum';
    if (!_numberDraftShape(raw['maximum'])) return '$path.maximum';
    return null;
  }
  if (raw['type'] != 'enum') return '$path.type';
  final values = raw['values'];
  if (values is! List ||
      values.isEmpty ||
      values.length > 32 ||
      values.any(
        (value) => value is! String && value is! int && value is! bool,
      )) {
    return '$path.values';
  }
  return null;
}

String? _constraintShapeError(Object? raw, String path) {
  if (raw is! Map<String, Object?>) return path;
  if (raw['type'] == 'integer') {
    if (raw['minimum'] is! int) return '$path.minimum';
    if (raw['maximum'] is! int) return '$path.maximum';
    final minimum = raw['minimum'] as int, maximum = raw['maximum'] as int;
    if (minimum < 0 || minimum > 1000000) return '$path.minimum';
    if (maximum < minimum || maximum > 1000000) return '$path.maximum';
    return null;
  }
  if (raw['type'] != 'enum') return '$path.type';
  final values = raw['values'];
  if (values is! List || values.isEmpty || values.length > 32) {
    return '$path.values';
  }
  // Delegation permits homogeneous string, integer OR boolean scalar enums;
  // these are different from the profile's string-only parameter definitions.
  if (values.any(
        (value) => value is! String && value is! int && value is! bool,
      ) ||
      values.any((value) => value.runtimeType != values.first.runtimeType) ||
      values.toSet().length != values.length) {
    return '$path.values';
  }
  return null;
}

bool _stringListShape(Object? value) =>
    value is List &&
    value.every((item) => item is String) &&
    value.toSet().length == value.length;

class _DraftShapeError extends StatelessWidget {
  const _DraftShapeError(this.path, {this.editable = false});
  final String path;
  final bool editable;
  @override
  Widget build(BuildContext context) {
    final message = editable
        ? 'Структура JSON: $path. Исправьте JSON в полях ниже или дополнительных сведениях. Исходный черновик сохранён.'
        : 'Структура JSON: $path. Исправьте JSON в дополнительных сведениях. Исходный черновик сохранён.';
    return Semantics(
      key: const ValueKey('automation-structured-shape-error'),
      liveRegion: true,
      label: message,
      child: ExcludeSemantics(
        child: DeckNotice(message: message, tone: DeckTone.warning),
      ),
    );
  }
}

/// A presentation codec for the existing closed JSON drafts. It never adds an
/// API field, executes a step, or decides whether the owner may save a draft.
class AutomationStructuredDraft extends StatefulWidget {
  const AutomationStructuredDraft({
    super.key,
    required this.input,
    required this.enabled,
    required this.onChanged,
    this.serverProfiles = const [],
    this.parameterDefinitions = const {},
    this.leadingFields = const [],
    this.trailingFields = const [],
  });

  final TextEditingController input;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final List<ProfileView> serverProfiles;
  final Map<String, Object?> parameterDefinitions;
  final List<Widget> leadingFields, trailingFields;

  @override
  State<AutomationStructuredDraft> createState() =>
      _AutomationStructuredDraftState();
}

class _AutomationStructuredDraftState extends State<AutomationStructuredDraft> {
  late String _observedText;
  String? _structuredText;
  int _sourceEpoch = 0;
  TextEditingController get input => widget.input;
  bool get enabled => widget.enabled;
  List<ProfileView> get serverProfiles => widget.serverProfiles;
  Map<String, Object?> get parameterDefinitions => widget.parameterDefinitions;

  @override
  void initState() {
    super.initState();
    _observedText = input.text;
    input.addListener(_observeSource);
  }

  void _observeSource() {
    final next = input.text;
    if (next == _observedText) return; // Selection/caret changes are not edits.
    _observedText = next;
    if (next != _structuredText) _sourceEpoch++;
  }

  @override
  void didUpdateWidget(covariant AutomationStructuredDraft oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.input, input)) {
      oldWidget.input.removeListener(_observeSource);
      _observedText = input.text;
      _structuredText = null;
      _sourceEpoch++;
      input.addListener(_observeSource);
    }
  }

  @override
  void dispose() {
    input.removeListener(_observeSource);
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: input,
    builder: (context, _, _) {
      Widget withContext(Widget child) =>
          widget.leadingFields.isEmpty && widget.trailingFields.isEmpty
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.leadingFields.isNotEmpty) ...[
                  AutomationFormGrid(children: widget.leadingFields),
                  const SizedBox(height: 18),
                ],
                child,
                if (widget.trailingFields.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  AutomationFormGrid(children: widget.trailingFields),
                ],
              ],
            );
      Widget shapeError(String field) => withContext(_DraftShapeError(field));
      final value = _decode(input.text);
      if (value == null) return withContext(const SizedBox.shrink());
      final controller = input, epoch = _sourceEpoch;
      void change(String key, Object? next) {
        if (!mounted ||
            !enabled ||
            epoch != _sourceEpoch ||
            !identical(controller, input))
          return;
        final source = const JsonEncoder.withIndent('  ')
            .convert({...value, key: next});
        _structuredText = source;
        try {
          controller.text = source;
        } finally {
          _structuredText = null;
        }
        if (mounted && epoch == _sourceEpoch && identical(controller, input)) {
          widget.onChanged?.call(controller.text);
        }
      }

      if (value.containsKey('scopes') || value.containsKey('serverIds')) {
        for (final field in ['scopes', 'serverIds']) {
          if (!_stringListShape(value[field])) return shapeError(field);
        }
        // A partial draft can still describe its exact targets. Missing fields
        // stay blank here; the unchanged save owner requires the complete body.
        if (value.containsKey('label') && value['label'] is! String) {
          return shapeError('label');
        }
        if (value.containsKey('lifetimeSeconds') &&
            !_numberDraftShape(value['lifetimeSeconds'])) {
          return shapeError('lifetimeSeconds');
        }
        final scopes = (value['scopes'] as List).cast<String>().toSet();
        final targets = (value['serverIds'] as List).cast<String>().toSet();
        final source = input.text;
        const scopeNames = {
          'read': 'Чтение состояния',
          'logs': 'Чтение журналов',
          'author': 'Создание и изменение профилей',
          'plan': 'Создание планов',
          'apply': 'Запуск заданий',
        };
        return withContext(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (value.containsKey('lifetimeSeconds') &&
                  value['lifetimeSeconds'] is! int)
                const _DraftShapeError('lifetimeSeconds', editable: true),
              AutomationFormGrid(
                children: [
                  AutomationValueField(
                    label: 'Клиент',
                    required: true,
                    value: value['label'],
                    enabled: enabled,
                    onChanged: (next) => change('label', next),
                  ),
                  AutomationDraftSelectionField(
                    label: 'Цели',
                    enabled: enabled,
                    selected: targets,
                    options: {
                      for (final row in serverProfiles)
                        row.id:
                            '${row.name} · ${row.address.contains(':') ? '[${row.address}]' : row.address}:${row.port}',
                    },
                    current: () => input.text == source,
                    onChanged: (next) => change('serverIds', next.toList()),
                  ),
                  AutomationDraftSelectionField(
                    label: 'Права',
                    enabled: enabled,
                    selected: scopes.difference({'apply'}),
                    options: {
                      for (final entry in scopeNames.entries)
                        if (entry.key != 'apply') entry.key: entry.value,
                    },
                    current: () => input.text == source,
                    onChanged: (next) => change('scopes', [
                      ...next,
                      if (scopes.contains('apply')) 'apply',
                    ]),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Применение', style: BrandTypography.button),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          scopes.contains('apply') ? 'Включено' : 'Выключено',
                        ),
                        value: scopes.contains('apply'),
                        onChanged: enabled
                            ? (next) {
                                final result = {...scopes};
                                next
                                    ? result.add('apply')
                                    : result.remove('apply');
                                change('scopes', result.toList());
                              }
                            : null,
                      ),
                    ],
                  ),
                  AutomationValueField(
                    label: 'Срок, секунд',
                    value: value['lifetimeSeconds'],
                    enabled: enabled,
                    numeric: true,
                    required: true,
                    onChanged: (next) => change('lifetimeSeconds', next),
                  ),
                  const AutomationFormValue(
                    label: 'Политика',
                    value: 'Отдельный grant для каждого клиента',
                  ),
                ],
              ),
            ],
          ),
        );
      }
      if (value.containsKey('predicates')) {
        final predicates = value['predicates'];
        if (predicates is! Map<String, Object?>) {
          return shapeError('predicates');
        }
        if (value.containsKey('lifetimeSeconds') &&
            !_numberDraftShape(value['lifetimeSeconds'])) {
          return shapeError('lifetimeSeconds');
        }
        final lifetime = value['lifetimeSeconds'];
        String? semanticError =
            lifetime is! int || lifetime < 300 || lifetime > 86400
            ? 'lifetimeSeconds (300–86400 секунд)'
            : null;
        for (final entry in predicates.entries) {
          final error = _constraintControlError(
            entry.value,
            'predicates.${entry.key}',
          );
          if (error != null) return shapeError(error);
          semanticError ??= _constraintShapeError(
            entry.value,
            'predicates.${entry.key}',
          );
        }
        final lifetimeField = AutomationValueField(
          label: 'Срок, секунд',
          value: value['lifetimeSeconds'],
          enabled: enabled,
          numeric: true,
          required: true,
          onChanged: (next) => change('lifetimeSeconds', next),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (semanticError != null)
              _DraftShapeError(semanticError, editable: true),
            if (widget.leadingFields.isEmpty && widget.trailingFields.isEmpty)
              lifetimeField
            else
              AutomationFormGrid(
                children: [
                  ...widget.leadingFields,
                  lifetimeField,
                  ...widget.trailingFields,
                ],
              ),
            const SizedBox(height: 20),
            for (final entry in predicates.entries)
              Padding(
                key: ValueKey((ObjectKey(input), entry.key)),
                padding: const EdgeInsets.only(bottom: 16),
                child: DeckPanel(
                  title: 'Параметр ${entry.key}',
                  child: _ConstraintFields(
                    value: (entry.value as Map).cast<String, Object?>(),
                    sourceEpoch: _sourceEpoch,
                    enabled: enabled,
                    onChanged: (next) =>
                        change('predicates', {...predicates, entry.key: next}),
                  ),
                ),
              ),
          ],
        );
      }
      String? semanticError;
      for (final entry in value.entries) {
        final definition = parameterDefinitions[entry.key];
        if (definition != null) {
          final error = _parameterControlError(
            definition,
            'parameters.${entry.key}',
          );
          if (error != null) return shapeError(error);
          semanticError ??= _parameterShapeError(
            definition,
            'parameters.${entry.key}',
          );
        }
        if (entry.value is! String &&
            entry.value is! int &&
            entry.value is! bool) {
          return shapeError(entry.key);
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (semanticError != null)
            _DraftShapeError(semanticError, editable: true),
          AutomationFormGrid(
            children: [
              ...widget.leadingFields,
              for (final entry in value.entries)
                SizedBox(
                  width: 280,
                  child: _ParameterValue(
                    label: switch (entry.key) {
                      'revision' => 'Версия',
                      'fromRevision' => 'Исходная версия',
                      'toRevision' => 'Новая версия',
                      _ => entry.key,
                    },
                    value: entry.value,
                    definition: (parameterDefinitions[entry.key] as Map?)
                        ?.cast<String, Object?>(),
                    enabled: enabled,
                    onChanged: (next) => change(entry.key, next),
                  ),
                ),
              ...widget.trailingFields,
            ],
          ),
        ],
      );
    },
  );
}

class AutomationFormGrid extends StatelessWidget {
  const AutomationFormGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => DeckHitOverflow(
    child: LayoutBuilder(
      builder: (context, c) {
        final one =
            MediaQuery.sizeOf(context).width <= 520 ||
            MediaQuery.textScalerOf(context).scale(14) >= 27;
        return Wrap(
          spacing: 14,
          runSpacing: MediaQuery.sizeOf(context).width <= 520 ? 20 : 18,
          children: [
            for (final child in children)
              DeckHitOverflow(
                child: SizedBox(
                  width: one ? c.maxWidth : (c.maxWidth - 14) / 2,
                  child: child,
                ),
              ),
          ],
        );
      },
    ),
  );
}

class AutomationLabeledField extends StatelessWidget {
  const AutomationLabeledField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
  });
  final String label;
  final Widget child;
  final bool required;
  @override
  Widget build(BuildContext context) => DeckHitOverflow(
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
                    style: TextStyle(color: deckColors(context)['accent']),
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
          child: Semantics(label: label, isRequired: required, child: child),
        ),
      ],
    ),
  );
}

class AutomationFormValue extends StatelessWidget {
  const AutomationFormValue({
    super.key,
    required this.label,
    required this.value,
    this.required = false,
  });
  final String label, value;
  final bool required;
  @override
  Widget build(BuildContext context) => AutomationLabeledField(
    label: label,
    required: required,
    child: DeckReadonlyInput(value: value),
  );
}

class AutomationDraftSelectionField extends StatefulWidget {
  const AutomationDraftSelectionField({
    super.key,
    required this.label,
    required this.enabled,
    required this.selected,
    required this.options,
    required this.current,
    required this.onChanged,
  });
  final String label;
  final bool enabled;
  final Set<String> selected;
  final Map<String, String> options;
  final bool Function() current;
  final ValueChanged<Set<String>> onChanged;
  @override
  State<AutomationDraftSelectionField> createState() =>
      _AutomationDraftSelectionFieldState();
}

class _AutomationDraftSelectionFieldState
    extends State<AutomationDraftSelectionField> {
  int epoch = 0;
  bool _focused = false;
  @override
  void didUpdateWidget(covariant AutomationDraftSelectionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || !widget.current()) epoch++;
  }

  Future<void> open() async {
    final token = epoch;
    final selected = {...widget.selected};
    final result = await showMotionDialog<Set<String>>(
      context: context,
      barrierDismissible: true,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => DeckDialogLayout(
          title: widget.label,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in widget.options.entries)
                CheckboxListTile(
                  title: Text(entry.value),
                  value: selected.contains(entry.key),
                  onChanged: (next) => update(
                    () => next == true
                        ? selected.add(entry.key)
                        : selected.remove(entry.key),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              clipBehavior: Clip.none,
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Отмена'),
            ),
            FilledButton(
              clipBehavior: Clip.none,
              onPressed: () => Navigator.pop(dialog, selected),
              child: const Text('Выбрать'),
            ),
          ],
        ),
      ),
    );
    if (mounted &&
        epoch == token &&
        widget.enabled &&
        widget.current() &&
        result != null)
      widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.enabled,
    child: InkWell(
      onTap: widget.enabled ? open : null,
      canRequestFocus: widget.enabled,
      onFocusChange: (focused) => setState(() => _focused = focused),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      child: AutomationLabeledField(
        label: widget.label,
        child: InputDecorator(
          isFocused: _focused && widget.enabled,
          decoration: deckFormDecoration(context)
              .copyWith(enabled: widget.enabled),
          child: Text(
            widget.selected.isEmpty
                ? 'Не выбрано'
                : widget.selected
                      .map(
                        (key) => widget.options[key] ?? 'Сведения недоступны',
                      )
                      .join(', '),
            style: deckFormTextStyle(context),
          ),
        ),
      ),
    ),
  );
}

class _ParameterValue extends StatelessWidget {
  const _ParameterValue({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.definition,
    this.numeric = false,
    this.required = false,
  });
  final String label;
  final Object? value;
  final bool enabled, numeric, required;
  final ValueChanged<Object?> onChanged;
  final Map<String, Object?>? definition;
  @override
  Widget build(BuildContext context) {
    if (definition?['type'] == 'enum') {
      final values = definition!['values'];
      if (values is! List ||
          values.isEmpty ||
          values.length > 32 ||
          values.any((item) => item is! String) ||
          values.toSet().length != values.length ||
          definition!['default'] is! String ||
          value is! String) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AutomationFormValue(
              label: label,
              value: value is String
                  ? value as String
                  : 'Неподдержанный тип значения',
            ),
            const SizedBox(height: 8),
            const Text(
              'Выбор недоступен: исправьте список допустимых значений или тип значения по умолчанию.',
            ),
          ],
        );
      }
      return _Choice(
        label: label,
        required: required,
        value: value as String,
        values: values.cast<String>(),
        enabled: enabled,
        onChanged: onChanged,
      );
    }
    if (value is bool)
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value as bool,
        onChanged: enabled ? onChanged : null,
      );
    return AutomationValueField(
      label: label,
      required: required || value is int || definition?['type'] == 'integer',
      value: value,
      enabled: enabled,
      numeric: numeric || value is int || definition?['type'] == 'integer',
      helper: definition == null
          ? null
          : switch (definition!['type']) {
              'integer' =>
                '${definition!['minimum']}…${definition!['maximum']}',
              'string' => 'Не более ${definition!['maxLength']} символов',
              _ => null,
            },
      onChanged: onChanged,
    );
  }
}

class _ConstraintFields extends StatefulWidget {
  const _ConstraintFields({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.sourceEpoch,
  });
  final Map<String, Object?> value;
  final bool enabled;
  final int sourceEpoch;
  final ValueChanged<Map<String, Object?>> onChanged;
  @override
  State<_ConstraintFields> createState() => _ConstraintFieldsState();
}

class _ConstraintFieldsState extends State<_ConstraintFields> {
  String? _enumKind;

  String? _sourceKind() {
    final values = widget.value['values'];
    if (widget.value['type'] != 'enum' || values is! List || values.isEmpty)
      return null;
    if (values.every((value) => value is int)) return 'integer';
    if (values.every((value) => value is bool)) return 'boolean';
    if (values.every((value) => value is String)) return 'string';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _enumKind = _sourceKind();
  }

  @override
  void didUpdateWidget(covariant _ConstraintFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sourceEpoch != oldWidget.sourceEpoch) _enumKind = _sourceKind();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value, enabled = widget.enabled;
    final onChanged = widget.onChanged;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          value['type'] == 'integer'
              ? 'Разрешённый диапазон целых чисел'
              : 'Разрешённые точные значения',
        ),
        const SizedBox(height: 12),
        if (value['type'] == 'integer') ...[
          AutomationValueField(
            label: 'Минимум',
            value: value['minimum'],
            enabled: enabled,
            numeric: true,
            required: true,
            onChanged: (next) => onChanged({...value, 'minimum': next}),
          ),
          const SizedBox(height: 12),
          AutomationValueField(
            label: 'Максимум',
            value: value['maximum'],
            enabled: enabled,
            numeric: true,
            required: true,
            onChanged: (next) => onChanged({...value, 'maximum': next}),
          ),
        ] else ...[
          for (var i = 0; i < (value['values'] as List).length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ParameterValue(
                label: 'Значение ${i + 1}',
                value: (value['values'] as List)[i],
                numeric: _enumKind == 'integer',
                required: _enumKind == 'integer',
                enabled: enabled,
                onChanged: (next) {
                  final values = List<Object?>.of(value['values'] as List);
                  values[i] = next;
                  onChanged({...value, 'values': values});
                },
              ),
            ),
          OutlinedButton(
            clipBehavior: Clip.none,
            onPressed: enabled && (value['values'] as List).length < 32
                ? () => onChanged({
                    ...value,
                    'values': [
                      ...value['values'] as List,
                      (value['values'] as List).first,
                    ],
                  })
                : null,
            child: const Text('Добавить допустимое значение'),
          ),
          if ((value['values'] as List).length > 1)
            TextButton(
              clipBehavior: Clip.none,
              onPressed: enabled
                  ? () => onChanged({
                      ...value,
                      'values': [...value['values'] as List]..removeLast(),
                    })
                  : null,
              child: const Text('Удалить последнее значение'),
            ),
        ],
      ],
    );
  }
}

/// Structured fields for format1 only. All validation still goes through the
/// original owner and AutomationBody codec; checks are a readonly derivation.
class AutomationProfileFields extends StatefulWidget {
  const AutomationProfileFields({
    super.key,
    required this.body,
    required this.enabled,
    required this.onChanged,
    required this.identityFields,
    this.showTabs = true,
    this.selectedSection,
  });
  final TextEditingController body;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final List<Widget> identityFields;
  final bool showTabs;
  final int? selectedSection;
  @override
  State<AutomationProfileFields> createState() =>
      _AutomationProfileFieldsState();
}

class _AutomationProfileFieldsState extends State<AutomationProfileFields> {
  int tab = 0;
  Future<void> renameParameter(String oldName) async {
    final source = widget.body.text;
    final body = _decode(source);
    if (!widget.enabled || body == null || body['parameters'] is! Map) return;
    final parameters = (body['parameters'] as Map).cast<String, Object?>();
    final next = await showMotionDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialog) => _ParameterNameDialog(
        original: oldName,
        names: parameters.keys.toSet(),
        current: () => mounted && widget.enabled && widget.body.text == source,
      ),
    );
    if (!mounted ||
        !widget.enabled ||
        widget.body.text != source ||
        next == null ||
        next == oldName)
      return;
    Object? renameReference(Object? value) => switch (value) {
      Map() when value.length == 1 && value['param'] == oldName => {
        'param': next,
      },
      Map() => value.map((key, child) => MapEntry(key, renameReference(child))),
      List() => value.map(renameReference).toList(),
      _ => value,
    };
    widget.body.text = const JsonEncoder.withIndent('  ').convert({
      ...body,
      'parameters': {
        for (final entry in parameters.entries)
          (entry.key == oldName ? next : entry.key): entry.value,
      },
      'steps': renameReference(body['steps']),
    });
    widget.onChanged(widget.body.text);
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: widget.body,
    builder: (context, _, _) {
      final value = _decode(widget.body.text);
      if (value == null) return Column(children: widget.identityFields);
      String? shapeError;
      if (value['steps'] is! List) {
        shapeError = 'steps';
      } else if (value['parameters'] is! Map<String, Object?>) {
        shapeError = 'parameters';
      } else {
        final rawSteps = value['steps'] as List;
        for (var index = 0; index < rawSteps.length; index++) {
          final step = rawSteps[index];
          if (step is! Map<String, Object?> ||
              step['kind'] == 'config_file' &&
                  step['values'] is! Map<String, Object?>) {
            shapeError = 'steps[$index]';
            break;
          }
        }
        if (shapeError == null) {
          for (final entry
              in (value['parameters'] as Map<String, Object?>).entries) {
            shapeError = _parameterControlError(
              entry.value,
              'parameters.${entry.key}',
            );
            if (shapeError != null) break;
          }
        }
      }
      if (shapeError != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [...widget.identityFields, _DraftShapeError(shapeError)],
        );
      }
      final parameters = (value['parameters'] as Map).cast<String, Object?>();
      final steps = (value['steps'] as List)
          .map((e) => (e as Map).cast<String, Object?>())
          .toList();
      String? semanticError;
      for (final entry in parameters.entries) {
        semanticError ??= _parameterShapeError(
          entry.value,
          'parameters.${entry.key}',
        );
      }
      void change(String key, Object? next) {
        widget.body.text = const JsonEncoder.withIndent('  ')
            .convert({...value, key: next});
        widget.onChanged(widget.body.text);
      }

      final selected = widget.selectedSection ?? tab;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTabs)
            DeckTabs(
              labels: const ['Назначение', 'Шаги', 'Параметры', 'Проверки'],
              selected: tab,
              onSelected: (next) => setState(() => tab = next),
            ),
          if (widget.showTabs) const DeckTabsGap(),
          if (semanticError != null)
            _DraftShapeError(semanticError, editable: true),
          if (selected == 0) ...[
            DeckHitOverflow(
              child: LayoutBuilder(
                builder: (context, c) {
                  final one =
                      MediaQuery.sizeOf(context).width <= 520 ||
                      MediaQuery.textScalerOf(context).scale(14) >= 27;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.identityFields.isNotEmpty)
                        DeckHitOverflow(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: one ? c.maxWidth : (c.maxWidth - 14) / 2,
                              child: widget.identityFields.first,
                            ),
                          ),
                        ),
                      ...widget.identityFields.skip(1),
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: MediaQuery.sizeOf(context).width <= 520 ? 20 : 18),
            AutomationFormGrid(
              children: [
                const AutomationFormValue(
                  label: 'Среда',
                  value: 'Ubuntu 24.04 · amd64 · systemd',
                ),
                AutomationFormValue(
                  label: 'Параметр',
                  value: parameters.isEmpty
                      ? 'Параметров нет'
                      : parameters.entries
                            .map(
                              (entry) =>
                                  '${entry.key} · ${(entry.value as Map)['type']}',
                            )
                            .join(', '),
                ),
                AutomationFormValue(
                  label: 'Шаг',
                  value: steps.isEmpty
                      ? 'Шагов нет'
                      : steps
                            .map(
                              (step) =>
                                  '${step['resourceId'] ?? step['recipeDigest']} · ${step['kind']}',
                            )
                            .join(', '),
                ),
                const AutomationFormValue(
                  label: 'Проверка',
                  value: 'Проверки будут определены планом',
                ),
                const AutomationFormValue(
                  label: 'Версия',
                  value: 'Новая версия',
                ),
              ],
            ),
          ],
          if (selected == 1) ...[
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DeckPanel(
                  title: 'Шаг ${i + 1}',
                  trailing: IconButton(
                    tooltip: 'Удалить шаг ${i + 1}',
                    onPressed: widget.enabled
                        ? () => change('steps', [...steps]..removeAt(i))
                        : null,
                    icon: const DeckIcon('close'),
                  ),
                  child: _StepFields(
                    value: steps[i],
                    parameters: parameters,
                    enabled: widget.enabled,
                    onChanged: (next) {
                      final rows = [...steps];
                      rows[i] = next;
                      change('steps', rows);
                    },
                  ),
                ),
              ),
            OutlinedButton(
              clipBehavior: Clip.none,
              onPressed: widget.enabled && steps.length < 32
                  ? () => change('steps', [
                      ...steps,
                      {
                        'id': 'step${steps.length + 1}',
                        'kind': 'config_file',
                        'resourceId': 'system.motd',
                        'values': {'text': ''},
                      },
                    ])
                  : null,
              child: const Text('Добавить шаг'),
            ),
          ],
          if (selected == 2) ...[
            for (final entry in parameters.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DeckPanel(
                  title: entry.key,
                  trailing: IconButton(
                    tooltip: 'Удалить параметр ${entry.key}',
                    onPressed: widget.enabled
                        ? () => change(
                            'parameters',
                            {...parameters}..remove(entry.key),
                          )
                        : null,
                    icon: const DeckIcon('close'),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton(
                        clipBehavior: Clip.none,
                        onPressed: widget.enabled
                            ? () => renameParameter(entry.key)
                            : null,
                        child: const Text('Изменить имя параметра'),
                      ),
                      const SizedBox(height: 16),
                      _ParameterDefinition(
                        value: (entry.value as Map).cast<String, Object?>(),
                        enabled: widget.enabled,
                        onChanged: (next) => change('parameters', {
                          ...parameters,
                          entry.key: next,
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            OutlinedButton(
              clipBehavior: Clip.none,
              onPressed: widget.enabled && parameters.length < 32
                  ? () {
                      var i = parameters.length + 1;
                      while (parameters.containsKey('parameter$i')) {
                        i++;
                      }
                      change('parameters', {
                        ...parameters,
                        'parameter$i': {
                          'type': 'string',
                          'maxLength': 4096,
                          'default': '',
                        },
                      });
                    }
                  : null,
              child: const Text('Добавить параметр'),
            ),
          ],
          if (selected == 3) ...[
            const Text(
              'Проверки задаёт поддержанный формат шага. Произвольные команды, YAML и дополнительные checks не допускаются.',
            ),
            for (final step in steps)
              DeckKeyValue(
                label: '${step['id']}',
                value: switch (step['kind']) {
                  'service' => 'Состояние и автозапуск службы',
                  'config_file' => 'Повторное чтение управляемых значений',
                  'install_recipe' => 'Точный рецепт и его проверки результата',
                  _ => 'Неизвестный формат шага',
                },
              ),
          ],
        ],
      );
    },
  );
}

class _ParameterNameDialog extends StatefulWidget {
  const _ParameterNameDialog({
    required this.original,
    required this.names,
    required this.current,
  });
  final String original;
  final Set<String> names;
  final bool Function() current;
  @override
  State<_ParameterNameDialog> createState() => _ParameterNameDialogState();
}

class _ParameterNameDialogState extends State<_ParameterNameDialog> {
  late final name = TextEditingController(text: widget.original);
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DeckDialogLayout(
    title: 'Имя параметра',
    maxWidth: 520,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutomationLabeledField(
          label: 'Идентификатор',
          required: true,
          child: TextField(
            key: const ValueKey('automation-field-Идентификатор'),
            controller: name,
            style: deckFormTextStyle(context),
            decoration: deckFormDecoration(context)
                .copyWith(errorText: error, errorMaxLines: 4),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'a–z, 0–9 и подчёркивание; начинается с буквы; до 32 символов.',
          style: BrandTypography.caption.copyWith(
            height: MediaQuery.sizeOf(context).width <= 520 ? 20 / 12 : 18 / 12,
            color: deckColors(context)['muted'],
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        clipBehavior: Clip.none,
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        clipBehavior: Clip.none,
        onPressed: () {
          if (!widget.current()) return;
          try {
            automationIdentifier(name.text);
            if (name.text != widget.original &&
                widget.names.contains(name.text))
              throw const FormatException();
            Navigator.pop(context, name.text);
          } on FormatException {
            setState(
              () => error = 'Введите уникальный идентификатор параметра в поддержанном формате.',
            );
          }
        },
        child: const Text('Переименовать'),
      ),
    ],
  );
}

class _ParameterDefinition extends StatelessWidget {
  const _ParameterDefinition({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final Map<String, Object?> value;
  final bool enabled;
  final ValueChanged<Map<String, Object?>> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Choice(
        label: 'Тип',
        value: '${value['type']}',
        values: const ['string', 'integer', 'boolean', 'enum'],
        enabled: enabled,
        onChanged: (next) => onChanged(switch (next) {
          'integer' => {
            'type': 'integer',
            'minimum': 0,
            'maximum': 1000000,
            'default': 0,
          },
          'boolean' => {'type': 'boolean', 'default': false},
          'enum' => {
            'type': 'enum',
            'values': ['value'],
            'default': 'value',
          },
          _ => {'type': 'string', 'maxLength': 4096, 'default': ''},
        }),
      ),
      const SizedBox(height: 16),
      if (value['type'] == 'string')
        AutomationValueField(
          label: 'Максимальная длина',
          value: value['maxLength'],
          enabled: enabled,
          numeric: true,
          required: true,
          onChanged: (next) => onChanged({...value, 'maxLength': next}),
        ),
      if (value['type'] == 'integer') ...[
        AutomationValueField(
          label: 'Минимум',
          value: value['minimum'],
          enabled: enabled,
          numeric: true,
          required: true,
          onChanged: (next) => onChanged({...value, 'minimum': next}),
        ),
        const SizedBox(height: 12),
        AutomationValueField(
          label: 'Максимум',
          value: value['maximum'],
          enabled: enabled,
          numeric: true,
          required: true,
          onChanged: (next) => onChanged({...value, 'maximum': next}),
        ),
      ],
      if (value['type'] == 'enum')
        AutomationValueField(
          label: 'Допустимые значения (по одному на строку)',
          value: (value['values'] as List).join('\n'),
          enabled: enabled,
          multiline: true,
          onChanged: (next) =>
              onChanged({...value, 'values': '$next'.split('\n')}),
        ),
      const SizedBox(height: 16),
      _ParameterValue(
        label: 'По умолчанию',
        value: value['default'],
        definition: value,
        enabled: enabled,
        onChanged: (next) => onChanged({...value, 'default': next}),
      ),
    ],
  );
}

class _StepFields extends StatelessWidget {
  const _StepFields({
    required this.value,
    required this.parameters,
    required this.enabled,
    required this.onChanged,
  });
  final Map<String, Object?> value, parameters;
  final bool enabled;
  final ValueChanged<Map<String, Object?>> onChanged;
  @override
  Widget build(BuildContext context) {
    final kind = value['kind'];
    final resource = value['resourceId'];
    Map<String, Object?> defaults(String resource) => switch (resource) {
      'postgresql.settings' => {
        'max_connections': 100,
        'shared_buffers_mb': 128,
      },
      'clickhouse.settings' => {
        'max_connections': 100,
        'max_server_memory_usage_mb': 1024,
      },
      _ => {'text': ''},
    };
    Widget binding(
      String name,
      Object? current,
      ValueChanged<Object?> save, {
      bool required = false,
    }) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (current is Map && current['param'] is String)
            _Choice(
              label: '$name · параметр',
              required: required || defaults('$resource')[name] is int,
              value: '${current['param']}',
              values: parameters.keys.toList(),
              enabled: enabled,
              onChanged: (next) => save({'param': next}),
            )
          else
            _ParameterValue(
              label: name,
              required: required || defaults('$resource')[name] is int,
              value: current,
              numeric: defaults('$resource')[name] is int,
              enabled: enabled,
              onChanged: save,
            ),
          if (parameters.isNotEmpty)
            TextButton(
              clipBehavior: Clip.none,
              onPressed: enabled
                  ? () => save(
                      current is Map ? '' : {'param': parameters.keys.first},
                    )
                  : null,
              child: Text(
                current is Map
                    ? 'Задать точное значение'
                    : 'Использовать параметр',
              ),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutomationValueField(
          label: 'Идентификатор шага',
          required: true,
          value: value['id'],
          enabled: enabled,
          onChanged: (next) => onChanged({...value, 'id': next}),
        ),
        const SizedBox(height: 16),
        _Choice(
          label: 'Тип шага',
          value: '$kind',
          values: const ['config_file', 'service', 'install_recipe'],
          enabled: enabled,
          onChanged: (next) => onChanged(switch (next) {
            'service' => {
              'id': value['id'],
              'kind': 'service',
              'resourceId': 'postgresql.service',
              'state': 'started',
            },
            'install_recipe' => {
              'id': value['id'],
              'kind': 'install_recipe',
              'recipeDigest': '',
              'version': '',
            },
            _ => {
              'id': value['id'],
              'kind': 'config_file',
              'resourceId': 'system.motd',
              'values': {'text': ''},
            },
          }),
        ),
        const SizedBox(height: 16),
        if (kind == 'config_file') ...[
          _Choice(
            label: 'Управляемый ресурс',
            value: '$resource',
            values: const [
              'system.motd',
              'postgresql.settings',
              'clickhouse.settings',
            ],
            enabled: enabled,
            onChanged: (next) => onChanged({
              ...value,
              'resourceId': next,
              'values': defaults(next),
            }),
          ),
          for (final entry in (value['values'] as Map).entries)
            binding(
              '${entry.key}',
              entry.value,
              (next) => onChanged({
                ...value,
                'values': {...value['values'] as Map, entry.key: next},
              }),
            ),
        ],
        if (kind == 'service') ...[
          _Choice(
            label: 'Служба',
            value: '$resource',
            values: const ['postgresql.service', 'clickhouse.service'],
            enabled: enabled,
            onChanged: (next) => onChanged({...value, 'resourceId': next}),
          ),
          if (value['state'] is Map)
            binding(
              'Состояние',
              value['state'],
              (next) => onChanged({...value, 'state': next}),
            )
          else ...[
            const SizedBox(height: 16),
            _Choice(
              label: 'Состояние',
              value: '${value['state']}',
              values: const ['started', 'stopped', 'restarted'],
              enabled: enabled,
              onChanged: (next) => onChanged({...value, 'state': next}),
            ),
            if (parameters.isNotEmpty)
              TextButton(
                clipBehavior: Clip.none,
                onPressed: enabled
                    ? () => onChanged({
                        ...value,
                        'state': {'param': parameters.keys.first},
                      })
                    : null,
                child: const Text('Использовать параметр состояния'),
              ),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Управлять автозапуском'),
            value: value.containsKey('enabled'),
            onChanged: enabled
                ? (next) => onChanged(
                    next == true
                        ? {...value, 'enabled': true}
                        : ({...value}..remove('enabled')),
                  )
                : null,
          ),
          if (value.containsKey('enabled'))
            binding(
              'Автозапуск',
              value['enabled'],
              (next) => onChanged({...value, 'enabled': next}),
            ),
        ],
        if (kind == 'install_recipe') ...[
          AutomationValueField(
            label: 'Digest точного рецепта (SHA-256)',
            required: true,
            value: value['recipeDigest'],
            enabled: enabled,
            onChanged: (next) => onChanged({...value, 'recipeDigest': next}),
          ),
          binding(
            'Точная версия',
            value['version'],
            (next) => onChanged({...value, 'version': next}),
            required: true,
          ),
        ],
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.values,
    required this.enabled,
    required this.onChanged,
    this.required = false,
  });
  final String label, value;
  final List<String> values;
  final bool enabled, required;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => AutomationLabeledField(
    label: label,
    required: required,
    child: MotionDropdown<String>(
      key: ValueKey((label, value, jsonEncode(values))),
      initialValue: values.contains(value) ? value : null,
      isExpanded: true,
      decoration: deckFormDecoration(context),
      items: values
          .map(
            (v) => DropdownMenuItem(
              value: v,
              child: Text(v, style: deckFormTextStyle(context)),
            ),
          )
          .toList(),
      onChanged: enabled
          ? (next) {
              if (next != null) onChanged(next);
            }
          : null,
    ),
  );
}

class AutomationValueField extends StatefulWidget {
  const AutomationValueField({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.numeric = false,
    this.required = false,
    this.multiline = false,
    this.helper,
  });
  final String label;
  final Object? value;
  final bool enabled, numeric, multiline, required;
  final String? helper;
  final ValueChanged<Object?> onChanged;
  @override
  State<AutomationValueField> createState() => _AutomationValueFieldState();
}

class _AutomationValueFieldState extends State<AutomationValueField> {
  late final TextEditingController field = TextEditingController(
    text: '${widget.value ?? ''}',
  );
  @override
  void didUpdateWidget(covariant AutomationValueField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = '${widget.value ?? ''}';
    if (field.text != text)
      field.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
  }

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final changed = widget.onChanged, numeric = widget.numeric;
    return DeckHitOverflow(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AutomationLabeledField(
            label: widget.label,
            required: widget.required,
            child: TextField(
              key: ValueKey('automation-field-${widget.label}'),
              controller: field,
              enabled: widget.enabled,
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                height: MediaQuery.sizeOf(context).width <= 520
                    ? 22 / 14
                    : 20 / 14,
              ),
              minLines: widget.multiline ? 2 : 1,
              maxLines: widget.multiline ? null : 1,
              keyboardType: widget.numeric ? TextInputType.number : null,
              decoration: deckFormDecoration(context),
              onChanged: widget.enabled
                  ? (next) =>
                        changed(numeric ? int.tryParse(next) ?? next : next)
                  : null,
            ),
          ),
          if (widget.helper != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.helper!,
              style: BrandTypography.caption.copyWith(
                height: MediaQuery.sizeOf(context).width <= 520
                    ? 20 / 12
                    : 18 / 12,
                color: deckColors(context)['muted'],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
