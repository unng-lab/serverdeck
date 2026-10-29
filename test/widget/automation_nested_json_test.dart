import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_forms.dart';
import 'package:serverdeck/automation/automation_presentation.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_page.dart';

import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_server_fixtures.dart';

Map<String, Object?> _body(Object? definition) => {
  'format': 1,
  'environment': 'ubuntu24.04-amd64-systemd',
  'parameters': {'choice': definition},
  'steps': <Object?>[],
};

const _validEnum = <String, Object?>{
  'type': 'enum',
  'values': ['first', 'second'],
  'default': 'first',
};

class _ProfileFlow {
  _ProfileFlow(String source) : body = TextEditingController(text: source);
  final name = TextEditingController(text: '  Точный профиль  ');
  final description = TextEditingController(text: 'Описание\n\tбез изменений');
  final TextEditingController body;
  final submission = AutomationProfileDraftSubmission();
  int writes = 0, closes = 0, validations = 0, changes = 0;
  Map<String, Object?>? written;

  Widget app(double scale) => _host(
    ValueListenableBuilder<TextEditingValue>(
      valueListenable: body,
      builder: (context, _, _) => ListenableBuilder(
        listenable: submission,
        builder: (context, _) => AutomationProfileEditorDialog(
          asPage: true,
          name: name,
          description: description,
          body: body,
          validating: false,
          canValidate: true,
          saving: submission.saving,
          error: submission.error,
          nameError: submission.nameError,
          descriptionError: submission.descriptionError,
          saveError: submission.saveError,
          onBodyChanged: (_) => changes++,
          onClose: () => closes++,
          onValidate: () => validations++,
          onSave: () => submission
              .save(
                name: name.text,
                description: description.text,
                source: body.text,
                current: () => context.mounted,
                submit: (_, _, value) async {
                  writes++;
                  written = value;
                },
                resultError: () => null,
                close: () => closes++,
              )
              .ignore(),
        ),
      ),
    ),
    scale,
  );

  void dispose() {
    submission.dispose();
    name.dispose();
    description.dispose();
    body.dispose();
  }
}

class _DelegationFlow {
  _DelegationFlow(Map<String, Object?> predicate)
    : input = TextEditingController(
        text:
            ' \n${jsonEncode({
              'lifetimeSeconds': 3600,
              'predicates': {'choice': predicate},
            })}\t',
      );
  final TextEditingController input;
  final submission = AutomationJsonDraftSubmission(AutomationUiPhase.delegate);
  int changes = 0, admissions = 0, writes = 0, closes = 0;
  Map<String, Object?>? written;
  Widget app(double scale) => _host(
    ValueListenableBuilder<TextEditingValue>(
      valueListenable: input,
      builder: (context, _, _) => ListenableBuilder(
        listenable: submission,
        builder: (context, _) => AutomationJsonEditorDialog(
          asPage: true,
          title: 'Делегирование профиля',
          input: input,
          error: submission.error,
          saving: submission.saving,
          onChanged: (_) => changes++,
          onClose: () => closes++,
          onContinue: () => submission
              .submit(
                source: input.text,
                current: () => context.mounted,
                completionCurrent: () => context.mounted,
                canSubmit: () => true,
                targetsAvailable: (_) => true,
                submit: (value, admitted) {
                  admissions++;
                  admitted();
                  writes++;
                  written = value;
                  return Future<void>.value();
                },
                result: () => const AutomationUiResult(),
                close: () => closes++,
              )
              .ignore(),
        ),
      ),
    ),
    scale,
  );

  Map<String, Object?> get predicate =>
      ((jsonDecode(input.text) as Map)['predicates'] as Map)['choice']
          as Map<String, Object?>;

  void dispose() {
    submission.dispose();
    input.dispose();
  }
}

Widget _host(Widget child, double scale) => MaterialApp(
  theme: Motion.theme(BrandTheme.dark, true),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void _frame(WidgetTester tester, double scale) {
  tester.view.physicalSize = scale == 1
      ? const Size(1100, 760)
      : const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      (widget.decoration?.labelText == label ||
          widget.key == ValueKey('automation-field-$label')),
);

EditableTextState _editingState(WidgetTester tester, Finder field) =>
    tester.state<EditableTextState>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );

Finder _predicateField(String name, String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is DeckPanel && widget.title == 'Параметр $name',
  ),
  matching: _field(label),
);

Future<void> _replace(WidgetTester tester, Finder field, String text) async {
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

Future<void> _selectAllDelete(WidgetTester tester, Finder field) async {
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadDesignFonts);
  for (final scale in [1.0, 2.0]) {
    for (final resource in ['postgresql.settings', 'clickhouse.settings']) {
      for (final fromParameter in [false, true]) {
        testWidgets(
          'T172 config integer survives ${fromParameter ? 'parameter to literal' : 'clear'} $resource at $scale',
          (tester) async {
            _frame(tester, scale);
            final flow = _ProfileFlow(
              jsonEncode({
                'format': 1,
                'environment': 'ubuntu24.04-amd64-systemd',
                'parameters': {
                  'connections': {
                    'type': 'integer',
                    'minimum': 10,
                    'maximum': 1000,
                    'default': 100,
                  },
                },
                'steps': [
                  {
                    'id': 'database',
                    'kind': 'config_file',
                    'resourceId': resource,
                    'values': {
                      'max_connections': fromParameter
                          ? {'param': 'connections'}
                          : 100,
                      if (resource == 'postgresql.settings')
                        'shared_buffers_mb': 128
                      else
                        'max_server_memory_usage_mb': 1024,
                    },
                  },
                  {
                    'id': 'message',
                    'kind': 'config_file',
                    'resourceId': 'system.motd',
                    'values': {'text': '100'},
                  },
                ],
              }),
            );
            Object? connections() =>
                (((jsonDecode(flow.body.text) as Map)['steps'] as List).first
                    as Map)['values']['max_connections'];
            try {
              await tester.pumpWidget(flow.app(scale));
              await tester.pumpAndSettle();
              await _tap(tester, find.widgetWithText(TextButton, 'Шаги'));
              if (fromParameter) {
                await _tap(tester, find.text('Задать точное значение').first);
              } else {
                await _selectAllDelete(tester, _field('max_connections'));
              }
              final editor = _editingState(tester, _field('max_connections'));
              expect(connections(), '');
              expect(flow.writes, 0);
              await _tap(tester, _field('max_connections'));
              tester.testTextInput.enterText('200');
              tester.testTextInput.hide();
              await tester.pumpAndSettle();
              expect(connections(), isA<int>());
              expect(connections(), 200);
              expect(
                _editingState(tester, _field('max_connections')),
                same(editor),
              );
              await _replace(tester, _field('max_connections'), 'not a number');
              final invalid = flow.body.text;
              await _tap(
                tester,
                find.widgetWithText(OutlinedButton, 'Сохранить версию'),
              );
              expect(flow.body.text, invalid);
              expect(flow.writes, 0);
              await _replace(tester, _field('max_connections'), '200');
              await _replace(tester, _field('text'), '200');
              final steps =
                  (jsonDecode(flow.body.text) as Map)['steps'] as List;
              expect((steps.last as Map)['values']['text'], '200');
              await _tap(
                tester,
                find.widgetWithText(OutlinedButton, 'Сохранить версию'),
              );
              expect(flow.writes, 1);
              expect(
                ((flow.written!['steps'] as List).first
                    as Map)['values']['max_connections'],
                200,
              );
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              flow.dispose();
            }
          },
        );
      }
    }
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'T174 literal-only source stays editable without a plan write at $scale',
      (tester) async {
        _frame(tester, scale);
        final capturedBody = <String, Object?>{
          'format': 1,
          'environment': 'ubuntu24.04-amd64-systemd',
          'parameters': <String, Object?>{},
          'steps': [
            {
              'id': 'motd',
              'kind': 'config_file',
              'resourceId': 'system.motd',
              'values': {'text': 'Captured literal source'},
            },
          ],
        };
        final source = jsonEncode(capturedBody);
        final flow = _ProfileFlow(source);
        try {
          await tester.pumpWidget(flow.app(scale));
          await tester.pumpAndSettle();
          expect(flow.body.text, source);
          expect(flow.writes + flow.validations + flow.closes, 0);
          expect(find.byType(AutomationJsonEditorDialog), findsNothing);
          await _tap(tester, find.widgetWithText(TextButton, 'Шаги'));
          expect(
            tester.widget<TextField>(_field('text')).controller!.text,
            'Captured literal source',
          );
          expect(flow.body.text, source);
          await _replace(tester, _field('text'), 'Explicitly edited source');
          expect(flow.writes + flow.validations + flow.closes, 0);
          expect(capturedBody['parameters'], isEmpty);
          expect(
            ((capturedBody['steps'] as List).single as Map)['values']['text'],
            'Captured literal source',
          );
          await _tap(
            tester,
            find.widgetWithText(OutlinedButton, 'Сохранить версию'),
          );
          expect(flow.writes, 1);
          expect(flow.validations, 0);
          expect(flow.written!['parameters'], isEmpty);
          expect(
            ((flow.written!['steps'] as List).single as Map)['values']['text'],
            'Explicitly edited source',
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          flow.dispose();
        }
      },
    );
  }
  final invalidDefinitions = <String, Object?>{
    for (final invalid in <Object?>[
      1,
      null,
      true,
      {'x': 1},
      [1],
    ])
      'values element ${jsonEncode(invalid)}': {
        ..._validEnum,
        'values': [invalid],
      },
    for (final invalid in <Object?>[
      null,
      true,
      1,
      'first',
      {'x': 1},
    ])
      'values shape ${jsonEncode(invalid)}': {..._validEnum, 'values': invalid},
    for (final invalid in <Object?>[
      null,
      true,
      1,
      {'x': 1},
      ['first'],
    ])
      'default shape ${jsonEncode(invalid)}': {
        ..._validEnum,
        'default': invalid,
      },
    'empty enum': {..._validEnum, 'values': <Object?>[]},
    'duplicate enum': {
      ..._validEnum,
      'values': ['first', 'first'],
    },
    'non-object definition': ['enum'],
  };

  for (final scale in [1.0, 2.0]) {
    final validDelegation = <String, Object?>{
      'lifetimeSeconds': 3600,
      'predicates': {
        'choice': {
          'type': 'enum',
          'values': ['first', 'second'],
        },
      },
    };
    final invalidDelegations = <String, Map<String, Object?>>{
      'missing TTL': Map.of(validDelegation)..remove('lifetimeSeconds'),
      'missing predicates': Map.of(validDelegation)..remove('predicates'),
      'extra editor field': {...validDelegation, 'extra': true},
      for (final ttl in <Object?>['', '3600', null, false, 300.0, 299, 86401])
        'TTL ${jsonEncode(ttl)}': {...validDelegation, 'lifetimeSeconds': ttl},
      'non-map predicates': {...validDelegation, 'predicates': []},
      '33 predicates': {
        ...validDelegation,
        'predicates': {
          for (var i = 0; i < 33; i++)
            'choice$i': {
              'type': 'enum',
              'values': ['x'],
            },
        },
      },
      'invalid identifier': {
        ...validDelegation,
        'predicates': {
          'bad-name': {
            'type': 'enum',
            'values': ['x'],
          },
        },
      },
      for (final values in <Object?>[
        ['first', 'first'],
        ['first', 1],
        [false, 1],
        [],
        [null],
        [
          [1],
        ],
        [
          {'x': 1},
        ],
        [1.5],
        [-1],
        [1000001],
        ['{{value}}'],
      ])
        'enum ${jsonEncode(values)}': {
          ...validDelegation,
          'predicates': {
            'choice': {'type': 'enum', 'values': values},
          },
        },
      'extra predicate field': {
        ...validDelegation,
        'predicates': {
          'choice': {
            'type': 'enum',
            'values': ['first'],
            'extra': true,
          },
        },
      },
      for (final bounds in <Map<String, Object?>>[
        {'minimum': '', 'maximum': 10},
        {'minimum': 1.5, 'maximum': 10},
        {'minimum': -1, 'maximum': 10},
        {'minimum': 20, 'maximum': 10},
        {'minimum': 0, 'maximum': 1000001},
      ])
        'range ${jsonEncode(bounds)}': {
          ...validDelegation,
          'predicates': {
            'choice': {'type': 'integer', ...bounds},
          },
        },
    };
    for (final entry in invalidDelegations.entries) {
      testWidgets('T160 real delegate boundary ${entry.key} at $scale', (
        tester,
      ) async {
        _frame(tester, scale);
        final semantics = tester.ensureSemantics();
        final flow = _DelegationFlow({
          'type': 'enum',
          'values': ['first'],
        });
        final source = ' \n${jsonEncode(entry.value)}\t';
        flow.input.text = source;
        try {
          await tester.pumpWidget(flow.app(scale));
          await tester.pumpAndSettle();
          await _tap(tester, find.widgetWithText(FilledButton, 'Продолжить'));
          expect(flow.admissions, 0);
          expect(flow.writes, 0);
          expect(flow.closes, 0);
          expect(flow.submission.requestRetained, isFalse);
          expect(flow.submission.saving, isFalse);
          expect(flow.input.text, source);
          expect(flow.submission.error, automationDraftInputError());
          final rawTitle = find.text('JSON · дополнительные сведения');
          final rawField = find.byWidgetPredicate(
            (widget) =>
                widget is TextField && identical(widget.controller, flow.input),
          );
          if (rawField.evaluate().isEmpty) await _tap(tester, rawTitle);
          expect(
            tester.widget<TextField>(rawField).decoration!.errorText,
            automationDraftInputError(),
          );
          expect(
            find.bySemanticsLabel(
              RegExp(RegExp.escape(automationDraftInputError())),
            ),
            findsWidgets,
          );
          final repaired = ' \n${jsonEncode(validDelegation)}\t';
          await _replace(tester, rawField, repaired);
          expect(flow.input.text, repaired);
          expect(flow.writes, 0);
          await _tap(tester, find.widgetWithText(FilledButton, 'Продолжить'));
          expect(flow.admissions, 1);
          expect(flow.writes, 1);
          expect(flow.closes, 1);
          expect(flow.written, validDelegation);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          flow.dispose();
          semantics.dispose();
        }
      });
    }

    for (final lifetime in [300, 86400]) {
      testWidgets(
        'T160 real delegate boundary accepts TTL $lifetime at $scale',
        (tester) async {
          _frame(tester, scale);
          final flow = _DelegationFlow({
            'type': 'enum',
            'values': ['first'],
          });
          flow.input.text = jsonEncode({
            ...validDelegation,
            'lifetimeSeconds': lifetime,
          });
          try {
            await tester.pumpWidget(flow.app(scale));
            await tester.pumpAndSettle();
            await _tap(tester, find.widgetWithText(FilledButton, 'Продолжить'));
            expect(flow.admissions, 1);
            expect(flow.writes, 1);
            expect(flow.written!['lifetimeSeconds'], lifetime);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            flow.dispose();
          }
        },
      );
    }

    for (final ordering in ['same', 'reordered']) {
      testWidgets(
        'T161 raw TTL replacement resets retained choice with $ordering predicate at $scale',
        (tester) async {
          _frame(tester, scale);
          final flow = _DelegationFlow({
            'type': 'enum',
            'values': [1, 2],
          });
          if (ordering == 'reordered') {
            flow.input.text = jsonEncode({
              'lifetimeSeconds': 3600,
              'predicates': {
                'choice': {
                  'type': 'enum',
                  'values': [1, 2],
                },
                'other': {
                  'type': 'enum',
                  'values': ['x', 'y'],
                },
              },
            });
          }
          try {
            await tester.pumpWidget(flow.app(scale));
            await tester.pumpAndSettle();
            await _selectAllDelete(
              tester,
              _predicateField('choice', 'Значение 1'),
            );
            await _selectAllDelete(
              tester,
              _predicateField('choice', 'Значение 2'),
            );
            expect(flow.predicate['values'], ['', '']);
            final state = _editingState(
              tester,
              _predicateField('choice', 'Значение 1'),
            );
            await _tap(tester, find.text('JSON · дополнительные сведения'));
            final rawField = find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  identical(widget.controller, flow.input),
            );
            final replacement =
                ' \n${jsonEncode({
                  'lifetimeSeconds': 7200,
                  'predicates': {
                    if (ordering == 'reordered') 'other': {
                        'type': 'enum',
                        'values': ['x', 'y'],
                      },
                    'choice': {
                      'type': 'enum',
                      'values': ['', ''],
                    },
                  },
                })}\t';
            await _replace(tester, rawField, replacement);
            expect(flow.input.text, replacement);
            expect(
              _editingState(tester, _predicateField('choice', 'Значение 1')),
              same(state),
            );
            await _replace(
              tester,
              _predicateField('choice', 'Значение 1'),
              '3',
            );
            expect(flow.predicate['values'], ['3', '']);
            expect(flow.admissions, 0);
            expect(flow.writes, 0);
            await _tap(tester, find.widgetWithText(FilledButton, 'Продолжить'));
            expect(flow.writes, 1);
            expect(
              ((flow.written!['predicates'] as Map)['choice'] as Map)['values'],
              ['3', ''],
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            flow.dispose();
          }
        },
      );
    }

    testWidgets(
      'T161 own structured TTL and caret preserve numeric intent at $scale',
      (tester) async {
        _frame(tester, scale);
        final flow = _DelegationFlow({
          'type': 'enum',
          'values': [1, 2],
        });
        try {
          await tester.pumpWidget(flow.app(scale));
          await tester.pumpAndSettle();
          final state = _editingState(tester, _field('Значение 1'));
          await _selectAllDelete(tester, _field('Значение 1'));
          await _selectAllDelete(tester, _field('Значение 2'));
          final beforeCaret = flow.input.text;
          flow.input.selection = TextSelection.collapsed(
            offset: beforeCaret.length,
          );
          await tester.pumpAndSettle();
          expect(flow.input.text, beforeCaret);
          await _replace(tester, _field('Срок, секунд'), '7200');
          expect(flow.predicate['values'], ['', '']);
          expect(_editingState(tester, _field('Значение 1')), same(state));
          await _replace(tester, _field('Значение 1'), '3');
          expect(flow.predicate['values'], [3, '']);
          await _replace(tester, _field('Значение 2'), '4');
          expect(flow.predicate['values'], [3, 4]);
          expect(flow.admissions, 0);
          await _tap(tester, find.widgetWithText(FilledButton, 'Продолжить'));
          expect(flow.writes, 1);
          expect(flow.written!['lifetimeSeconds'], 7200);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          flow.dispose();
        }
      },
    );

    testWidgets(
      'T161 raw replacement retires old field callback before frame and disposal at $scale',
      (tester) async {
        _frame(tester, scale);
        final flow = _DelegationFlow({
          'type': 'enum',
          'values': [1, 2],
        });
        try {
          await tester.pumpWidget(flow.app(scale));
          await tester.pumpAndSettle();
          await _selectAllDelete(tester, _field('Значение 1'));
          await _selectAllDelete(tester, _field('Значение 2'));
          final oldCallback = tester
              .widget<TextField>(_field('Значение 1'))
              .onChanged!;
          await _tap(tester, find.text('JSON · дополнительные сведения'));
          final rawField = find.byWidgetPredicate(
            (widget) =>
                widget is TextField && identical(widget.controller, flow.input),
          );
          await tester.ensureVisible(rawField);
          await tester.tap(rawField);
          final replacement =
              ' \n${jsonEncode({
                'lifetimeSeconds': 7200,
                'predicates': {
                  'choice': {
                    'type': 'enum',
                    'values': ['', ''],
                  },
                },
              })}\t';
          tester.testTextInput.enterText(replacement);
          oldCallback('7');
          expect(flow.input.text, replacement);
          await tester.pumpAndSettle();
          oldCallback('8');
          expect(flow.input.text, replacement);
          await tester.pumpWidget(const SizedBox.shrink());
          oldCallback('9');
          expect(flow.input.text, replacement);
          expect(flow.writes, 0);
          expect(flow.admissions, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          flow.dispose();
        }
      },
    );

    testWidgets(
      'T161 replacing equal-source controller retires old callbacks at $scale',
      (tester) async {
        _frame(tester, scale);
        final first = TextEditingController(
          text: jsonEncode({
            'lifetimeSeconds': 3600,
            'predicates': {
              'choice': {
                'type': 'enum',
                'values': [1, 2],
              },
            },
          }),
        );
        final second = TextEditingController();
        var active = first;
        late StateSetter rebuild;
        var changes = 0;
        try {
          await tester.pumpWidget(
            _host(
              StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return SingleChildScrollView(
                    child: AutomationStructuredDraft(
                      input: active,
                      enabled: true,
                      onChanged: (_) => changes++,
                    ),
                  );
                },
              ),
              scale,
            ),
          );
          await tester.pumpAndSettle();
          await _selectAllDelete(tester, _field('Значение 1'));
          await _selectAllDelete(tester, _field('Значение 2'));
          final retiredCallback = tester
              .widget<TextField>(_field('Значение 1'))
              .onChanged!;
          final original = first.text;
          second.text = original;
          rebuild(() => active = second);
          await tester.pumpAndSettle();
          retiredCallback('7');
          expect(first.text, original);
          expect(second.text, original);
          expect(changes, 2);
          await _replace(tester, _field('Значение 1'), '3');
          final predicate =
              ((jsonDecode(second.text) as Map)['predicates'] as Map)['choice']
                  as Map;
          expect(predicate['values'], ['3', '']);
          await tester.pumpWidget(const SizedBox.shrink());
          final completed = second.text;
          retiredCallback('8');
          expect(second.text, completed);
          expect(first.text, original);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          first.dispose();
          second.dispose();
        }
      },
    );

    testWidgets('T153 delegation enum Add then explicit repair at $scale', (
      tester,
    ) async {
      _frame(tester, scale);
      final semantics = tester.ensureSemantics();
      final flow = _DelegationFlow({
        'type': 'enum',
        'values': ['first'],
      });
      final original = flow.input.text;
      try {
        await tester.pumpWidget(flow.app(scale));
        await tester.pumpAndSettle();
        expect(flow.input.text, original);
        expect(flow.changes, 0);
        final firstState = _editingState(tester, _field('Значение 1'));
        final firstController = tester
            .widget<TextField>(_field('Значение 1'))
            .controller;
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, 'Добавить допустимое значение'),
        );
        expect(flow.predicate['values'], ['first', 'first']);
        expect(_editingState(tester, _field('Значение 1')), same(firstState));
        expect(
          tester.widget<TextField>(_field('Значение 1')).controller,
          same(firstController),
        );
        expect(_field('Значение 2'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('automation-structured-shape-error')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp('Структура JSON.*predicates.choice.values'),
          ),
          findsWidgets,
        );
        await _tap(tester, find.widgetWithText(FilledButton, 'Продолжить'));
        expect(flow.writes, 0);
        expect(flow.closes, 0);
        expect(flow.predicate['values'], ['first', 'first']);
        await _replace(tester, _field('Значение 2'), 'second');
        expect(flow.predicate['values'], ['first', 'second']);
        expect(flow.changes, 2);
        expect(flow.writes, 0);
        await _tap(tester, find.widgetWithText(FilledButton, 'Продолжить'));
        expect(flow.writes, 1);
        expect(flow.closes, 1);
        expect(flow.written!['predicates'], {
          'choice': {
            'type': 'enum',
            'values': ['first', 'second'],
          },
        });
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        flow.dispose();
        semantics.dispose();
      }
    });

    testWidgets(
      'T153 profile enum values retain old default until explicit choice at $scale',
      (tester) async {
        _frame(tester, scale);
        final semantics = tester.ensureSemantics();
        final flow = _ProfileFlow(' \n${jsonEncode(_body(_validEnum))}\t');
        final original = flow.body.text;
        final name = flow.name.text, description = flow.description.text;
        try {
          await tester.pumpWidget(flow.app(scale));
          await tester.pumpAndSettle();
          await _tap(tester, find.widgetWithText(TextButton, 'Параметры'));
          expect(flow.body.text, original);
          expect(flow.changes, 0);
          final valuesState = _editingState(
            tester,
            _field('Допустимые значения (по одному на строку)'),
          );
          final valuesController = tester
              .widget<TextField>(
                _field('Допустимые значения (по одному на строку)'),
              )
              .controller;
          await _replace(
            tester,
            _field('Допустимые значения (по одному на строку)'),
            'second\nthird',
          );
          final pending =
              (jsonDecode(flow.body.text) as Map)['parameters'] as Map;
          expect((pending['choice'] as Map)['values'], ['second', 'third']);
          expect((pending['choice'] as Map)['default'], 'first');
          expect(
            _editingState(
              tester,
              _field('Допустимые значения (по одному на строку)'),
            ),
            same(valuesState),
          );
          expect(
            tester
                .widget<TextField>(
                  _field('Допустимые значения (по одному на строку)'),
                )
                .controller,
            same(valuesController),
          );
          expect(valuesState.widget.focusNode.hasFocus, isTrue);
          expect(find.byType(MotionDropdown<String>), findsNWidgets(2));
          expect(
            find.bySemanticsLabel(
              RegExp('Структура JSON.*parameters.choice.default'),
            ),
            findsWidgets,
          );
          await _tap(
            tester,
            find.widgetWithText(OutlinedButton, 'Сохранить версию'),
          );
          expect(flow.writes, 0);
          expect(flow.closes, 0);
          final choice = find.byType(MotionDropdown<String>).at(1);
          await _tap(tester, choice);
          await _tap(tester, find.text('third').last);
          expect(flow.name.text, name);
          expect(flow.description.text, description);
          expect(flow.writes, 0);
          await _tap(
            tester,
            find.widgetWithText(OutlinedButton, 'Сохранить версию'),
          );
          expect(flow.writes, 1);
          expect(
            flow.written,
            _body({
              ..._validEnum,
              'values': ['second', 'third'],
              'default': 'third',
            }),
          );
          expect(flow.closes, 1);
          expect(flow.validations, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          flow.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'T153 profile numeric select-all delete remains editable at $scale',
      (tester) async {
        _frame(tester, scale);
        final semantics = tester.ensureSemantics();
        final flow = _ProfileFlow(
          ' \n${jsonEncode(_body({'type': 'integer', 'minimum': 0, 'maximum': 100, 'default': 10}))}\t',
        );
        final original = flow.body.text;
        final name = flow.name.text, description = flow.description.text;
        try {
          await tester.pumpWidget(flow.app(scale));
          await tester.pumpAndSettle();
          await _tap(tester, find.widgetWithText(TextButton, 'Параметры'));
          expect(flow.body.text, original);
          final numericState = _editingState(tester, _field('Минимум'));
          final numericController = tester
              .widget<TextField>(_field('Минимум'))
              .controller;
          await _selectAllDelete(tester, _field('Минимум'));
          expect(_field('Минимум'), findsOneWidget);
          expect(_editingState(tester, _field('Минимум')), same(numericState));
          expect(
            tester.widget<TextField>(_field('Минимум')).controller,
            same(numericController),
          );
          expect(numericState.widget.focusNode.hasFocus, isTrue);
          expect(
            tester.widget<TextField>(_field('Минимум')).controller!.text,
            isEmpty,
          );
          final pending =
              ((jsonDecode(flow.body.text) as Map)['parameters']
                      as Map)['choice']
                  as Map;
          expect(pending['minimum'], '');
          expect(
            find.bySemanticsLabel(
              RegExp('Структура JSON.*parameters.choice.minimum'),
            ),
            findsWidgets,
          );
          // The same active IME can repair the draft without another tap or
          // tester.enterText (which would silently reacquire lost focus).
          tester.testTextInput.enterText('2');
          await tester.pumpAndSettle();
          expect(_editingState(tester, _field('Минимум')), same(numericState));
          expect(numericState.widget.focusNode.hasFocus, isTrue);
          expect(
            tester.widget<TextField>(_field('Минимум')).controller,
            same(numericController),
          );
          await _selectAllDelete(tester, _field('Минимум'));
          await _tap(
            tester,
            find.widgetWithText(OutlinedButton, 'Сохранить версию'),
          );
          expect(flow.writes, 0);
          expect(flow.closes, 0);
          expect(flow.name.text, name);
          expect(flow.description.text, description);
          await _replace(tester, _field('Минимум'), '2');
          expect(flow.writes, 0);
          await _tap(
            tester,
            find.widgetWithText(OutlinedButton, 'Сохранить версию'),
          );
          expect(flow.writes, 1);
          expect(
            flow.written,
            _body({
              'type': 'integer',
              'minimum': 2,
              'maximum': 100,
              'default': 10,
            }),
          );
          expect(flow.closes, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          flow.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'T153 delegation range select-all delete remains editable at $scale',
      (tester) async {
        _frame(tester, scale);
        final semantics = tester.ensureSemantics();
        final flow = _DelegationFlow({
          'type': 'integer',
          'minimum': 0,
          'maximum': 100,
        });
        final original = flow.input.text;
        try {
          await tester.pumpWidget(flow.app(scale));
          await tester.pumpAndSettle();
          expect(flow.input.text, original);
          final numericState = _editingState(tester, _field('Минимум'));
          final numericController = tester
              .widget<TextField>(_field('Минимум'))
              .controller;
          await _selectAllDelete(tester, _field('Минимум'));
          expect(_field('Минимум'), findsOneWidget);
          expect(_editingState(tester, _field('Минимум')), same(numericState));
          expect(
            tester.widget<TextField>(_field('Минимум')).controller,
            same(numericController),
          );
          expect(numericState.widget.focusNode.hasFocus, isTrue);
          expect(
            tester.widget<TextField>(_field('Минимум')).controller!.text,
            isEmpty,
          );
          expect(flow.predicate['minimum'], '');
          expect(
            find.bySemanticsLabel(
              RegExp('Структура JSON.*predicates.choice.minimum'),
            ),
            findsWidgets,
          );
          tester.testTextInput.enterText('5');
          await tester.pumpAndSettle();
          expect(_editingState(tester, _field('Минимум')), same(numericState));
          expect(numericState.widget.focusNode.hasFocus, isTrue);
          expect(
            tester.widget<TextField>(_field('Минимум')).controller,
            same(numericController),
          );
          await _selectAllDelete(tester, _field('Минимум'));
          await _tap(tester, find.widgetWithText(FilledButton, 'Продолжить'));
          expect(flow.writes, 0);
          expect(flow.closes, 0);
          await _replace(tester, _field('Минимум'), '5');
          expect(flow.writes, 0);
          await _tap(tester, find.widgetWithText(FilledButton, 'Продолжить'));
          expect(flow.writes, 1);
          expect(flow.written!['predicates'], {
            'choice': {'type': 'integer', 'minimum': 5, 'maximum': 100},
          });
          expect(flow.closes, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          flow.dispose();
          semantics.dispose();
        }
      },
    );

    for (final boundary in ['duplicate', 'oversized']) {
      testWidgets('T153 profile $boundary enum keeps source editor at $scale', (
        tester,
      ) async {
        _frame(tester, scale);
        final flow = _ProfileFlow(jsonEncode(_body(_validEnum)));
        final name = flow.name.text, description = flow.description.text;
        final values = boundary == 'duplicate'
            ? ['first', 'first']
            : ['first', for (var i = 1; i <= 32; i++) 'value$i'];
        try {
          await tester.pumpWidget(flow.app(scale));
          await tester.pumpAndSettle();
          await _tap(tester, find.widgetWithText(TextButton, 'Параметры'));
          final sourceField = _field(
            'Допустимые значения (по одному на строку)',
          );
          final editor = _editingState(tester, sourceField);
          await _replace(tester, sourceField, values.join('\n'));
          expect(sourceField, findsOneWidget);
          expect(_editingState(tester, sourceField), same(editor));
          expect(editor.widget.focusNode.hasFocus, isTrue);
          final invalidDraft = flow.body.text;
          expect(
            (((jsonDecode(invalidDraft) as Map)['parameters'] as Map)['choice']
                as Map)['values'],
            values,
          );
          expect(
            find.byType(MotionDropdown<String>),
            findsOneWidget,
            reason: 'Only the Type dropdown is safe; the ambiguous/default selector is withheld.',
          );
          expect(find.textContaining('Выбор недоступен'), findsOneWidget);
          await _tap(
            tester,
            find.widgetWithText(OutlinedButton, 'Сохранить версию'),
          );
          expect(flow.body.text, invalidDraft);
          expect(flow.name.text, name);
          expect(flow.description.text, description);
          expect(flow.writes, 0);
          expect(flow.closes, 0);
          await _replace(tester, sourceField, 'first\nsecond');
          await _tap(
            tester,
            find.widgetWithText(OutlinedButton, 'Сохранить версию'),
          );
          expect(flow.writes, 1);
          expect(flow.written, _body(_validEnum));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          flow.dispose();
        }
      });
    }

    testWidgets('T153 delegation int enum numeric intermediates at $scale', (
      tester,
    ) async {
      _frame(tester, scale);
      final flow = _DelegationFlow({
        'type': 'enum',
        'values': [1, 2],
      });
      try {
        await tester.pumpWidget(flow.app(scale));
        await tester.pumpAndSettle();
        final first = _editingState(tester, _field('Значение 1'));
        final second = _editingState(tester, _field('Значение 2'));
        await _selectAllDelete(tester, _field('Значение 1'));
        expect(flow.predicate['values'], ['', 2]);
        expect(_editingState(tester, _field('Значение 1')), same(first));
        expect(first.widget.focusNode.hasFocus, isTrue);
        await _selectAllDelete(tester, _field('Значение 2'));
        expect(flow.predicate['values'], ['', '']);
        expect(_editingState(tester, _field('Значение 2')), same(second));
        expect(second.widget.focusNode.hasFocus, isTrue);
        await _tap(tester, find.widgetWithText(FilledButton, 'Продолжить'));
        expect(flow.writes, 0);
        expect(flow.closes, 0);
        await _replace(tester, _field('Значение 2'), '3');
        expect(flow.predicate['values'], ['', 3]);
        await _replace(tester, _field('Значение 1'), '4');
        expect(flow.predicate['values'], [4, 3]);
        expect(
          (flow.predicate['values'] as List).every((value) => value is int),
          isTrue,
        );
        expect(flow.writes, 0);
        await _tap(tester, find.widgetWithText(FilledButton, 'Продолжить'));
        expect(flow.writes, 1);
        expect(flow.written!['predicates'], {
          'choice': {
            'type': 'enum',
            'values': [4, 3],
          },
        });
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        flow.dispose();
      }
    });

    testWidgets(
      'T153 delegation external raw enum replacement resets numeric controls at $scale',
      (tester) async {
        _frame(tester, scale);
        final flow = _DelegationFlow({
          'type': 'enum',
          'values': [1, 2],
        });
        try {
          await tester.pumpWidget(flow.app(scale));
          await tester.pumpAndSettle();
          await _selectAllDelete(tester, _field('Значение 1'));
          expect(flow.predicate['values'], ['', 2]);
          await _tap(tester, find.text('JSON · дополнительные сведения'));
          final rawField = find.byWidgetPredicate(
            (widget) =>
                widget is TextField && identical(widget.controller, flow.input),
          );
          final replacement =
              ' \n${jsonEncode({
                'lifetimeSeconds': 3600,
                'predicates': {
                  'choice': {
                    'type': 'enum',
                    'values': ['1', '2'],
                  },
                },
              })}\t';
          await _replace(tester, rawField, replacement);
          expect(flow.input.text, replacement);
          expect(flow.predicate['values'], ['1', '2']);
          expect(flow.writes, 0);
          await _replace(tester, _field('Значение 1'), '3');
          expect(flow.predicate['values'], ['3', '2']);
          expect(
            (flow.predicate['values'] as List).every(
              (value) => value is String,
            ),
            isTrue,
          );
          await _tap(tester, find.widgetWithText(FilledButton, 'Продолжить'));
          expect(flow.writes, 1);
          expect(flow.written!['predicates'], {
            'choice': {
              'type': 'enum',
              'values': ['3', '2'],
            },
          });
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          flow.dispose();
        }
      },
    );

    for (final operation in ['remove', 'reorder', 'rename']) {
      testWidgets(
        'T153 scalar intent stays with predicate after external $operation at $scale',
        (tester) async {
          _frame(tester, scale);
          final flow = _DelegationFlow({
            'type': 'enum',
            'values': [1, 2],
          });
          const stringPredicate = {
            'type': 'enum',
            'values': ['', ''],
          };
          flow.input.text = jsonEncode({
            'lifetimeSeconds': 3600,
            'predicates': {
              'choice': {
                'type': 'enum',
                'values': [1, 2],
              },
              'other': stringPredicate,
            },
          });
          try {
            await tester.pumpWidget(flow.app(scale));
            await tester.pumpAndSettle();
            final group = tester.widget<Padding>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Padding &&
                    widget.child is DeckPanel &&
                    (widget.child! as DeckPanel).title == 'Параметр choice' &&
                    widget.key != null,
              ),
            );
            expect(group.key.toString(), isNot(contains('lifetimeSeconds')));
            expect(group.key.toString(), isNot(contains('predicates')));
            await _selectAllDelete(
              tester,
              _predicateField('choice', 'Значение 1'),
            );
            await _selectAllDelete(
              tester,
              _predicateField('choice', 'Значение 2'),
            );
            expect(flow.predicate['values'], ['', '']);
            await _tap(tester, find.text('JSON · дополнительные сведения'));
            final rawField = find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  identical(widget.controller, flow.input),
            );
            final replacement =
                ' \n${jsonEncode({
                  'lifetimeSeconds': 3600,
                  'predicates': {if (operation == 'rename') 'renamed': stringPredicate else 'other': stringPredicate, if (operation == 'reorder') 'choice': stringPredicate},
                })}\t';
            await _replace(tester, rawField, replacement);
            expect(flow.input.text, replacement);
            expect(flow.writes, 0);
            final target = operation == 'rename' ? 'renamed' : 'other';
            await _replace(tester, _predicateField(target, 'Значение 1'), '3');
            final predicates =
                (jsonDecode(flow.input.text) as Map)['predicates'] as Map;
            expect((predicates[target] as Map)['values'], ['3', '']);
            expect(
              ((predicates[target] as Map)['values'] as List).first,
              isA<String>(),
            );
            expect(flow.writes, 0);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            flow.dispose();
          }
        },
      );
    }

    for (final entry in invalidDefinitions.entries) {
      testWidgets('T149 profile ${entry.key} at $scale', (tester) async {
        _frame(tester, scale);
        final semantics = tester.ensureSemantics();
        final source = ' \n${jsonEncode(_body(entry.value))}\n\t';
        final flow = _ProfileFlow(source);
        final originalName = flow.name.text;
        final originalDescription = flow.description.text;
        try {
          await tester.pumpWidget(flow.app(scale));
          await tester.pumpAndSettle();
          await _tap(tester, find.widgetWithText(TextButton, 'Параметры'));
          expect(tester.takeException(), isNull);
          final issue = find.byKey(
            const ValueKey('automation-structured-shape-error'),
          );
          expect(issue, findsOneWidget);
          await tester.ensureVisible(issue);
          await tester.pumpAndSettle();
          expect(
            find.bySemanticsLabel(RegExp('Структура JSON.*parameters.choice')),
            findsWidgets,
          );
          expect(find.textContaining('Исправьте JSON'), findsOneWidget);
          final input = find.byWidgetPredicate(
            (widget) =>
                widget is TextField && identical(widget.controller, flow.body),
          );
          expect(
            input,
            findsOneWidget,
            reason: 'The original JSON remains editable.',
          );
          await _tap(
            tester,
            find.widgetWithText(OutlinedButton, 'Сохранить версию'),
          );
          expect(flow.writes, 0);
          expect(flow.closes, 0);
          expect(flow.validations, 0);
          expect(flow.changes, 0);
          expect(flow.name.text, originalName);
          expect(flow.description.text, originalDescription);
          expect(flow.body.text, source);
          expect(
            flow.submission.error,
            automationDraftInputError(profileBody: true),
          );
          expect(
            tester.widget<TextField>(input).decoration!.errorText,
            automationDraftInputError(profileBody: true),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          flow.dispose();
          semantics.dispose();
        }
      });
    }

    testWidgets('T149 explicit raw JSON repair restores typed enum at $scale', (
      tester,
    ) async {
      _frame(tester, scale);
      final flow = _ProfileFlow(
        jsonEncode(
          _body({
            ..._validEnum,
            'values': [1],
          }),
        ),
      );
      try {
        await tester.pumpWidget(flow.app(scale));
        await tester.pumpAndSettle();
        await _tap(tester, find.widgetWithText(TextButton, 'Параметры'));
        expect(tester.takeException(), isNull);
        expect(flow.writes, 0);
        final input = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && identical(widget.controller, flow.body),
        );
        await tester.ensureVisible(input);
        final repaired = ' \n${jsonEncode(_body(_validEnum))}\n';
        await tester.enterText(input, repaired);
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('automation-structured-shape-error')),
          findsNothing,
        );
        expect(find.byType(MotionDropdown<String>), findsNWidgets(2));
        expect(flow.body.text, repaired);
        expect(flow.changes, 1);
        expect(flow.writes, 0);
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, 'Сохранить версию'),
        );
        expect(flow.writes, 1);
        expect(flow.written, _body(_validEnum));
        expect(flow.closes, 1);
        expect(flow.validations, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        flow.dispose();
      }
    });

    for (final values in <List<Object?>>[
      [1, 2],
      [false, true],
      ['first', 'second'],
    ]) {
      testWidgets(
        'T149 delegation preserves supported scalar enum $values at $scale',
        (tester) async {
          _frame(tester, scale);
          final source =
              ' \n${jsonEncode({
                'lifetimeSeconds': 3600,
                'predicates': {
                  'choice': {'type': 'enum', 'values': values},
                },
              })}\t';
          final input = TextEditingController(text: source);
          var changes = 0;
          try {
            await tester.pumpWidget(
              _host(
                SingleChildScrollView(
                  child: AutomationStructuredDraft(
                    input: input,
                    enabled: true,
                    onChanged: (_) => changes++,
                  ),
                ),
                scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('automation-structured-shape-error')),
              findsNothing,
            );
            expect(find.text('Разрешённые точные значения'), findsOneWidget);
            expect(input.text, source);
            expect(changes, 0);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            input.dispose();
          }
        },
      );
    }

    for (final values in <Object?>[
      [],
      [null],
      [
        [1],
      ],
      [
        {'x': 1},
      ],
      [true, 1],
      null,
    ]) {
      testWidgets(
        'T149 invalid delegation enum ${jsonEncode(values)} at $scale',
        (tester) async {
          _frame(tester, scale);
          final source =
              ' \n${jsonEncode({
                'lifetimeSeconds': 3600,
                'predicates': {
                  'choice': {'type': 'enum', 'values': values},
                },
              })}\t';
          final input = TextEditingController(text: source);
          var changes = 0;
          try {
            await tester.pumpWidget(
              _host(
                SingleChildScrollView(
                  child: AutomationStructuredDraft(
                    input: input,
                    enabled: true,
                    onChanged: (_) => changes++,
                  ),
                ),
                scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('automation-structured-shape-error')),
              findsOneWidget,
            );
            expect(find.textContaining('predicates.choice'), findsOneWidget);
            expect(input.text, source);
            expect(changes, 0);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            input.dispose();
          }
        },
      );
    }

    final invalidGrants = <String, Map<String, Object?>>{
      'scopes': {
        'scopes': ['read', 1],
      },
      'serverIds': {
        'serverIds': [
          {'id': 'target'},
        ],
      },
      'duplicate scopes': {
        'scopes': ['read', 'read'],
      },
      'lifetimeSeconds': {'lifetimeSeconds': '3600'},
      'label': {
        'label': {'text': 'Client'},
      },
    };
    for (final entry in invalidGrants.entries) {
      testWidgets('T149 grant ${entry.key} stays exact at $scale', (
        tester,
      ) async {
        _frame(tester, scale);
        final source =
            ' \n${jsonEncode({
              'label': 'Client',
              'scopes': ['read'],
              'serverIds': <String>[],
              'lifetimeSeconds': 3600,
              ...entry.value,
            })}\t';
        final input = TextEditingController(text: source);
        var changes = 0;
        try {
          await tester.pumpWidget(
            _host(
              SingleChildScrollView(
                child: AutomationStructuredDraft(
                  input: input,
                  enabled: true,
                  onChanged: (_) => changes++,
                ),
              ),
              scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('automation-structured-shape-error')),
            findsOneWidget,
          );
          expect(input.text, source);
          expect(changes, 0);
          expect(
            find.byType(AutomationDraftSelectionField),
            entry.key == 'lifetimeSeconds' ? findsNWidgets(2) : findsNothing,
            reason: 'A safely editable numeric intermediate keeps the unchanged target/scope controls.',
          );
          if (entry.key == 'lifetimeSeconds') {
            expect(
              tester.widget<TextField>(_field('Срок, секунд')).controller!.text,
              '3600',
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          input.dispose();
        }
      });
    }

    for (final missing in ['lifetimeSeconds', 'label']) {
      testWidgets('T149 partial grant missing $missing at $scale', (
        tester,
      ) async {
        _frame(tester, scale);
        final target = DesignServerFixtures.profile();
        final partial = <String, Object?>{
          'label': 'Client',
          'scopes': ['read'],
          'serverIds': [target.id],
          'lifetimeSeconds': 3600,
        }..remove(missing);
        final source = ' \n${jsonEncode(partial)}\t';
        final input = TextEditingController(text: source);
        var changes = 0;
        try {
          await tester.pumpWidget(
            _host(
              SingleChildScrollView(
                child: AutomationStructuredDraft(
                  input: input,
                  enabled: true,
                  serverProfiles: [target],
                  onChanged: (_) => changes++,
                ),
              ),
              scale,
            ),
          );
          await tester.pumpAndSettle();
          final selected = find.text(
            '${target.name} · ${target.address}:${target.port}',
          );
          expect(selected, findsOneWidget);
          await tester.ensureVisible(selected);
          await tester.pumpAndSettle();
          expect(selected.hitTestable(), findsOneWidget);
          expect(
            find.byKey(const ValueKey('automation-structured-shape-error')),
            findsNothing,
          );
          final emptyField = find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.key ==
                    ValueKey(
                      'automation-field-${missing == 'label' ? 'Клиент' : 'Срок, секунд'}',
                    ),
          );
          expect(
            tester.widget<TextField>(emptyField).controller!.text,
            isEmpty,
          );
          expect(input.text, source);
          expect((jsonDecode(input.text) as Map).containsKey(missing), isFalse);
          expect(changes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          input.dispose();
        }
      });
    }

    for (final definition in <Object?>[
      ['enum'],
      {
        ..._validEnum,
        'values': [1],
      },
      {..._validEnum, 'default': false},
    ]) {
      testWidgets(
        'T149 parameter input rejects corrupt definition ${jsonEncode(definition)} at $scale',
        (tester) async {
          _frame(tester, scale);
          const source = ' \n{"choice":"first"}\t';
          final input = TextEditingController(text: source);
          var changes = 0;
          try {
            await tester.pumpWidget(
              _host(
                SingleChildScrollView(
                  child: AutomationStructuredDraft(
                    input: input,
                    enabled: true,
                    parameterDefinitions: {'choice': definition},
                    onChanged: (_) => changes++,
                  ),
                ),
                scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('automation-structured-shape-error')),
              findsOneWidget,
            );
            expect(find.byType(MotionDropdown<String>), findsNothing);
            expect(input.text, source);
            expect(changes, 0);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            input.dispose();
          }
        },
      );
    }
  }
}
