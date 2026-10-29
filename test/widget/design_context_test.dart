import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/design_automation_fixtures.dart';
import '../support/design_server_fixtures.dart';

import 'package:serverdeck/app.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/servers/server_compositions.dart';
import 'package:serverdeck/settings/settings_form.dart';
import 'package:serverdeck/settings/settings_view.dart' as settings;
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as fixture;

class _CountingClient extends fixture.ModelClient {
  final reads = <ApiMethod>[];
  final writes = <MutationIntent>[];
  var connections = 0;
  var pollingSnapshots = 0;

  @override
  Future<void> connect() async => connections++;

  @override
  Future<ApiReply> read(
    ApiMethod method, [
    Map<String, Object?> params = const {},
  ]) {
    reads.add(method);
    return super.read(method, params);
  }

  @override
  Future<ApiReply> mutate(MutationIntent intent) async {
    writes.add(intent);
    throw const LocalApiException(ErrorCode.timeout);
  }

  void publish(ThemePreference theme, int revision) {
    pollingSnapshots++;
    final snapshot = fixture.snapshot(revision: '$revision');
    events.add(
      ClientSnapshot(
        snapshot.profiles,
        ApiReply(fixture.fixtureGeneration, {
          'storeRevision': '$revision',
          'settings': SettingsView(
            theme: theme,
            reduceMotion: true,
            selectedProfileId: fixture.profileId,
          ).toJson(),
        }),
      ),
    );
  }
}

void _view(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

Finder _field(String name) => find.byKey(ValueKey('profile-$name'));
Finder _editable(Finder owner) =>
    find.descendant(of: owner, matching: find.byType(EditableText));

Future<void> _expectRecordSemantics(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final widget = tester.widget(finder);
  final data = tester.getSemantics(finder).getSemanticsData();
  if (widget is EditableText) {
    expect(widget.readOnly, isTrue);
    expect(data.value, text);
    final row = find
        .ancestor(
          of: finder,
          matching: find.byWidgetPredicate(
            (widget) => widget.key is ServerFactRowKey,
          ),
        )
        .first;
    final label = find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            const [
              'Сервер',
              'Адрес',
              'Время',
              'Источник',
              'Наблюдение',
              'Служба',
              'Приоритет',
            ].contains(widget.data),
      ),
    );
    expect(label, findsOneWidget);
    expect(
      tester.getSemantics(label).getSemanticsData().label,
      contains(tester.widget<Text>(label).data!),
    );
  } else {
    expect(data.label, contains(text));
  }
}

ProfileView _logTarget({
  String id = DesignServerFixtures.serverId,
  String revision = '2',
  String name = 'Целевой сервер',
  String address = '192.0.2.1',
  int port = 22,
  String connectionRevision = '1',
  String credentialRevision = '1',
  String trustRevision = '2',
  List<String> tags = const [],
}) => ProfileView(
  id: id,
  revision: revision,
  name: name,
  address: address,
  port: port,
  sshUser: 'synthetic',
  tags: tags,
  credentialRevision: credentialRevision,
  connectionRevision: connectionRevision,
  trustRevision: trustRevision,
  createdAt: DesignServerFixtures.observedAt,
  updatedAt: DesignServerFixtures.observedAt,
  credentialKind: CredentialKind.password,
  credentialConfigured: true,
);

void _removeProfiles(_CountingClient client) {
  final snapshot = fixture.snapshot(revision: '2');
  final profiles = Map<String, Object?>.from(snapshot.profiles.result as Map)
    ..['profiles'] = <Object?>[];
  final settings = Map<String, Object?>.from(snapshot.settings.result as Map)
    ..['settings'] = const SettingsView(
      theme: ThemePreference.dark,
      reduceMotion: true,
    ).toJson();
  client.events.add(
    ClientSnapshot(
      ApiReply(fixture.fixtureGeneration, profiles),
      ApiReply(fixture.fixtureGeneration, settings),
    ),
  );
}

void main() {
  final identityProfile = _logTarget();
  final identityLogs = DesignServerFixtures.logs();
  final identityJson = identityLogs['identity'] as Map<String, Object?>;
  final identityCases = <String, (ProfileView, Map<String, Object?>?)>{
    'profile ID': (
      _logTarget(id: DesignServerFixtures.workspaceId),
      identityLogs,
    ),
    'server ID': (
      identityProfile,
      {...identityLogs, 'serverId': DesignServerFixtures.workspaceId},
    ),
    'identity profile ID': (
      identityProfile,
      {
        ...identityLogs,
        'identity': {
          ...identityJson,
          'profileId': DesignServerFixtures.workspaceId,
        },
      },
    ),
    'connection revision': (_logTarget(connectionRevision: '2'), identityLogs),
    'credential revision': (_logTarget(credentialRevision: '2'), identityLogs),
    'trust revision': (_logTarget(trustRevision: '3'), identityLogs),
    'missing logs': (identityProfile, null),
    'missing server ID': (identityProfile, {...identityLogs, 'serverId': null}),
    'missing identity': (identityProfile, {...identityLogs, 'identity': null}),
    'non-map identity': (
      identityProfile,
      {...identityLogs, 'identity': 'not an identity'},
    ),
    'missing identity fields': (
      identityProfile,
      {...identityLogs, 'identity': <String, Object?>{}},
    ),
    'extra identity fields': (
      identityProfile,
      {
        ...identityLogs,
        'identity': {...identityJson, 'unexpected': true},
      },
    ),
    'invalid identity UUID': (
      identityProfile,
      {
        ...identityLogs,
        'identity': {...identityJson, 'profileId': 'bad UUID'},
      },
    ),
    'noncanonical revision': (
      identityProfile,
      {
        ...identityLogs,
        'identity': {...identityJson, 'connectionRevision': '01'},
      },
    ),
    'invalid key': (
      identityProfile,
      {
        ...identityLogs,
        'identity': {
          ...identityJson,
          'key': {'algorithm': 'bad', 'fingerprint': 'bad'},
        },
      },
    ),
    'invalid revision ordering': (
      identityProfile,
      {
        ...identityLogs,
        'identity': {
          ...identityJson,
          'connectionRevision': '3',
          'trustRevision': '2',
        },
      },
    ),
  };
  for (final entry in identityCases.entries) {
    test(
      'log record context rejects ${entry.key} without inventing target metadata',
      () {
        final (profile, logs) = entry.value;
        final projection = ServerLogRecordContext.capture(profile, logs);
        expect(projection.profile, isNull);
        expect(projection.serverId, logs?['serverId']);
        expect(projection.source, logs?['source']);
        expect(projection.observedAt, logs?['observedAt']);
      },
    );
  }
  test('log record context permits metadata-only name tags and global revision updates', () {
    final metadata = _logTarget(
      name: 'Updated readable metadata',
      revision: '99',
      tags: ['new tag'],
    );
    final projection = ServerLogRecordContext.capture(metadata, identityLogs);
    expect(projection.profile, same(metadata));
    expect(projection.source, identityLogs['source']);
    expect(projection.observedAt, identityLogs['observedAt']);
  });

  for (final unauthorized in [false, true]) {
    testWidgets(
      'unresolved log record real private modal retires on loss unauthorized=$unauthorized and ignores late work',
      (tester) async {
        _view(tester, const Size(360, 800));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = _CountingClient();
        final bootstrap = fixture.ModelBootstrap(client)
          ..show(ReadinessState.ready);
        await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
        client.publish(ThemePreference.light, 1);
        await tester.pumpAndSettle();
        final owner = tester
            .widget<ProfileList>(find.byType(ProfileList))
            .controller;
        final profile = owner.selected!;
        final logs = {
          ...DesignServerFixtures.logs(
            records: [
              DesignServerFixtures.record(
                timestamp: '2026-10-24T07:08:09.000Z',
                message: 'PRIVATE unresolved log record',
              ),
            ],
          ),
          'serverId': profile.id,
          'identity': {
            ...DesignServerFixtures.identity().toJson(),
            'profileId': profile.id,
            'connectionRevision': profile.connectionRevision,
            'credentialRevision': profile.credentialRevision,
            'trustRevision': '999',
          },
        };
        final projection = ServerLogRecordContext.capture(profile, logs);
        expect(projection.profile, isNull);
        var closed = 0;
        final completion = showMotionDialog<void>(
          context: tester.element(find.byType(ProfileList)),
          barrierDismissible: true,
          builder: (context) => ServerLogRecordDialog(
            recordContext: projection,
            record: (logs['records'] as List).single as Map<String, Object?>,
            onClose: () {
              closed++;
              Navigator.pop(context);
            },
          ),
        );
        await tester.pumpAndSettle();
        final dialog = find.byType(ServerLogRecordDialog);
        final oldElement = tester.element(dialog);
        final route = ModalRoute.of(oldElement)!;
        final semantics = tester.ensureSemantics();
        final markers = [
          profile.id,
          'journald',
          '2026-10-24T07:08:09.000Z',
          DesignServerFixtures.observedAt,
          'PRIVATE unresolved log record',
        ];
        for (final text in [
          'Цель записи: ${profile.id}',
          'Параметры цели записи не подтверждены текущими сведениями',
          'journald',
          '2026-10-24T07:08:09.000Z UTC',
          '${DesignServerFixtures.observedAt} UTC',
        ]) {
          final label = find.descendant(of: dialog, matching: find.text(text));
          await tester.ensureVisible(label);
          await tester.pumpAndSettle();
          await _expectRecordSemantics(tester, label, text);
        }
        final pending = Completer<void>();
        client.refreshGate = pending;
        final allowedRead = owner.refresh();
        if (unauthorized) {
          client.readErrors.add(ErrorCode.unauthorized);
        } else {
          bootstrap.show(ReadinessState.unavailable);
        }
        await tester.pumpAndSettle();
        expect(oldElement.mounted, isFalse);
        expect(route.isActive, isFalse);
        pending.complete();
        await allowedRead;
        client.refreshGate = null;
        await tester.pumpAndSettle();
        bootstrap.show(ReadinessState.ready);
        _removeProfiles(client);
        await tester.pumpAndSettle();
        expect(
          find.byType(ServerLogRecordDialog, skipOffstage: false),
          findsNothing,
        );
        for (final marker in markers) {
          expect(
            find.textContaining(marker, skipOffstage: false),
            findsNothing,
          );
          expect(
            find.bySemanticsLabel(RegExp(RegExp.escape(marker))),
            findsNothing,
          );
        }
        expect(oldElement.mounted, isFalse);
        expect(closed, 0);
        expect(client.writes, isEmpty);
        expect(client.connections, 0);
        semantics.dispose();
        await completion;
        await tester.pumpWidget(const SizedBox.shrink());
        await client.events.close();
        await client.readErrors.close();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'log record factory refuses endpoint changed before opening and only a new matching result retargets',
    (tester) async {
      _view(tester, const Size(1100, 760));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final filter = TextEditingController();
      var effects = 0;
      final profileA = _logTarget(
        name: 'Цель A',
        address: 'endpoint-a.example',
      );
      final profileB = _logTarget(
        name: 'Цель B',
        address: 'endpoint-b.example',
        connectionRevision: '2',
      );
      var profile = profileA;
      var logs = DesignServerFixtures.logs(
        records: [
          DesignServerFixtures.record(
            timestamp: '2026-10-24T07:08:09.000Z',
            message: 'Exact record A',
          ),
        ],
      );
      final logsA = logs;
      final recordA = (logsA['records'] as List).single as Map<String, Object?>;
      Future<void> mount() async {
        final displayedLogs = logs;
        final recordContext = ServerLogRecordContext.capture(
          profile,
          displayedLogs,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: Motion.theme(BrandTheme.light, true),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Builder(
                  builder: (context) => ServerLogsSection(
                    logs: displayedLogs,
                    filterController: filter,
                    busy: false,
                    onLoad: () => effects++,
                    onPrevious: () => effects++,
                    onOpenRecord: (row) => showMotionDialog<void>(
                      context: context,
                      barrierDismissible: true,
                      builder: (context) => ServerLogRecordDialog(
                        recordContext: recordContext,
                        record: row,
                        onClose: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      profile = profileB;
      await mount();
      final launcher = find
          .byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.label ?? '').startsWith('Полная запись '),
          )
          .first;
      await tester.ensureVisible(launcher);
      await tester.tap(launcher);
      await tester.pumpAndSettle();
      final dialog = find.byType(ServerLogRecordDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('endpoint-b.example:22'),
        ),
        findsNothing,
        reason: 'A record from identity A must never be labelled as current endpoint B',
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Цель B')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('endpoint-a.example:22'),
        ),
        findsNothing,
      );
      final original = tester.widget<ServerLogRecordDialog>(dialog);
      expect(original.recordContext.profile, isNull);
      expect(original.record, same(recordA));
      final semantics = tester.ensureSemantics();
      for (final text in [
        'Цель записи: ${logsA['serverId']}',
        'Параметры цели записи не подтверждены текущими сведениями',
        'Закройте окно и получите журнал для текущих параметров.',
        '${logsA['source']}',
        '${recordA['timestamp']} UTC',
        '${logsA['observedAt']} UTC',
      ]) {
        final label = find.descendant(of: dialog, matching: find.text(text));
        expect(label, findsOneWidget);
        await tester.ensureVisible(label);
        await tester.pumpAndSettle();
        await _expectRecordSemantics(tester, label, text);
      }
      logs = {
        ...logsA,
        'identity': {
          ...(logsA['identity'] as Map<String, Object?>),
          'connectionRevision': profileB.connectionRevision,
        },
        'source': 'journal-B',
        'observedAt': '2026-10-26T12:00:00.000Z',
        'records': [
          DesignServerFixtures.record(
            timestamp: '2026-10-26T11:00:00.000Z',
            message: 'Exact record B',
          ),
        ],
      };
      await mount();
      expect(
        tester.widget<ServerLogRecordDialog>(dialog).recordContext,
        same(original.recordContext),
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Цель B')),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('journal-B')),
        findsNothing,
      );
      expect(effects, 0);
      semantics.dispose();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      await tester.ensureVisible(launcher);
      await tester.tap(launcher);
      await tester.pumpAndSettle();
      for (final text in [
        'Цель B',
        'endpoint-b.example:22',
        'journal-B',
        '2026-10-26T12:00:00.000Z UTC',
        '2026-10-26T11:00:00.000Z UTC',
      ]) {
        expect(
          find.descendant(of: dialog, matching: find.text(text)),
          findsOneWidget,
        );
      }
      expect(
        tester.widget<ServerLogRecordDialog>(dialog).recordContext.profile,
        same(profileB),
      );
      expect(effects, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      filter.dispose();
    },
  );

  testWidgets(
    'actual profile page retains draft target scroll owner and identity across all layouts',
    (tester) async {
      _view(tester, const Size(1100, 760));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _CountingClient();
      final bootstrap = fixture.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
      client.publish(ThemePreference.dark, 1);
      await tester.pumpAndSettle();
      final owner = tester.widget<ProfileList>(find.byType(ProfileList));
      final model = owner.controller;
      final listOwner = tester.state(find.byType(ProfileList));
      final initial = model.profiles.single;
      final baseRoute = ModalRoute.of(tester.element(find.byType(ProfileList)));
      final edit = find.widgetWithText(OutlinedButton, 'Изменить');
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      final launcher = Focus.of(tester.element(find.text('Изменить')));
      launcher.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final form = tester.state(find.byType(ProfileForm));
      expect(
        tester.widget<ProfileForm>(find.byType(ProfileForm)).asPage,
        isTrue,
      );
      expect(
        ModalRoute.of(tester.element(find.byType(ProfileForm))),
        same(baseRoute),
      );
      final formScroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ProfileForm),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(_field('name'), 'Черновик сервера 日本語');
      final editableState = tester.state(_editable(_field('name')));
      final editor = tester.widget<EditableText>(_editable(_field('name')));
      final reads = List<ApiMethod>.of(client.reads);
      final refreshes = client.refreshes;
      final epoch = bootstrap.readinessEpoch;
      var revision = 1;
      for (final size in const [
        Size(800, 600),
        Size(390, 800),
        Size(1100, 760),
      ]) {
        _view(tester, size);
        client.publish(
          revision.isOdd ? ThemePreference.light : ThemePreference.dark,
          ++revision,
        );
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ProfileForm)), same(form));
        expect(tester.state(_editable(_field('name'))), same(editableState));
        expect(
          tester.widget<EditableText>(_editable(_field('name'))).controller,
          same(editor.controller),
        );
        expect(editor.controller.text, 'Черновик сервера 日本語');
        expect(tester.state(find.byType(ProfileList)), same(listOwner));
        expect(
          tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ProfileForm),
                  matching: find.byType(Scrollable),
                )
                .first,
          ),
          same(formScroll),
        );
        expect(formScroll.position.pixels, greaterThanOrEqualTo(0));
        final currentForm = tester.widget<ProfileForm>(
          find.byType(ProfileForm),
        );
        expect(currentForm.initial, same(initial));
        expect(currentForm.initial!.id, fixture.profileId);
        expect(currentForm.initial!.revision, initial.revision);
        expect(currentForm.initial!.address, initial.address);
        expect(
          tester.widget<EditableText>(_editable(_field('name'))).focusNode,
          same(editor.focusNode),
        );
        expect(model.selected!.id, fixture.profileId);
        expect(
          tester.widget<ProfileList>(find.byType(ProfileList)).controller,
          same(model),
        );
        expect(formScroll.mounted, isTrue);
        expect(find.text('Редактирование профиля'), findsOneWidget);
        expect(find.textContaining('192.0.2.1:22'), findsWidgets);
        expect(client.reads, reads);
        expect(client.refreshes, refreshes);
        expect(client.connections, 0);
        expect(client.writes, isEmpty);
        expect(bootstrap.readinessEpoch, epoch);
        expect(tester.takeException(), isNull);
      }
      expect(client.pollingSnapshots, 4);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileForm), findsNothing);
      expect(launcher.context?.mounted, isNot(true));
      expect(tester.state(find.byType(ProfileList)), same(listOwner));
      final search = tester.widget<TextField>(
        find.descendant(
          of: find.byType(ProfileList),
          matching: find.byType(TextField),
        ),
      );
      expect(search.focusNode!.hasFocus, isTrue);
      expect(find.widgetWithText(OutlinedButton, 'Изменить'), findsOneWidget);
      expect(client.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await client.events.close();
      await client.readErrors.close();
    },
  );

  testWidgets(
    'actual settings page retains unsaved motion dropdown and owner',
    (tester) async {
      _view(tester, const Size(1100, 760));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _CountingClient();
      final bootstrap = fixture.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
      client.publish(ThemePreference.dark, 1);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('foundation-navigation-settings')),
      );
      await tester.pumpAndSettle();
      final owner = tester
          .widget<settings.SettingsView>(find.byType(settings.SettingsView))
          .controller;
      await tester.tap(find.text('Изменить настройки'));
      await tester.pumpAndSettle();
      final form = tester.state(find.byType(SettingsForm));
      expect(
        tester.widget<SettingsForm>(find.byType(SettingsForm)).asPage,
        isTrue,
      );
      final motion = find.byType(MotionDropdown<bool>);
      await tester.ensureVisible(motion);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Включено'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выключено'));
      await tester.pumpAndSettle();
      expect(tester.widget<MotionDropdown<bool>>(motion).initialValue, isFalse);
      final reads = List<ApiMethod>.of(client.reads);
      final refreshes = client.refreshes;
      var revision = 1;
      for (final size in const [
        Size(800, 600),
        Size(390, 800),
        Size(1100, 760),
      ]) {
        _view(tester, size);
        client.publish(ThemePreference.light, ++revision);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(SettingsForm)), same(form));
        expect(
          tester.widget<SettingsForm>(find.byType(SettingsForm)).model,
          same(owner),
        );
        expect(
          tester.widget<MotionDropdown<bool>>(motion).initialValue,
          isFalse,
        );
        expect(owner.settings!.reduceMotion, isTrue);
        expect(owner.selected!.id, fixture.profileId);
        expect(client.reads, reads);
        expect(client.refreshes, refreshes);
        expect(client.connections, 0);
        expect(client.writes, isEmpty);
        expect(tester.takeException(), isNull);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsForm), findsNothing);
      expect(find.text('Изменить настройки'), findsOneWidget);
      expect(client.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await client.events.close();
      await client.readErrors.close();
    },
  );

  testWidgets('production logs retain filter inner scroll and record modal', (
    tester,
  ) async {
    _view(tester, const Size(1100, 760));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final filter = TextEditingController();
    var reads = 0;
    Map<String, Object?>? selected;
    final rows = [
      for (var index = 0; index < 30; index++)
        <String, Object?>{
          'timestamp': '2026-10-25T00:00:${index.toString().padLeft(2, '0')}Z',
          'message': 'Журнал $index 日本語 — диагностическое сообщение',
        },
    ];
    var profile = _logTarget();
    var logs = <String, Object?>{
      ...DesignServerFixtures.logs(),
      'quality': 'known',
      'records': rows,
      'source': 'journald captured result',
      'observedAt': '2026-10-26T09:15:00.000Z',
    };
    Future<void> mount(Size size, ThemeData theme) async {
      _view(tester, size);
      final displayProfile = profile;
      final displayLogs = logs;
      final recordContext = ServerLogRecordContext.capture(
        displayProfile,
        displayLogs,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: FoundationShell(
            state: ReadinessState.ready,
            targetName: displayProfile.name,
            targetAddress: '${displayProfile.address}:${displayProfile.port}',
            servers: ServerPageFrame(
              profile: displayProfile,
              title: 'Журнал сервера',
              eyebrow: 'Журналы / Рабочее пространство',
              showServerTabs: false,
              onTabSelected: (_) {},
              child: ServerLogsSection(
                logs: displayLogs,
                filterController: filter,
                busy: false,
                onLoad: () => reads++,
                onPrevious: () => reads++,
                onOpenRecord: (row) {
                  selected = row;
                  showMotionDialog<void>(
                    context: tester.element(find.byType(ServerLogsSection)),
                    barrierDismissible: true,
                    builder: (context) => ServerLogRecordDialog(
                      recordContext: recordContext,
                      record: row,
                      onClose: () => Navigator.pop(context),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount(const Size(1100, 760), BrandTheme.dark);
    await tester.enterText(find.byType(TextField), 'kernel 日本語');
    final editable = tester.state(_editable(find.byType(TextField)));
    final inner = tester.state<ScrollableState>(
      find.descendant(
        of: find.descendant(
          of: find.byType(ServerLogsSection),
          matching: find.byType(ListView),
        ),
        matching: find.byType(Scrollable),
      ),
    );
    inner.position.jumpTo(200);
    await tester.pumpAndSettle();
    final offset = inner.position.pixels;
    for (final size in const [
      Size(800, 600),
      Size(390, 800),
      Size(1100, 760),
    ]) {
      await mount(size, BrandTheme.light);
      expect(tester.state(_editable(find.byType(TextField))), same(editable));
      expect(
        tester
            .widget<EditableText>(_editable(find.byType(TextField)))
            .controller,
        same(filter),
      );
      expect(filter.text, 'kernel 日本語');
      expect(inner.position.pixels, offset);
      expect(reads, 0);
      expect(find.textContaining('Целевой сервер'), findsWidgets);
      expect(tester.takeException(), isNull);
    }
    // Pause remains an honest disabled future affordance; no read follows.
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Пауза'))
          .onPressed,
      isNull,
    );
    expect(reads, 0);
    final record = find
        .byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label ?? '').startsWith('Полная запись '),
        )
        .first;
    await tester.ensureVisible(record);
    await tester.pumpAndSettle();
    await tester.tap(record);
    await tester.pumpAndSettle();
    final modal = tester.element(find.byType(ServerLogRecordDialog));
    final semantics = tester.ensureSemantics();
    final dialog = find.byType(ServerLogRecordDialog);
    final contextText = [
      'Целевой сервер',
      '192.0.2.1:22',
      'journald captured result',
      '${selected!['timestamp']} UTC',
      '2026-10-26T09:15:00.000Z UTC',
    ];
    for (final text in contextText) {
      expect(
        find.descendant(of: dialog, matching: find.text(text)),
        findsOneWidget,
      );
      await _expectRecordSemantics(
        tester,
        find.descendant(of: dialog, matching: find.text(text)),
        text,
      );
    }
    final captured = tester.widget<ServerLogRecordDialog>(dialog);
    expect(captured.recordContext.profile, same(profile));
    expect(captured.record, same(selected));
    profile = _logTarget(
      name: 'Поздняя другая цель',
      address: 'replacement.example',
      port: 2200,
      connectionRevision: '2',
    );
    logs = {
      ...logs,
      'source': 'replacement source',
      'observedAt': '2026-10-27T12:00:00.000Z',
      'records': [
        {'timestamp': '2026-10-27T11:00:00Z', 'message': 'replacement record'},
      ],
    };
    await mount(const Size(390, 800), BrandTheme.dark);
    expect(tester.element(find.byType(ServerLogRecordDialog)), same(modal));
    for (final text in contextText) {
      final label = find.descendant(of: dialog, matching: find.text(text));
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      expect(label, findsOneWidget);
      await _expectRecordSemantics(tester, label, text);
    }
    for (final text in [
      'Поздняя другая цель',
      'replacement source',
      'replacement record',
      '2026-10-27T12:00:00.000Z',
      '2026-10-27T11:00:00Z',
    ]) {
      expect(
        find.descendant(of: dialog, matching: find.textContaining(text)),
        findsNothing,
      );
    }
    expect(
      tester.widget<ServerLogRecordDialog>(dialog).recordContext.profile,
      same(captured.recordContext.profile),
    );
    expect(
      tester.widget<ServerLogRecordDialog>(dialog).record,
      same(captured.record),
    );
    expect(
      tester.widget<ServerLogRecordDialog>(dialog).recordContext.source,
      captured.recordContext.source,
    );
    expect(
      tester.widget<ServerLogRecordDialog>(dialog).recordContext.observedAt,
      captured.recordContext.observedAt,
    );
    expect(find.byType(SelectableText), findsWidgets);
    expect(reads, 0);
    semantics.dispose();
    await tester.ensureVisible(find.text('Закрыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    filter.dispose();
  });

  for (final missingRecordTime in [false, true]) {
    testWidgets(
      'log record missing source and times remain honest recordTimeMissing=$missingRecordTime',
      (tester) async {
        var opened = 0;
        final profile = _logTarget();
        final record = <String, Object?>{
          if (!missingRecordTime) 'timestamp': '2026-10-24T07:08:09.000Z',
          'message': 'Exact record without observation metadata',
        };
        final logs = {
          ...DesignServerFixtures.logs(),
          'source': null,
          'observedAt': null,
          'records': [record],
        };
        final recordContext = ServerLogRecordContext.capture(profile, logs);
        expect(recordContext.profile, same(profile));
        await tester.pumpWidget(
          MaterialApp(
            theme: Motion.theme(BrandTheme.light, true),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    opened++;
                    showMotionDialog<void>(
                      context: context,
                      barrierDismissible: true,
                      builder: (context) => ServerLogRecordDialog(
                        recordContext: recordContext,
                        record: record,
                        onClose: () => Navigator.pop(context),
                      ),
                    );
                  },
                  child: const Text('Открыть запись'),
                ),
              ),
            ),
          ),
        );
        final launcher = Focus.of(tester.element(find.text('Открыть запись')));
        launcher.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final semantics = tester.ensureSemantics();
        for (final text in [
          'Целевой сервер',
          '192.0.2.1:22',
          'Источник не указан',
          missingRecordTime
              ? 'Время записи: не указано'
              : '2026-10-24T07:08:09.000Z UTC',
          'Наблюдение: время не указано',
        ]) {
          expect(
            find.descendant(
              of: find.byType(ServerLogRecordDialog),
              matching: find.text(text),
            ),
            findsOneWidget,
          );
          await _expectRecordSemantics(
            tester,
            find.descendant(
              of: find.byType(ServerLogRecordDialog),
              matching: find.text(text),
            ),
            text,
          );
        }
        expect(find.textContaining('null'), findsNothing);
        expect(find.textContaining('journald'), findsNothing);
        expect(opened, 1);
        semantics.dispose();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(ServerLogRecordDialog), findsNothing);
        expect(launcher.hasFocus, isTrue);
        expect(opened, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'actual readiness loss retires a profile draft instead of retaining it',
    (tester) async {
      final client = _CountingClient();
      final bootstrap = fixture.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
      client.publish(ThemePreference.dark, 1);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Добавить сервер'));
      await tester.tap(find.text('Добавить сервер'));
      await tester.pumpAndSettle();
      final retired = tester.state(find.byType(ProfileForm));
      await tester.enterText(_field('name'), 'Retired private draft');
      final retiredFocus = tester
          .widget<EditableText>(_editable(_field('name')))
          .focusNode;
      bootstrap.show(ReadinessState.unavailable);
      await tester.pumpAndSettle();
      expect(retired.mounted, isFalse);
      expect(retiredFocus.hasFocus, isFalse);
      expect(
        find.text('Retired private draft', skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(ProfileForm, skipOffstage: false), findsNothing);
      bootstrap.show(ReadinessState.ready);
      client.publish(ThemePreference.light, 2);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileForm), findsNothing);
      expect(retired.mounted, isFalse);
      expect(retiredFocus.hasFocus, isFalse);
      expect(client.writes, isEmpty);
      expect(client.connections, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await client.events.close();
      await client.readErrors.close();
    },
  );

  testWidgets(
    'removed launcher fallback does not steal focus from a covering route',
    (tester) async {
      final client = _CountingClient();
      final bootstrap = fixture.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      final coveringFocus = FocusNode();
      await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
      client.publish(ThemePreference.dark, 1);
      await tester.pumpAndSettle();
      final listOwner = tester.state(find.byType(ProfileList));
      await tester.ensureVisible(find.text('Изменить'));
      await tester.pumpAndSettle();
      final launcher = Focus.of(tester.element(find.text('Изменить')));
      launcher.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final baseRoute = ModalRoute.of(
        tester.element(find.byType(ProfileForm)),
      )!;
      final closeEditor = tester
          .widget<ProfileForm>(find.byType(ProfileForm))
          .onClose!;
      final navigator = Navigator.of(tester.element(find.byType(ProfileForm)));
      _removeProfiles(client);
      await tester.pumpAndSettle();
      expect(launcher.context?.mounted, isNot(true));
      final covering = navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: TextField(
              focusNode: coveringFocus,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Публичная справка'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(coveringFocus.hasFocus, isTrue);
      // The editor is inline. Closing its retired launcher must not remove the
      // public route or move focus out of the route currently covering it.
      closeEditor();
      await tester.pumpAndSettle();
      expect(coveringFocus.hasFocus, isTrue);
      expect(find.byType(ProfileForm, skipOffstage: false), findsNothing);
      expect(baseRoute.isActive, isTrue);
      expect(baseRoute.isCurrent, isFalse);
      expect(
        tester.state(find.byType(ProfileList, skipOffstage: false)),
        same(listOwner),
      );
      expect(client.writes, isEmpty);
      navigator.pop();
      await tester.pumpAndSettle();
      await covering;
      expect(baseRoute.isCurrent, isTrue);
      expect(find.text('Все серверы.\nОдин центр управления.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      coveringFocus.dispose();
      await client.events.close();
      await client.readErrors.close();
    },
  );

  testWidgets(
    'removed profile launcher returns focus to an existing safe control',
    (tester) async {
      _view(tester, const Size(1100, 760));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _CountingClient();
      final bootstrap = fixture.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
      client.publish(ThemePreference.dark, 1);
      await tester.pumpAndSettle();
      final listOwner = tester.state(find.byType(ProfileList));
      await tester.ensureVisible(find.text('Изменить'));
      await tester.pumpAndSettle();
      Focus.of(tester.element(find.text('Изменить'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final snapshot = fixture.snapshot(revision: '2');
      final current = Map<String, Object?>.from(snapshot.profiles.result as Map)
        ..['profiles'] = <Object?>[];
      final currentSettings =
          Map<String, Object?>.from(snapshot.settings.result as Map)
            ..['settings'] = const SettingsView(
              theme: ThemePreference.dark,
              reduceMotion: true,
            ).toJson();
      client.events.add(
        ClientSnapshot(
          ApiReply(fixture.fixtureGeneration, current),
          ApiReply(fixture.fixtureGeneration, currentSettings),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Изменить'), findsNothing);
      expect(
        tester.widget<ProfileForm>(find.byType(ProfileForm)).initial!.id,
        fixture.profileId,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileForm), findsNothing);
      expect(tester.state(find.byType(ProfileList)), same(listOwner));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Добавить сервер'),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      final focus = FocusManager.instance.primaryFocus!;
      expect(focus.context, isNotNull);
      final element = focus.context! as Element;
      var insideShell = false;
      var insideControl = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is FoundationShell) insideShell = true;
        if (ancestor.widget is ButtonStyleButton) insideControl = true;
        return true;
      });
      expect(
        insideShell,
        isTrue,
        reason: 'Focus must return to the existing context',
      );
      expect(focus.canRequestFocus, isTrue);
      expect(insideControl, isTrue);
      expect(client.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await client.events.close();
      await client.readErrors.close();
    },
  );

  for (final dark in [false, true]) {
    for (final size in const [
      Size(1100, 760),
      Size(800, 600),
      Size(390, 800),
      Size(360, 800),
    ]) {
      testWidgets('actual profile route at200 with keyboard $size dark=$dark', (
        tester,
      ) async {
        _view(tester, size);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final client = _CountingClient();
        final bootstrap = fixture.ModelBootstrap(client)
          ..show(ReadinessState.ready);
        await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
        client.publish(dark ? ThemePreference.dark : ThemePreference.light, 1);
        await tester.pumpAndSettle();
        final launch = find.text('Добавить сервер');
        await tester.ensureVisible(launch);
        await tester.pumpAndSettle();
        final launcher = Focus.of(tester.element(launch));
        launcher.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        final name = tester.widget<EditableText>(_editable(_field('name')));
        await tester.enterText(_field('name'), '');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: _field('name'),
                  matching: find.byType(TextField),
                ),
              )
              .decoration!
              .errorText,
          'Проверьте значение поля',
        );
        expect(client.writes, isEmpty);
        await tester.enterText(_field('name'), 'Сохранённый черновик 日本語');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(_editable(_field('address')))
              .focusNode
              .hasFocus,
          isTrue,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(name.focusNode.hasFocus, isTrue);
        await tester.enterText(_field('tags'), 'первая\nвторая');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(client.writes, isEmpty);
        final save = find.widgetWithText(
          FilledButton,
          'Сохранить без подключения',
        );
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        expect(save.hitTestable(), findsOneWidget);
        final rect = tester.getRect(save);
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
        expect(rect.bottom, lessThanOrEqualTo(size.height - 300));
        expect(name.controller.text, 'Сохранённый черновик 日本語');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(ProfileForm), findsNothing);
        expect(launcher.hasFocus, isFalse);
        final search = tester.widget<TextField>(
          find.descendant(
            of: find.byType(ProfileList),
            matching: find.byType(TextField),
          ),
        );
        expect(search.focusNode!.hasFocus, isTrue);
        expect(client.writes, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await client.events.close();
        await client.readErrors.close();
      });
    }
  }

  for (final kind in _Modal.values) {
    testWidgets(
      'production $kind Escape cancels a real modal route and restores launcher',
      (tester) async {
        _view(tester, const Size(360, 800));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final launcher = FocusNode();
        final input = TextEditingController(text: '{\n"name":"draft"\n}');
        final description = TextEditingController();
        final body = TextEditingController(text: '{}');
        final theme = ValueNotifier<ThemeData>(BrandTheme.light);
        final recordLogs = {
          ...DesignServerFixtures.logs(
            records: [
              DesignServerFixtures.record(
                timestamp: '2026-10-25T12:00:00Z',
                message: 'Полная запись 日本語',
              ),
            ],
          ),
          'observedAt': '2026-10-26T09:15:00.000Z',
        };
        var approvals = 0, applications = 0, reads = 0, selections = 0;
        await tester.pumpWidget(
          ValueListenableBuilder<ThemeData>(
            valueListenable: theme,
            builder: (_, currentTheme, _) => MaterialApp(
              theme: currentTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 300),
                ),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: OutlinedButton(
                    focusNode: launcher,
                    child: const Text('Открыть'),
                    onPressed: () => showMotionDialog<void>(
                      context: context,
                      // The production ServerPanel and AutomationPanel owners
                      // explicitly allow cancellation for each of these routes.
                      barrierDismissible: true,
                      builder: (dialog) {
                        void close() => Navigator.pop(dialog);
                        return switch (kind) {
                          _Modal.server => ServerConfirmationDialog.revoke(
                            profile: DesignServerFixtures.profile(),
                            title: 'Отозвать доверие',
                            child: const Text(
                              'Доступ к серверу будет остановлен до нового подтверждения ключа.',
                            ),
                            confirmLabel: 'Отозвать',
                            onCancel: close,
                            onConfirm: () => applications++,
                          ),
                          _Modal.record => ServerLogRecordDialog(
                            recordContext: ServerLogRecordContext.capture(
                              DesignServerFixtures.profile(),
                              recordLogs,
                            ),
                            record:
                                (recordLogs['records'] as List).single
                                    as Map<String, Object?>,
                            onClose: close,
                          ),
                          _Modal.json => AutomationJsonEditorDialog(
                            title: 'Создать план',
                            input: input,
                            onClose: close,
                            onContinue: () => reads++,
                            target: 'Сервер 192.0.2.1:22',
                            purpose:
                                'Создать план. Запуск выполняется отдельно.',
                            error: 'Проверьте JSON',
                          ),
                          _Modal.profile => AutomationProfileEditorDialog(
                            name: input,
                            description: description,
                            body: body,
                            validating: false,
                            canValidate: true,
                            onBodyChanged: (_) {},
                            onClose: close,
                            onSave: () => applications++,
                            onValidate: () => reads++,
                          ),
                          _Modal.plan => AutomationPlanDecisionDialog(
                            now: DesignAutomationFixtures.presentationNow,
                            plan: const {
                              'serverId': '192.0.2.1',
                              'profileId': 'Профиль',
                              'profileRevision': 3,
                              'expiresAt': '2026-10-25T12:05:00Z',
                            },
                            approve: true,
                            onBack: close,
                            onConfirm: () => approvals++,
                          ),
                          _Modal.confirm => AutomationConfirmationDialog(
                            title: 'Отозвать разрешение',
                            message:
                                'Новые задания этого клиента будут запрещены.',
                            confirmLabel: 'Отозвать',
                            onBack: close,
                            onConfirm: () => applications++,
                          ),
                          _Modal.delegation => AutomationDelegationGrantDialog(
                            grants: const [
                              {
                                'label': 'Клиент',
                                'expiresAt': '2026-10-25T12:05:00Z',
                                'scopes': ['plan', 'apply'],
                                'serverIds': ['192.0.2.1'],
                              },
                            ],
                            onSelect: (_) => selections++,
                          ),
                        };
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        launcher.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        final modal = tester.element(find.byType(Dialog));
        for (final size in const [
          Size(800, 600),
          Size(1100, 760),
          Size(360, 800),
        ]) {
          _view(tester, size);
          theme.value = identical(theme.value, BrandTheme.light)
              ? BrandTheme.dark
              : BrandTheme.light;
          await tester.pumpAndSettle();
          expect(tester.element(find.byType(Dialog)), same(modal));
          expect(input.text, '{\n"name":"draft"\n}');
          expect(approvals, 0);
          expect(applications, 0);
          expect(reads, 0);
          expect(selections, 0);
          expect(tester.takeException(), isNull);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(launcher.hasFocus, isTrue);
        expect(approvals, 0);
        expect(applications, 0);
        expect(reads, 0);
        expect(selections, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        launcher.dispose();
        input.dispose();
        description.dispose();
        body.dispose();
        theme.dispose();
      },
    );
  }
}

enum _Modal { server, record, json, profile, plan, confirm, delegation }
