import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/profiles/mutation_controller.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;

import 'support/design_scenarios.dart';

Map<String, List<String>> _mapRows(String source) => {
  for (final line in source.split('\n'))
    if (RegExp(r'^\| `\d\d-[^`]+`').hasMatch(line))
      RegExp(r'`([^`]+)`').firstMatch(line)!.group(1)!: line
          .split('|')
          .skip(1)
          .take(line.split('|').length - 2)
          .map((cell) => cell.trim())
          .toList(),
};

List<String> _expandRequirements(String source, String kind) {
  final values = <String>{};
  for (final match in RegExp(
    '\\b$kind-[A-Z0-9-]+(?:/[A-Z0-9]+)*',
  ).allMatches(source)) {
    final parts = match.group(0)!.split('/');
    values.add(parts.first);
    final prefix = parts.first.substring(0, parts.first.lastIndexOf('-') + 1);
    values.addAll(parts.skip(1).map((part) => '$prefix$part'));
  }
  return values.toList();
}

void main() {
  final registry = (jsonDecode(
    File('docs/design/screens.json').readAsStringSync(),
  ) as List).cast<Map<String, Object?>>();
  final mapSource = File('specs/003-design-system/screen-map.md')
      .readAsStringSync();
  final historicalMap = mapSource
      .split('## Историческая карта 003.1–003.3')
      .last;
  final currentMap = mapSource.split('## Историческая карта 003.1–003.3').first;
  final rows = _mapRows(historicalMap);
  final taskSource = File('specs/003-design-system/tasks.md')
      .readAsStringSync();
  final taskIds = RegExp(
    r'^- \[[ X]\] (T\d{3})\b',
    multiLine: true,
  ).allMatches(taskSource).map((match) => match.group(1)!).toSet();

  test('historical98 registry remains35origins63concepts without claiming current acceptance', () {
    final ids = registry.map((row) => row['id'] as String).toList();
    final originIds = registry
        .where((row) => row['implemented'] == true)
        .map((row) => row['id'] as String)
        .toSet();
    final conceptIds = registry
        .where((row) => row['implemented'] == false)
        .map((row) => row['id'] as String)
        .toSet();
    expect(ids, hasLength(98));
    expect(ids.toSet(), hasLength(98));
    expect(originIds, hasLength(35));
    expect(conceptIds, hasLength(63));
    expect(rows.keys.toSet(), ids.toSet());
    // Check the physical rows as well: a map alone would hide duplicates.
    expect(
      RegExp(r'^\| `\d\d-[^`]+`', multiLine: true).allMatches(historicalMap),
      hasLength(98),
    );
    expect(designBindings, hasLength(35));
    expect(
      designBindings.map((binding) => binding.screenId).toSet(),
      originIds,
    );
    expect(designConcepts, hasLength(63));
    expect(
      designConcepts.map((concept) => concept.screenId).toSet(),
      conceptIds,
    );
    expect(designBindings.map((binding) => binding.group).toSet(), {
      for (var i = 1; i <= 12; i++) 'A${i.toString().padLeft(2, '0')}',
    });
  });

  test('current003 has37 unique base entries and61 future owners', () {
    final current = _mapRows(currentMap);
    expect(current, hasLength(37));
    final original = registry
        .where((row) => row['implemented'] == true)
        .map((row) => row['id'] as String)
        .toSet();
    expect(current.keys.toSet(), {
      ...original,
      '11-host-key-changed',
      '93-protected-effect-blocked',
    });
    expect(
      RegExp(r'^\| `\d\d-[^`]+`', multiLine: true).allMatches(currentMap),
      hasLength(37),
    );
    for (final row in current.values) {
      expect(row[5], contains('T13'));
      expect(row.last, contains('не проверено заново'));
    }
    final delivery = File('specs/design-delivery.md').readAsStringSync();
    final ownership = _mapRows(delivery);
    expect(ownership.keys.toSet(), registry.map((row) => row['id']).toSet());
  });

  for (final binding in designBindings) {
    test(
      'binding ${binding.screenId} retains owner requirement/task/state scope',
      () {
        final row = registry.singleWhere(
          (entry) => entry['id'] == binding.screenId,
        );
        final mapped = rows[binding.screenId]!;
        final sources = (row['source'] as String)
            .split(';')
            .map((source) => source.trim())
            .toList();
        expect(binding.sourceOwners, sources);
        expect(binding.ownerFile, sources.first);
        for (final source in sources) {
          expect(
            File(source).existsSync(),
            isTrue,
            reason: '${binding.screenId}: $source',
          );
          expect(
            mapped.join(' ').contains(source) ||
                mapped.join(' ').contains(source.replaceFirst('specs/', '../')),
            isTrue,
            reason: 'source owner $source must stay in the individual map row',
          );
        }
        expect(mapped[1], binding.group);
        expect(binding.ownerRequirement, mapped[3]);
        expect(binding.ownerFR, _expandRequirements(mapped[3], 'FR'));
        expect(binding.ownerAC, _expandRequirements(mapped[3], 'AC'));
        expect(binding.ownerFR, isNotEmpty);
        expect(binding.ownerAC, isNotEmpty);
        expect(
          binding.taskIds,
          RegExp(r'T\d{3}')
              .allMatches(mapped[5])
              .map((match) => match.group(0)!)
              .toList(),
        );
        expect(taskIds.containsAll(binding.taskIds), isTrue);
        expect(binding.taskIds, containsAll(['T005', 'T019', 'T029', 'T038']));
        expect(binding.states, isNotEmpty);
        expect(binding.states.toSet().length, binding.states.length);
        expect(binding.notApplicableReason, mapped[7]);
        expect(binding.notApplicableReason.length, greaterThan(20));
        expect(binding.productionWidgets, isNotEmpty);
        expect(
          binding.frames.map(
            (frame) => '${frame.width.toInt()}x${frame.height.toInt()}',
          ),
          ['1100x760', '800x600', '390x800', '360x800'],
        );
        expect(binding.themes, [ThemeMode.light, ThemeMode.dark]);
        expect(binding.scales, [1.0, 2.0]);
        expect(binding.command, contains(binding.screenId));
        expect(binding.command, contains(binding.verificationTest));
        expect(binding.result, 'not-run');
        // Descriptor metadata is separate from the completed map acceptance.
        expect(mapped[8], '`passed; scoped UI`');
        expect(binding.scope, contains('do not prove visual acceptance'));
      },
    );
  }

  test(
    '63 concepts keep source ownership and never acquire runtime acceptance',
    () {
      for (final concept in designConcepts) {
        final row = registry.singleWhere(
          (entry) => entry['id'] == concept.screenId,
        );
        expect(
          concept.sourceOwners,
          (row['source'] as String)
              .split(';')
              .map((source) => source.trim())
              .toList(),
        );
        for (final owner in concept.sourceOwners) {
          expect(File(owner).existsSync(), isTrue, reason: owner);
          expect(rows[concept.screenId]![1], contains(owner));
        }
        expect(concept.requirement, 'FR-003-LOCAL-09');
        expect(concept.acceptanceCriterion, 'AC-003-1B');
        expect(concept.taskIds, ['T003', 'T006']);
        expect(concept.result, 'not-runtime-accepted');
        expect(rows[concept.screenId]!.last, contains('not-runtime-accepted'));
      }
    },
  );

  test(
    'server and automation live panels consume the shared production classes',
    () {
      for (final family in ['servers/server', 'automation/automation']) {
        final panel = File('lib/${family}_panel.dart').readAsStringSync();
        final sections = File('lib/${family}_sections.dart').readAsStringSync();
        final leaf = family.split('/').last;
        expect(panel, contains("import '${leaf}_sections.dart'"));
        var liveOwners = panel;
        if (family == 'servers/server') {
          // The workspace owns target selection and passes its real selector
          // into the panel's log filter region; the panel owns log operations.
          final workspace = File('lib/shell/base_workspace.dart')
              .readAsStringSync();
          expect(
            workspace,
            contains("import '../servers/server_sections.dart'"),
          );
          expect(
            RegExp(
              r'Widget _logTargetSelector\(\) => ServerLogTargetSelector\(',
            ).hasMatch(workspace),
            isTrue,
          );
          expect(
            RegExp(
              r'contextBar:\s*_section == FoundationSection\.logs\s*\? _logTargetSelector\(\)\s*:\s*null',
            ).hasMatch(workspace),
            isTrue,
          );
          expect(
            RegExp(r'targetSelector:\s*widget\.contextBar').hasMatch(panel),
            isTrue,
          );
          liveOwners = '$panel\n$workspace';
        }
        final declarations = RegExp(
          r'class (_?(?:Server|Automation)\w+) extends (?:StatelessWidget|StatefulWidget|State<[^>]+>)',
        ).allMatches(sections).toList();
        final classes = declarations.map((match) => match.group(1)!).toList();
        expect(classes, isNotEmpty);
        // Some retained components also own shared target resolution/address
        // helpers. Their actual static calls are production consumption too.
        bool referencesClass(String source, String name) =>
            RegExp('\\b${RegExp.escape(name)}\\s*(?:\\(|\\.)').hasMatch(source);
        final reachable = {
          for (final name in classes)
            if (referencesClass(liveOwners, name)) name,
        };
        var changed = true;
        while (changed) {
          changed = false;
          for (var i = 0; i < classes.length; i++) {
            if (!reachable.contains(classes[i])) continue;
            final body = sections.substring(
              declarations[i].start,
              i + 1 == classes.length
                  ? sections.length
                  : declarations[i + 1].start,
            );
            for (final dependency in classes) {
              if (referencesClass(body, dependency) &&
                  reachable.add(dependency)) {
                changed = true;
              }
            }
          }
        }
        for (final name in classes) {
          expect(
            reachable,
            contains(name),
            reason: '$name must be reachable from its live owner',
          );
        }
      }
    },
  );

  test(
    'runtime imports cannot reach the visual catalogue or test fixtures',
    () {
      final directives = RegExp(
        r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
        multiLine: true,
      );
      final forbidden = RegExp(
        r'docs/design|screens\.json|ServerDeck-design|design_scenarios|test/support|demo|fixture',
        caseSensitive: false,
      );
      for (final directory in [Directory('lib'), Directory('packages')]) {
        for (final file
            in directory
                .listSync(recursive: true)
                .whereType<File>()
                .where(
                  (file) =>
                      file.path.endsWith('.dart') &&
                      !file.path.replaceAll('\\', '/').contains('/test/'),
                )) {
          for (final directive in directives.allMatches(
            file.readAsStringSync(),
          )) {
            expect(
              forbidden.hasMatch(directive.group(1)!),
              isFalse,
              reason: '${file.path}: ${directive.group(1)}',
            );
          }
        }
      }
    },
  );

  // This is a construction smoke check, not T019 visual/semantics acceptance.
  // It requires every declared origin to mount actual production widgets. The
  // later stages assert design behavior, states, frame matrices and captures.
  for (final binding in designBindings) {
    testWidgets('production fixture construction ${binding.screenId}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = await DesignScenarioHarness.create(
        screenId: binding.screenId,
      );
      try {
        final widget = binding.build(harness);
        final boundedOwner =
            binding.group == 'A01' ||
            binding.group == 'A02' ||
            binding.group == 'A04' ||
            binding.group == 'A12' ||
            widget is AutomationJsonEditorDialog ||
            widget is AutomationProfileEditorDialog ||
            widget is AutomationPlanDecisionDialog ||
            widget is ServerConfirmationDialog ||
            widget is ServerLogRecordDialog;
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.light,
            home: Scaffold(
              body: boundedOwner
                  ? widget
                  : SingleChildScrollView(child: widget),
            ),
          ),
        );
        await tester.pump();
        for (final name in binding.productionWidgets) {
          expect(
            find.byWidgetPredicate(
              (widget) => widget.runtimeType.toString() == name,
            ),
            findsWidgets,
            reason: '${binding.screenId}: actual $name',
          );
        }
        expect(
          harness.client.mutations,
          binding.screenId == '13-mutation-conflict' ? hasLength(1) : isEmpty,
        );
        expect(harness.counters.values, isEmpty);
        expect(binding.result, 'not-run');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.close();
      }
    });
  }

  test(
    'defensive history fixtures preserve bounds, values and source order',
    () {
      for (final count in [0, 1, 120]) {
        expect(DesignServerFixtures.history(count: count), hasLength(count));
      }
      final points = DesignServerFixtures.history(
        count: 5,
        overrides: {
          0: {
            'cpuPercent': 0,
            'memoryUsedPercent': 100,
            'rootDiskUsedPercent': null,
          },
          1: {
            'cpuPercent': -1,
            'memoryUsedPercent': 101,
            'rootDiskUsedPercent': 1.5,
          },
          2: {'receivedAt': '2026-10-25T09:00:15.000Z'},
          3: {'receivedAt': '2026-10-25T09:00:15.000Z'},
          4: {'receivedAt': '2026-10-25T09:00:00.000Z'},
        },
      );
      expect((points[0] as Map)['cpuPercent'], 0);
      expect((points[0] as Map)['memoryUsedPercent'], 100);
      expect((points[0] as Map)['rootDiskUsedPercent'], isNull);
      expect((points[1] as Map)['rootDiskUsedPercent'], 1.5);
      expect(
        (points[2] as Map)['receivedAt'],
        (points[3] as Map)['receivedAt'],
      );
      expect((points[4] as Map)['receivedAt'], DesignServerFixtures.observedAt);
      for (final gap in [15000, 15001]) {
        final history = DesignServerFixtures.history(
          count: 2,
          interval: Duration(milliseconds: gap),
        );
        final first = DateTime.parse(
          (history.first as Map)['receivedAt'] as String,
        );
        final last = DateTime.parse(
          (history.last as Map)['receivedAt'] as String,
        );
        expect(last.difference(first).inMilliseconds, gap);
      }
      final stale = DesignServerFixtures.state(stale: true);
      expect((stale['metrics'] as Map)['stale'], isTrue);
      expect(() => DesignServerFixtures.history(count: 121), throwsRangeError);
    },
  );

  test('harness supports late readiness snapshots, delayed picker and mutation gates', () async {
    final harness = await DesignScenarioHarness.create(
      screenId: '13-mutation-conflict',
      options: const DesignFixtureOptions(busy: true, delayed: true),
    );
    try {
      expect(harness.mutation.state, MutationPresentation.submitting);
      expect(harness.client.mutations, hasLength(1));
      expect(harness.pickerGate!.isCompleted, isFalse);
      expect(harness.client.recentGate!.isCompleted, isFalse);
      harness.showReadiness(ReadinessState.storageBlocked);
      expect(harness.profiles.profiles, isEmpty);
      harness.publishSnapshot(revision: '2');
      expect(harness.profiles.loaded, isFalse);
      expect(harness.profiles.profiles, isEmpty);
      harness.showReadiness(ReadinessState.ready);
      harness.publishSnapshot(revision: '3');
      expect(harness.profiles.loaded, isTrue);
      expect(harness.profiles.storeRevision, '3');
      expect(harness.client.mutations, hasLength(1));
      expect(
        () => harness.buildOrigin('11-host-key-changed'),
        throwsArgumentError,
      );
    } finally {
      await harness.close();
    }
  });
}
