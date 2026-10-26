import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/shell/private_session.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/models.dart';

import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_server_fixtures.dart';
import '../support/design_state_capture.dart';

enum _Revoke {
  trust(
    'Отозвать доверие',
    'Доступ к серверу будет остановлен до нового подтверждения ключа.',
    '10-host-trust',
  ),
  executor(
    'Отозвать привязку',
    'Новые изменения через этот исполнитель будут недоступны.',
    '40-executor-binding',
  );

  const _Revoke(this.title, this.consequences, this.origin);
  final String title, consequences, origin;
}

ProfileView _profile({
  String name = 'Синтетический сервер 例 · отдел инфраструктуры',
  String address = '2001:db8::44',
  int port = 2222,
}) {
  final base = DesignServerFixtures.profile(address: address, port: port);
  return ProfileView(
    id: base.id,
    revision: base.revision,
    name: name,
    address: base.address,
    port: base.port,
    sshUser: base.sshUser,
    tags: base.tags,
    credentialRevision: base.credentialRevision,
    connectionRevision: base.connectionRevision,
    trustRevision: base.trustRevision,
    createdAt: base.createdAt,
    updatedAt: base.updatedAt,
    credentialKind: base.credentialKind,
    credentialConfigured: base.credentialConfigured,
  );
}

/// Public metadata and bool route results only; no native client or revoke RPC.
class _Owner {
  _Owner(this.kind, {this.dark = false, this.scale = 1, ProfileView? profile})
    : profile = profile ?? _profile();
  final _Revoke kind;
  ProfileView profile;
  bool dark;
  double scale;
  int epoch = 1, confirmed = 0, closed = 0;
  final launcher = FocusNode();

  Widget app() => RepaintBoundary(
    key: designStateCaptureBoundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Motion.theme(dark ? BrandTheme.dark : BrandTheme.light, true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: PrivateSessionScope(
          authorized: true,
          epoch: epoch,
          child: child!,
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: OutlinedButton(
            focusNode: launcher,
            onPressed: () async {
              final accepted = await showServerConfirmationDialog(
                context: context,
                profile: profile,
                title: kind.title,
                child: Text(kind.consequences),
                confirmLabel: 'Отозвать',
              );
              closed++;
              if (accepted) confirmed++;
            },
            child: const Text('Открыть подтверждение'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _mount(
  WidgetTester tester,
  _Owner owner, {
  Size size = const Size(1100, 760),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(owner.launcher.dispose);
  await tester.pumpWidget(owner.app());
  owner.launcher.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
  expect(find.byType(ServerConfirmationDialog), findsOneWidget);
  expect(find.byType(Dialog), findsOneWidget);
}

Finder get _confirm => find.widgetWithText(FilledButton, 'Отозвать');
Finder get _cancel => find.widgetWithText(TextButton, 'Отмена');

Future<void> _visibleText(WidgetTester tester, String text, Size frame) async {
  final finder = find.text(text);
  expect(finder, findsOneWidget);
  expect(tester.widget<Text>(finder).maxLines, isNull);
  expect(tester.widget<Text>(finder).overflow, isNot(TextOverflow.ellipsis));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(frame.width));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(frame.height));
  expect(tester.getSemantics(finder).label, contains(text));
}

void main() {
  setUpAll(loadDesignFonts);
  for (final kind in _Revoke.values) {
    for (final dark in [false, true]) {
      for (final frame in const [
        Size(1100, 760),
        Size(800, 600),
        Size(390, 800),
        Size(360, 800),
      ]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            'F16 actual ${kind.name} revoke $frame dark=$dark scale=$scale',
            (tester) async {
              final semantics = tester.ensureSemantics();
              final owner = _Owner(kind, dark: dark, scale: scale);
              await _mount(tester, owner, size: frame);
              for (final text in [
                kind.title,
                owner.profile.name,
                '[2001:db8::44]:2222',
                kind.consequences,
              ]) {
                await _visibleText(tester, text, frame);
              }
              for (final action in [_cancel, _confirm]) {
                await tester.ensureVisible(action);
                await tester.pumpAndSettle();
                expect(action.hitTestable(), findsOneWidget);
                expect(tester.getSize(action).width, greaterThanOrEqualTo(44));
                expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
              }
              expect(owner.confirmed, 0);
              expect(owner.closed, 0);
              await tester.ensureVisible(find.text(kind.title));
              await tester.pumpAndSettle();
              await captureDesignState(
                tester,
                family: 'server',
                caseIds: ['state-${kind.origin}-data'],
                phase: 't104-revoke-${kind.name}',
                theme: dark ? 'dark' : 'light',
                scale: scale,
                counters: {
                  'confirmed': owner.confirmed,
                  'closed': owner.closed,
                },
                assertions: [
                  'Actual shared revoke modal shows full name, bracketed IPv6 endpoint and consequences',
                  'Text semantics and scroll access; both actions meet 44px targets',
                  'Rendering has delivered no consent or route result',
                ],
                scope: 'T104 revoke target composition in the existing production modal route',
                limitations: [
                  'Existing origin ID identifies this scoped revoke variant only; no native revoke, service CAS or full state acceptance is exercised.',
                  'The initial scroll position is pictured; all text and actions were independently scrolled into view and asserted.',
                ],
              );
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
              expect(owner.confirmed, 0);
              expect(owner.closed, 1);
              expect(owner.launcher.hasFocus, isTrue);
              expect(find.byType(ServerConfirmationDialog), findsNothing);
              expect(tester.takeException(), isNull);
              semantics.dispose();
            },
          );
        }
      }
    }

    for (final cancel in [true, false]) {
      testWidgets(
        'actual ${kind.name} revoke ${cancel ? 'cancel' : 'confirm'} returns once',
        (tester) async {
          final owner = _Owner(
            kind,
            profile: _profile(address: '192.0.2.44', port: 22),
          );
          await _mount(tester, owner);
          expect(find.text('192.0.2.44:22'), findsOneWidget);
          await tester.tap(cancel ? _cancel : _confirm);
          await tester.pumpAndSettle();
          expect(owner.closed, 1);
          expect(owner.confirmed, cancel ? 0 : 1);
          expect(owner.launcher.hasFocus, isTrue);
          expect(find.byType(ServerConfirmationDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'actual ${kind.name} revoke retains its snapshot through owner/theme/resize changes',
      (tester) async {
        final owner = _Owner(kind);
        final captured = owner.profile;
        await _mount(tester, owner);
        final modal = tester.element(find.byType(ServerConfirmationDialog));
        final route = ModalRoute.of(modal);
        owner.profile = _profile(
          name: 'Другой сервер',
          address: '192.0.2.99',
          port: 2200,
        );
        for (final frame in const [
          Size(800, 600),
          Size(390, 800),
          Size(360, 800),
          Size(1100, 760),
        ]) {
          tester.view.physicalSize = frame;
          owner.dark = !owner.dark;
          owner.scale = owner.scale == 1 ? 2 : 1;
          await tester.pumpWidget(owner.app());
          await tester.pumpAndSettle();
          expect(
            tester.element(find.byType(ServerConfirmationDialog)),
            same(modal),
          );
          expect(ModalRoute.of(modal), same(route));
          expect(find.text(captured.name), findsOneWidget);
          expect(find.text('[2001:db8::44]:2222'), findsOneWidget);
          expect(find.text(owner.profile.name), findsNothing);
          expect(find.text('192.0.2.99:2200'), findsNothing);
          expect(owner.confirmed + owner.closed, 0);
          expect(tester.takeException(), isNull);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(owner.confirmed, 0);
        expect(owner.closed, 1);
      },
    );

    testWidgets(
      'actual ${kind.name} revoke hides the target on private epoch retirement',
      (tester) async {
        final owner = _Owner(kind);
        await _mount(tester, owner);
        owner.epoch++;
        await tester.pumpWidget(owner.app());
        await tester.pumpAndSettle();
        expect(
          find.byType(ServerConfirmationDialog, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.text(owner.profile.name, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.text('[2001:db8::44]:2222', skipOffstage: false),
          findsNothing,
        );
        expect(owner.confirmed, 0);
        expect(owner.closed, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('already bracketed IPv6 target is not bracketed twice', (
    tester,
  ) async {
    final owner = _Owner(
      _Revoke.trust,
      profile: _profile(address: '[2001:db8::44]'),
    );
    await _mount(tester, owner);
    expect(find.text('[2001:db8::44]:2222'), findsOneWidget);
    expect(find.text('[[2001:db8::44]]:2222'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(owner.confirmed, 0);
  });
}
