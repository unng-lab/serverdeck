import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/models.dart';

import '../support/design_server_fixtures.dart';

/// Presentation state only: no transport, operational client, or native proof.
class _ReviewState extends ChangeNotifier {
  _ReviewState({ProfileView? profile})
    : profile = profile ?? DesignServerFixtures.profile();

  ProfileView? profile;
  HostTrustChallenge? challenge = DesignServerFixtures.challenge();
  int confirmed = 0, cancelled = 0;

  void changed() => notifyListeners();

  Widget dialog() => ServerTrustConfirmation(
    challenge: challenge!,
    profile: profile!,
    changes: this,
    currentProfile: () => profile,
    currentChallenge: () => challenge,
    onCancel: () => cancelled++,
    onConfirm: () => confirmed++,
  );
}

Future<void> _mount(WidgetTester tester, _ReviewState state) async {
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: BrandTheme.light,
      home: Scaffold(body: state.dialog()),
    ),
  );
}

Finder get _confirm => find.widgetWithText(FilledButton, 'Подтвердить ключ');

void _expectBlocked(WidgetTester tester, _ReviewState state) {
  expect(tester.widget<FilledButton>(_confirm).onPressed, isNull);
  expect(state.confirmed, 0);
  expect(
    find.textContaining('перечитайте профиль и заново получите SSH-ключ'),
    findsOneWidget,
  );
  expect(tester.takeException(), isNull);
}

/// Mimics an existing owner's metadata update while an overlay is open.
/// The production dialog must handle synchronous delivery during parent build.
class _ProfileUpdateBridge extends StatefulWidget {
  const _ProfileUpdateBridge({required this.profile, required this.review});
  final ProfileView profile;
  final _ReviewState review;

  @override
  State<_ProfileUpdateBridge> createState() => _ProfileUpdateBridgeState();
}

class _ProfileUpdateBridgeState extends State<_ProfileUpdateBridge> {
  @override
  void didUpdateWidget(covariant _ProfileUpdateBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.review.profile = widget.profile;
    widget.review.changed();
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => showMotionDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => widget.review.dialog(),
    ),
    child: const Text('Проверить ключ'),
  );
}

void main() {
  testWidgets('SSH review displays the address beside the fingerprint', (
    tester,
  ) async {
    final state = _ReviewState();
    await _mount(tester, state);
    expect(find.textContaining('192.0.2.44:2222'), findsOneWidget);
    expect(find.textContaining(state.profile!.name), findsOneWidget);
    expect(find.text(state.challenge!.key.fingerprint), findsOneWidget);
    expect(state.confirmed, 0);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(_confirm);
    await tester.tap(_confirm);
    expect(state.confirmed, 1);
    expect(state.cancelled, 0);
  });

  testWidgets('SSH review brackets an IPv6 address before its port', (
    tester,
  ) async {
    final state = _ReviewState(
      profile: DesignServerFixtures.profile(address: '2001:db8::44', port: 22),
    );
    await _mount(tester, state);
    expect(find.textContaining('[2001:db8::44]:22'), findsOneWidget);
    expect(find.text(state.challenge!.key.fingerprint), findsOneWidget);
    expect(tester.widget<FilledButton>(_confirm).onPressed, isNotNull);
    expect(state.confirmed, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile UUID is diagnostic detail rather than the target', (
    tester,
  ) async {
    final state = _ReviewState();
    await _mount(tester, state);
    expect(find.text(DesignServerFixtures.serverId), findsNothing);
    await tester.ensureVisible(find.text('Технические сведения'));
    await tester.tap(find.text('Технические сведения'));
    await tester.pumpAndSettle();
    expect(find.text(DesignServerFixtures.serverId), findsOneWidget);
    expect(find.textContaining('192.0.2.44:2222'), findsOneWidget);
    expect(state.confirmed, 0);
  });

  final mismatches = <String, ProfileView Function()>{
    'profile identity': () => DesignServerFixtures.profile(
      id: '00000000-0000-4000-8000-000000000099',
    ),
    'profile revision': () => DesignServerFixtures.profile(revision: '3'),
    'connection revision': () =>
        DesignServerFixtures.profile(connectionRevision: '3'),
    'credential revision': () =>
        DesignServerFixtures.profile(credentialRevision: '3'),
    'trust revision': () => DesignServerFixtures.profile(trustRevision: '3'),
  };
  for (final mismatch in mismatches.entries) {
    testWidgets('initial ${mismatch.key} mismatch cannot label an old key', (
      tester,
    ) async {
      final state = _ReviewState(profile: mismatch.value());
      await _mount(tester, state);
      _expectBlocked(tester, state);
      expect(find.textContaining('192.0.2.44:2222'), findsNothing);
      expect(find.textContaining(state.profile!.name), findsNothing);
      expect(find.text(state.challenge!.key.fingerprint), findsOneWidget);
      await tester.ensureVisible(_confirm);
      await tester.tap(_confirm);
      expect(state.confirmed, 0);
    });
  }

  final changes = <String, ProfileView Function()>{
    ...mismatches,
    'address': () => DesignServerFixtures.profile(address: '192.0.2.99'),
    'port': () => DesignServerFixtures.profile(port: 2223),
  };
  for (final change in changes.entries) {
    testWidgets('${change.key} change retires an open review permanently', (
      tester,
    ) async {
      final state = _ReviewState();
      final initial = state.profile;
      await _mount(tester, state);
      state.profile = change.value();
      state.changed();
      await tester.pump();
      _expectBlocked(tester, state);
      expect(find.textContaining('192.0.2.44:2222'), findsOneWidget);
      expect(find.textContaining('192.0.2.99:2222'), findsNothing);
      expect(find.textContaining('192.0.2.44:2223'), findsNothing);
      state.profile = initial;
      state.changed();
      await tester.pump();
      _expectBlocked(tester, state);
    });
  }

  testWidgets('click rechecks metadata before a notification redraw', (
    tester,
  ) async {
    final state = _ReviewState();
    await _mount(tester, state);
    state.profile = DesignServerFixtures.profile(address: '192.0.2.99');
    expect(tester.widget<FilledButton>(_confirm).onPressed, isNotNull);
    await tester.ensureVisible(_confirm);
    await tester.tap(_confirm);
    await tester.pump();
    _expectBlocked(tester, state);
  });

  testWidgets('replacement challenge object invalidates prior consent', (
    tester,
  ) async {
    final state = _ReviewState();
    final initial = state.challenge;
    await _mount(tester, state);
    state.challenge = DesignServerFixtures.challenge();
    expect(state.challenge!.toJson(), initial!.toJson());
    state.changed();
    await tester.pump();
    _expectBlocked(tester, state);
    state.challenge = initial;
    state.changed();
    await tester.pump();
    _expectBlocked(tester, state);
  });

  for (final removed in ['profile', 'challenge']) {
    testWidgets('removed $removed makes confirmation unavailable', (
      tester,
    ) async {
      final state = _ReviewState();
      await _mount(tester, state);
      if (removed == 'profile') {
        state.profile = null;
      } else {
        state.challenge = null;
      }
      state.changed();
      await tester.pump();
      _expectBlocked(tester, state);
    });
  }

  testWidgets('cancel does not confirm trust', (tester) async {
    final state = _ReviewState();
    await _mount(tester, state);
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Отмена'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Отмена'));
    expect(state.cancelled, 1);
    expect(state.confirmed, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-target rebuild retains review without granting consent', (
    tester,
  ) async {
    final state = _ReviewState();
    await _mount(tester, state);
    final dialogState = tester.state(find.byType(ServerTrustConfirmation));
    state.profile = DesignServerFixtures.profile();
    state.changed();
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark,
        home: Scaffold(body: state.dialog()),
      ),
    );
    expect(
      tester.state(find.byType(ServerTrustConfirmation)),
      same(dialogState),
    );
    expect(tester.widget<FilledButton>(_confirm).onPressed, isNotNull);
    expect(find.textContaining('192.0.2.44:2222'), findsOneWidget);
    expect(state.confirmed, 0);
    expect(state.cancelled, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes the review without a trust callback', (
    tester,
  ) async {
    final state = _ReviewState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.light,
        home: Scaffold(
          body: _ProfileUpdateBridge(profile: state.profile!, review: state),
        ),
      ),
    );
    await tester.tap(find.text('Проверить ключ'));
    await tester.pumpAndSettle();
    expect(find.byType(ServerTrustConfirmation), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ServerTrustConfirmation), findsNothing);
    expect(state.confirmed, 0);
    expect(state.cancelled, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile update during owner build safely retires open modal', (
    tester,
  ) async {
    final state = _ReviewState();
    final profile = ValueNotifier(state.profile!);
    addTearDown(state.dispose);
    addTearDown(profile.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.light,
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: profile,
            builder: (_, value, _) =>
                _ProfileUpdateBridge(profile: value, review: state),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Проверить ключ'));
    await tester.pumpAndSettle();
    profile.value = DesignServerFixtures.profile(address: '192.0.2.99');
    await tester.pump();
    // The prior button can retain its handler until the next frame, so the
    // handler itself must reject the changed target immediately.
    await tester.ensureVisible(_confirm);
    await tester.tap(_confirm);
    await tester.pumpAndSettle();
    _expectBlocked(tester, state);
    expect(find.textContaining('192.0.2.44:2222'), findsOneWidget);
    expect(find.textContaining('192.0.2.99:2222'), findsNothing);
  });
}
