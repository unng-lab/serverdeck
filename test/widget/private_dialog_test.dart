import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/app.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as fixture;

void main() {
  for (final rapidRetirement in [true, false]) {
    testWidgets(
      rapidRetirement
          ? 'rapid auth recovery replaces the private feature State'
          : 'ordinary theme and resize retain private feature State',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = _VisibilityClient();
        final bootstrap = fixture.ModelBootstrap(client)
          ..show(ReadinessState.ready);
        await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
        client.events.add(fixture.snapshot());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Saved profile'));
        await tester.pumpAndSettle();
        final tiles = find.byType(ExpansionTile);
        final previous = tester.state(tiles);
        expect(find.text('Редактировать профиль'), findsOneWidget);
        final snapshot = fixture.snapshot();
        if (rapidRetirement) {
          client.readErrors.add(ErrorCode.unauthorized);
          // Both synchronous events happen before Flutter can draw a frame.
          client.events.add(snapshot);
        } else {
          tester.view.physicalSize = const Size(390, 800);
          client.events.add(
            ClientSnapshot(
              snapshot.profiles,
              ApiReply(fixture.fixtureGeneration, {
                'storeRevision': '1',
                'settings': const SettingsView(
                  theme: ThemePreference.light,
                  reduceMotion: true,
                  selectedProfileId: fixture.profileId,
                ).toJson(),
              }),
            ),
          );
        }
        await tester.pumpAndSettle();
        final current = tester.state(tiles);
        if (rapidRetirement) {
          expect(current, isNot(same(previous)));
          expect(previous.mounted, isFalse);
          expect(find.text('Редактировать профиль'), findsNothing);
          // A subsequent response can update the current snapshot; it cannot
          // reattach the retired owner, its expansion, or descendant buffers.
          client.events.add(fixture.snapshot(revision: '2'));
          await tester.pumpAndSettle();
          expect(previous.mounted, isFalse);
          expect(tester.state(tiles), same(current));
          expect(find.text('Редактировать профиль'), findsNothing);
        } else {
          expect(current, same(previous));
          expect(find.text('Редактировать профиль'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await bootstrap.close();
        await client.visibilityStates.close();
        await client.events.close();
        await client.readErrors.close();
      },
    );
  }

  for (final loss in [
    'unauthorized',
    'closed',
    'rapid-authorization-recovery',
  ]) {
    testWidgets(
      '$loss retires private content without bootstrap state change',
      (tester) async {
        final client = _VisibilityClient();
        final bootstrap = fixture.ModelBootstrap(client)
          ..show(ReadinessState.ready);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
        client.events.add(fixture.snapshot());
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(FoundationShell));
        var accepted = 0;
        final result = showMotionDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Retired private target'),
            content: const Text('Retired private secret'),
            actions: [
              TextButton(
                onPressed: () {
                  accepted++;
                  Navigator.pop(context, true);
                },
                child: const Text('Accept retired consent'),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Retired private target'), findsOneWidget);
        if (loss == 'closed') {
          client.visibilityStates.add(ClientConnectionState.closed);
        } else {
          client.readErrors.add(ErrorCode.unauthorized);
        }
        if (loss == 'rapid-authorization-recovery') {
          client.events.add(fixture.snapshot());
        }
        await tester.pump();
        expect(bootstrap.state, ReadinessState.ready);
        for (final marker in [
          'Retired private target',
          'Retired private secret',
          'Accept retired consent',
        ]) {
          expect(find.text(marker, skipOffstage: false), findsNothing);
          expect(find.bySemanticsLabel(marker), findsNothing);
        }
        await tester.pumpAndSettle();
        expect(await result, isNull);
        expect(accepted, 0);
        if (loss != 'rapid-authorization-recovery') {
          expect(find.textContaining('Saved profile'), findsNothing);
          // A late reply cannot reopen a closed client. A current authorized
          // snapshot may restore the workspace, but never the retired consent.
          client.events.add(fixture.snapshot());
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Saved profile'),
            loss == 'closed' ? findsNothing : findsWidgets,
          );
          expect(find.text('Retired private target'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await bootstrap.close();
        await client.visibilityStates.close();
        await client.events.close();
        await client.readErrors.close();
        semantics.dispose();
      },
    );
  }

  testWidgets('ready loss removes a private route and retires its consent', (
    tester,
  ) async {
    final client = fixture.ModelClient();
    final bootstrap = fixture.ModelBootstrap(client)
      ..show(ReadinessState.ready);
    await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
    client.events.add(fixture.snapshot());
    await tester.pump();
    final context = tester.element(find.byType(FoundationShell));
    var accepted = 0;
    final result = showMotionDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Private consent target'),
        content: const Text('Private secret input'),
        actions: [
          TextButton(
            onPressed: () {
              accepted++;
              Navigator.of(context).pop(true);
            },
            child: const Text('Accept private effect'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private consent target'), findsOneWidget);
    bootstrap.show(ReadinessState.unavailable);
    await tester.pump();
    expect(
      find.text('Private consent target', skipOffstage: false),
      findsNothing,
    );
    expect(
      find.text('Private secret input', skipOffstage: false),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(await result, isNull);
    bootstrap.show(ReadinessState.ready);
    await tester.pump();
    expect(
      find.text('Private consent target', skipOffstage: false),
      findsNothing,
    );
    expect(accepted, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await client.events.close();
    await client.readErrors.close();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rapid session change retires covered private routes', (
    tester,
  ) async {
    final client = fixture.ModelClient();
    final bootstrap = fixture.ModelBootstrap(client)
      ..show(ReadinessState.ready);
    await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
    client.events.add(fixture.snapshot());
    await tester.pumpAndSettle();
    final first = showMotionDialog<void>(
      context: tester.element(find.byType(FoundationShell)),
      builder: (_) => const AlertDialog(title: Text('First private target')),
    );
    await tester.pumpAndSettle();
    final second = showMotionDialog<void>(
      context: tester.element(find.text('First private target')),
      builder: (_) => const AlertDialog(title: Text('Second private target')),
    );
    await tester.pumpAndSettle();
    bootstrap.show(ReadinessState.unavailable);
    bootstrap.show(ReadinessState.ready);
    await tester.pump();
    await tester.pump();
    expect(
      find.text('First private target', skipOffstage: false),
      findsNothing,
    );
    expect(
      find.text('Second private target', skipOffstage: false),
      findsNothing,
    );
    await first;
    await second;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await client.events.close();
    await client.readErrors.close();
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme and resize keep a private route in the same session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = fixture.ModelClient();
    final bootstrap = fixture.ModelBootstrap(client)
      ..show(ReadinessState.ready);
    final draft = TextEditingController();
    await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
    client.events.add(fixture.snapshot());
    await tester.pumpAndSettle();
    final epoch = bootstrap.readinessEpoch;
    final route = showMotionDialog<void>(
      context: tester.element(find.byType(FoundationShell)),
      builder: (_) => AlertDialog(
        title: const Text('Keep open target'),
        content: TextField(controller: draft),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate(
      (widget) => widget is EditableText && identical(widget.controller, draft),
    );
    final original = tester.state(field);
    await tester.enterText(field, 'Permitted dialog draft');
    tester.view.physicalSize = const Size(390, 800);
    final old = fixture.snapshot();
    client.events.add(
      ClientSnapshot(
        old.profiles,
        ApiReply(fixture.fixtureGeneration, {
          'storeRevision': '1',
          'settings': const SettingsView(
            theme: ThemePreference.light,
            reduceMotion: true,
          ).toJson(),
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.state(field), same(original));
    expect(draft.text, 'Permitted dialog draft');
    expect(bootstrap.readinessEpoch, epoch);
    expect(find.text('Keep open target'), findsOneWidget);
    Navigator.of(tester.element(find.text('Keep open target'))).pop();
    await tester.pumpAndSettle();
    await route;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    draft.dispose();
    await client.events.close();
    await client.readErrors.close();
    expect(tester.takeException(), isNull);
  });

  testWidgets('only public navigation may open outside a ready session', (
    tester,
  ) async {
    final client = fixture.ModelClient();
    final bootstrap = fixture.ModelBootstrap(client);
    await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
    await tester.pump();
    final context = tester.element(find.byType(FoundationShell));
    var privateBuilds = 0;
    final privateRoute = showMotionDialog<void>(
      context: context,
      builder: (_) {
        privateBuilds++;
        return const AlertDialog(title: Text('Forbidden private content'));
      },
    );
    await tester.pump();
    await tester.pump();
    expect(privateBuilds, 0);
    expect(
      find.text('Forbidden private content', skipOffstage: false),
      findsNothing,
    );
    await privateRoute;
    final publicRoute = showMotionDialog<void>(
      context: context,
      privateContent: false,
      builder: (_) => const AlertDialog(title: Text('Public navigation')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Public navigation'), findsOneWidget);
    Navigator.of(tester.element(find.text('Public navigation'))).pop();
    await tester.pumpAndSettle();
    await publicRoute;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await client.events.close();
    await client.readErrors.close();
    expect(tester.takeException(), isNull);
  });
}

class _VisibilityClient extends fixture.ModelClient {
  final visibilityStates = StreamController<ClientConnectionState>.broadcast(
    sync: true,
  );

  @override
  Stream<ClientConnectionState> get states => visibilityStates.stream;
}
