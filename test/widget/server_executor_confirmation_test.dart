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

/// Public presentation metadata only; no native client or enrollment effect.
class _Review extends ChangeNotifier {
  _Review({ProfileView? profile}) : profile = profile ?? _profile();
  ProfileView? profile;
  Map<String, Object?>? inspection = DesignServerFixtures.executorInspection();
  int confirmed = 0, cancelled = 0;
  void changed() => notifyListeners();
  Widget dialog() => ServerExecutorConfirmation(
    inspection: inspection!,
    profile: profile!,
    changes: this,
    currentProfile: () => profile,
    currentInspection: () => inspection,
    onCancel: () => cancelled++,
    onConfirm: () => confirmed++,
  );
}

ProfileView _profile({
  String? name,
  String id = DesignServerFixtures.serverId,
  String revision = '2',
  String address = '192.0.2.44',
  int port = 2222,
  String connectionRevision = '1',
  String credentialRevision = '1',
  String trustRevision = '2',
}) {
  final base = DesignServerFixtures.profile(
    id: id,
    revision: revision,
    address: address,
    port: port,
    connectionRevision: connectionRevision,
    credentialRevision: credentialRevision,
    trustRevision: trustRevision,
  );
  return ProfileView(
    id: base.id,
    revision: base.revision,
    name: name ?? base.name,
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

Widget _app(Widget child, {bool dark = false, double scale = 1}) => MaterialApp(
  theme: Motion.theme(dark ? BrandTheme.dark : BrandTheme.light, true),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
    child: child!,
  ),
  home: Scaffold(body: child),
);

Future<void> _mount(
  WidgetTester tester,
  _Review review, {
  bool dark = false,
  double scale = 1,
  Size size = const Size(1100, 760),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(review.dispose);
  await tester.pumpWidget(_app(review.dialog(), dark: dark, scale: scale));
}

Finder get _confirm => find.widgetWithText(FilledButton, 'Привязать');
void _blocked(WidgetTester tester, _Review review) {
  expect(tester.widget<FilledButton>(_confirm).onPressed, isNull);
  expect(review.confirmed, 0);
  expect(find.textContaining('заново проверьте исполнитель'), findsOneWidget);
  expect(find.text('192.0.2.44:2222'), findsNothing);
  expect(tester.takeException(), isNull);
}

/// Delivers a real owner-style notification while its parent is building.
class _OwnerBridge extends StatefulWidget {
  const _OwnerBridge({required this.profile, required this.review});
  final ProfileView profile;
  final _Review review;
  @override
  State<_OwnerBridge> createState() => _OwnerBridgeState();
}

class _OwnerBridgeState extends State<_OwnerBridge> {
  @override
  void didUpdateWidget(covariant _OwnerBridge oldWidget) {
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
    child: const Text('Проверить исполнитель'),
  );
}

void main() {
  setUpAll(loadDesignFonts);
  for (final dark in [false, true]) {
    testWidgets('executor review shows the human target and key dark=$dark', (
      tester,
    ) async {
      final review = _Review();
      await _mount(tester, review, dark: dark);
      expect(find.text(review.profile!.name), findsOneWidget);
      expect(find.text('192.0.2.44:2222'), findsOneWidget);
      expect(find.text(DesignServerFixtures.key.fingerprint), findsOneWidget);
      expect(
        find.text(
          'Подтверждение действует до ${DesignServerFixtures.expiresAt} · UTC',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 40));
      expect(review.confirmed + review.cancelled, 0);
      await tester.ensureVisible(_confirm);
      await tester.tap(_confirm);
      expect(review.confirmed, 1);
      expect(review.cancelled, 0);
    });
  }
  testWidgets('executor and profile UUIDs are explicit diagnostic details', (
    tester,
  ) async {
    final review = _Review();
    await _mount(tester, review);
    expect(find.text(DesignServerFixtures.serverId), findsNothing);
    expect(find.text(DesignServerFixtures.hostId), findsNothing);
    await tester.tap(find.text('Технические сведения'));
    await tester.pumpAndSettle();
    expect(find.text('Идентификатор профиля'), findsOneWidget);
    expect(find.text(DesignServerFixtures.serverId), findsOneWidget);
    expect(find.text('Идентификатор исполнителя'), findsOneWidget);
    expect(find.text(DesignServerFixtures.hostId), findsOneWidget);
    expect(review.confirmed, 0);
  });
  final mismatches = <String, ProfileView Function()>{
    'profile identity': () =>
        _profile(id: '00000000-0000-4000-8000-000000000099'),
    'connection revision': () => _profile(connectionRevision: '3'),
    'credential revision': () => _profile(credentialRevision: '3'),
    'trust revision': () => _profile(trustRevision: '3'),
  };
  for (final mismatch in mismatches.entries) {
    testWidgets('initial ${mismatch.key} cannot label an inspected executor', (
      tester,
    ) async {
      final review = _Review(profile: mismatch.value());
      await _mount(tester, review);
      _blocked(tester, review);
      expect(find.text(review.profile!.name), findsNothing);
      expect(find.text(DesignServerFixtures.key.fingerprint), findsOneWidget);
      await tester.tap(_confirm);
      expect(review.confirmed, 0);
    });
  }
  final changes = <String, ProfileView Function()>{
    ...mismatches,
    'profile revision': () => _profile(revision: '3'),
    'name': () => _profile(name: 'Другой сервер'),
    'address': () => _profile(address: '192.0.2.99'),
    'port': () => _profile(port: 2223),
  };
  for (final change in changes.entries) {
    testWidgets('${change.key} retires executor consent without restoration', (
      tester,
    ) async {
      final review = _Review();
      final initial = review.profile;
      await _mount(tester, review);
      review.profile = change.value();
      review.changed();
      await tester.pump();
      _blocked(tester, review);
      expect(find.text('192.0.2.99:2222'), findsNothing);
      review.profile = initial;
      review.changed();
      await tester.pump();
      _blocked(tester, review);
    });
  }
  for (final removed in ['profile', 'inspection']) {
    testWidgets('removed $removed permanently retires executor consent', (
      tester,
    ) async {
      final review = _Review();
      final profile = review.profile, inspection = review.inspection;
      await _mount(tester, review);
      if (removed == 'profile') {
        review.profile = null;
      } else {
        review.inspection = null;
      }
      review.changed();
      await tester.pump();
      _blocked(tester, review);
      review.profile = profile;
      review.inspection = inspection;
      review.changed();
      await tester.pump();
      _blocked(tester, review);
    });
  }
  testWidgets('replacement inspection cannot restore an old executor consent', (
    tester,
  ) async {
    final review = _Review();
    final inspection = review.inspection;
    await _mount(tester, review);
    review.inspection = DesignServerFixtures.executorInspection();
    expect(review.inspection, inspection);
    expect(identical(review.inspection, inspection), isFalse);
    review.changed();
    await tester.pump();
    _blocked(tester, review);
    review.inspection = inspection;
    review.changed();
    await tester.pump();
    _blocked(tester, review);
  });
  for (final inspectionChanged in [false, true]) {
    testWidgets(
      'click rechecks metadata before redraw inspection=$inspectionChanged',
      (tester) async {
        final review = _Review();
        await _mount(tester, review);
        if (inspectionChanged) {
          review.inspection = DesignServerFixtures.executorInspection();
        } else {
          review.profile = _profile(address: '192.0.2.99');
        }
        expect(tester.widget<FilledButton>(_confirm).onPressed, isNotNull);
        await tester.tap(_confirm);
        await tester.pump();
        _blocked(tester, review);
      },
    );
  }
  testWidgets('cancel reports cancellation and never enrolls an executor', (
    tester,
  ) async {
    final review = _Review();
    await _mount(tester, review);
    await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
    expect(review.cancelled, 1);
    expect(review.confirmed, 0);
  });
  testWidgets('owner metadata delivered during build retires open review', (
    tester,
  ) async {
    final review = _Review(), profile = ValueNotifier(_profile());
    addTearDown(review.dispose);
    addTearDown(profile.dispose);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder(
          valueListenable: profile,
          builder: (_, value, _) =>
              _OwnerBridge(profile: value, review: review),
        ),
      ),
    );
    await tester.tap(find.text('Проверить исполнитель'));
    await tester.pumpAndSettle();
    profile.value = _profile(address: '192.0.2.99');
    await tester.pumpAndSettle();
    _blocked(tester, review);
    profile.value = _profile();
    await tester.pumpAndSettle();
    _blocked(tester, review);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ServerExecutorConfirmation), findsNothing);
    expect(review.confirmed + review.cancelled, 0);
  });
  testWidgets('retired private route cannot deliver late executor consent', (
    tester,
  ) async {
    final review = _Review(), epoch = ValueNotifier(1);
    addTearDown(review.dispose);
    addTearDown(epoch.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: Motion.theme(BrandTheme.dark, true),
        builder: (context, child) => ValueListenableBuilder(
          valueListenable: epoch,
          builder: (_, value, _) => PrivateSessionScope(
            authorized: true,
            epoch: value,
            child: child!,
          ),
        ),
        home: Scaffold(
          body: _OwnerBridge(profile: review.profile!, review: review),
        ),
      ),
    );
    await tester.tap(find.text('Проверить исполнитель'));
    await tester.pumpAndSettle();
    final lateConfirm = tester.widget<FilledButton>(_confirm).onPressed!;
    epoch.value++;
    await tester.pumpAndSettle();
    expect(
      find.byType(ServerExecutorConfirmation, skipOffstage: false),
      findsNothing,
    );
    lateConfirm();
    await tester.pump();
    expect(review.confirmed + review.cancelled, 0);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    for (final size in const [
      Size(1100, 760),
      Size(800, 600),
      Size(390, 800),
      Size(360, 800),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'readable long IPv6 executor target $size dark=$dark scale=$scale',
          (tester) async {
            final review = _Review(
              profile: _profile(
                name: List.filled(5, 'Синтетический сервер 例 ').join().trim(),
                address: '2001:db8::44',
                port: 22,
              ),
            );
            await _mount(tester, review, dark: dark, scale: scale, size: size);
            final original = tester.state(
              find.byType(ServerExecutorConfirmation),
            );
            for (final text in [
              review.profile!.name,
              '[2001:db8::44]:22',
              DesignServerFixtures.key.fingerprint,
            ]) {
              final content = find.text(text);
              expect(content, findsOneWidget);
              await tester.ensureVisible(content);
              await tester.pumpAndSettle();
              final rect = tester.getRect(content);
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(size.width));
              expect(rect.top, greaterThanOrEqualTo(0));
              expect(rect.bottom, lessThanOrEqualTo(size.height));
            }
            await tester.ensureVisible(_confirm);
            await tester.pumpAndSettle();
            expect(tester.getSize(_confirm).width, greaterThanOrEqualTo(44));
            expect(tester.getSize(_confirm).height, greaterThanOrEqualTo(44));
            expect(
              tester.state(find.byType(ServerExecutorConfirmation)),
              same(original),
            );
            expect(review.confirmed + review.cancelled, 0);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
