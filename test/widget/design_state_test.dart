import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/design_automation_state_cases.dart';
import '../support/design_foundation_state_cases.dart';
import '../support/design_scenarios.dart';
import '../support/design_server_state_cases.dart';

/// Planned-contract checks plus the actual production providers implemented so
/// far. Missing families remain not-run in external evidence, never implicit pass.
void main() {
  group('T033 planned state registry structure', () {
    test('exact 35 origin bindings and 420 explicit typed cells', () {
      final origins = designStateOrigins.map((item) => item.originId).toList();
      expect(origins, hasLength(35));
      expect(origins.toSet(), hasLength(35));
      expect(
        origins.toSet(),
        designBindings.map((item) => item.screenId).toSet(),
      );
      for (final binding in designBindings) {
        expect(binding.stateApplicability.originId, binding.screenId);
      }
      expect(DesignStateCategory.values, hasLength(12));
      var cells = 0;
      for (final origin in designStateOrigins) {
        expect(origin.cells.keys.toSet(), DesignStateCategory.values.toSet());
        expect(origin.cells, hasLength(12));
        cells += origin.cells.length;
        for (final cell in origin.cells.values) {
          expect(
            cell,
            anyOf(
              isA<DesignStateApplicable>(),
              isA<DesignStateNotApplicable>(),
            ),
          );
        }
      }
      expect(cells, 420);
    });

    test('every applicable cell has unique planned matching case IDs', () {
      final ids = <String>{};
      final referenced = <String>{};
      for (final scenario in designStateCases) {
        expect(
          scenario.caseId,
          matches(RegExp(r'^state-[0-9]{2}-[a-z0-9-]+-[a-zA-Z]+$')),
        );
        expect(ids.add(scenario.caseId), isTrue, reason: scenario.caseId);
        expect(
          scenario.caseId,
          'state-${scenario.originId}-${scenario.category.name}',
        );
        expect(scenario.result, DesignStateResult.notRun);
        expect(scenario.command, contains(scenario.caseId));
        expect(
          scenario.verificationTest,
          scenario.taskId == 'T037'
              ? 'test/widget/design_privacy_test.dart'
              : 'test/widget/design_state_test.dart',
        );
        expect(scenario.limitation, contains('do not execute'));
      }
      for (final origin in designStateOrigins) {
        for (final entry in origin.cells.entries) {
          if (entry.value case DesignStateApplicable(:final caseIds)) {
            expect(caseIds, isNotEmpty);
            expect(caseIds.toSet(), hasLength(caseIds.length));
            for (final id in caseIds) {
              expect(referenced.add(id), isTrue, reason: id);
              final scenario = designStateCasesById[id];
              expect(scenario, isNotNull, reason: id);
              expect(scenario!.originId, origin.originId);
              expect(scenario.category, entry.key);
            }
          }
        }
      }
      expect(referenced, ids);
      expect(designStateCasesById, hasLength(ids.length));
    });

    test('all production anchors exist and N/A has a specific reason', () {
      final sources = <DesignStateSource>[];
      final reasons = <String>{};
      for (final origin in designStateOrigins) {
        for (final cell in origin.cells.values) {
          if (cell case DesignStateNotApplicable(
            :final reason,
            :final source,
          )) {
            expect(reason, contains(origin.originId));
            expect(reason.length, greaterThan(100));
            expect(reason, isNot(matches(RegExp(r'\b(TBD|TODO)\b'))));
            reasons.add(reason);
            sources.add(source);
          }
        }
      }
      expect(reasons.length, greaterThan(20));
      for (final scenario in designStateCases) {
        expect(scenario.owner, isNotEmpty);
        expect(scenario.sources, isNotEmpty);
        expect(scenario.phase.length, greaterThan(30));
        expect(scenario.expectations, isNotEmpty);
        for (final expectation in scenario.expectations) {
          expect(expectation.length, greaterThan(30));
        }
        expect(scenario.taskId, isIn(['T034', 'T035', 'T036', 'T037']));
        sources.addAll(scenario.sources);
      }
      final fileCache = <String, String>{};
      for (final source in sources) {
        expect(source.path, matches(RegExp(r'^(lib|packages)/')));
        expect(source.path, isNot(contains('..')));
        expect(source.anchor.length, greaterThan(5));
        final file = File(source.path);
        expect(file.existsSync(), isTrue, reason: source.path);
        final text = fileCache.putIfAbsent(source.path, file.readAsStringSync);
        expect(
          text,
          contains(source.anchor),
          reason: '${source.path}: ${source.anchor}',
        );
      }
    });

    test('planned counter boundaries distinguish passive UI from intent', () {
      for (final scenario in designStateCases) {
        expect(scenario.passiveCounters, hasLength(3));
        expect(scenario.passiveCounters.map((item) => item.trigger), [
          'render',
          'theme-change',
          'resize',
        ]);
        for (final counter in scenario.passiveCounters) {
          expect(counter.counter, 'additionalUiInitiatedOwnerActions');
          expect(counter.expectedDelta, 0);
        }
        expect(scenario.actions, isNotEmpty);
        for (final action in scenario.actions) {
          expect(action.trigger, isNotEmpty);
          expect(action.counter, isNotEmpty);
          expect(action.expectedDelta, greaterThanOrEqualTo(0));
        }
        expect(
          scenario.limitation,
          contains('count existing lifecycle work separately'),
        );
        expect(scenario.limitation, contains('do not prove RPC identity'));
      }
    });

    test('legal unsupported errors apply to all nine verified owners', () {
      const verified = [
        '19-plan-approval',
        '27-job-list',
        '32-automation-profiles',
        '33-profile-authoring',
        '34-profile-revisions',
        '36-ai-grants',
        '37-ai-grant-form',
        '38-mcp-client-config',
        '39-delegations',
      ];
      for (final id in verified) {
        final origin = designStateOrigins.singleWhere(
          (item) => item.originId == id,
        );
        expect(origin.unsupported, isA<DesignStateApplicable>());
        final scenario = designStateCasesById['state-$id-unsupported']!;
        expect(scenario.phase, contains('outer TrustedLocalError UNSUPPORTED'));
        expect(
          scenario.sources.any(
            (item) =>
                item.path == 'packages/serverdeck_protocol/lib/host_trust.dart',
          ),
          isTrue,
        );
      }
    });

    test(
      'unknown writes, observation quality and bounds are not conflated',
      () {
        for (final scenario in designStateCases.where(
          (item) => item.category == DesignStateCategory.unknown,
        )) {
          expect(
            scenario.meaning,
            isIn([
              DesignStateMeaning.localMutation,
              DesignStateMeaning.trustWrite,
              DesignStateMeaning.automationWrite,
              DesignStateMeaning.jobOutcome,
            ]),
          );
          expect(scenario.meaning, isNot(DesignStateMeaning.remoteObservation));
        }
        final observation =
            designStateCasesById['state-06-server-overview-data']!;
        expect(observation.expectations.join(' '), contains('quality=unknown'));
        expect(
          observation.expectations.join(' '),
          contains('no unknown-write claim'),
        );
        for (final id in [
          '07-profile-create',
          '08-profile-edit',
          '09-profile-delete',
          '12-credential-input',
          '13-mutation-conflict',
          '85-settings-form',
        ]) {
          final row = designStateOrigins.singleWhere(
            (item) => item.originId == id,
          );
          expect(row.stale, isA<DesignStateNotApplicable>());
          expect(
            designStateCasesById['state-$id-validation']!.expectations.join(
              ' ',
            ),
            contains('CAS conflict'),
          );
        }
        expect(
          designStateCasesById['state-06-server-overview-dropped']!.expectations
              .join(' '),
          contains('120-sample cap alone is not dropped'),
        );
        expect(
          designStateCasesById['state-28-job-detail-dropped']!.expectations
              .join(' '),
          contains('200 events alone does not indicate dropped'),
        );
        final receiptRow = designStateOrigins.singleWhere(
          (item) => item.originId == '31-recent-operations',
        );
        expect(receiptRow.dropped, isA<DesignStateNotApplicable>());
        expect(receiptRow.unknown, isA<DesignStateNotApplicable>());
      },
    );

    test('execution metadata has no constructed or implicit pass', () {
      expect(designStateExecutionRecords, isEmpty);
      expect(
        designStateCases.every(
          (item) => item.result == DesignStateResult.notRun,
        ),
        isTrue,
      );
      expect(designBindings.every((item) => item.result == 'not-run'), isTrue);
      expect(
        designConcepts.every((item) => item.result == 'not-runtime-accepted'),
        isTrue,
      );
    });
  });
  registerDesignFoundationStateCases(fullAdaptive: true);
  registerDesignServerStateCases(fullAdaptive: true);
  registerDesignAutomationStateCases(fullAdaptive: true);
}
