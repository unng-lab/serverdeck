import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/runtime/owned_settings_route.dart';
import 'package:serverdeck/theme/brand_theme.dart';

class _Host extends StatefulWidget {
  const _Host({
    required this.owner,
    required this.admitted,
    required this.changes,
    required this.dispatch,
  });
  final Object owner;
  final bool admitted;
  final List<bool> changes;
  final VoidCallback dispatch;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  var session = OwnedSettingsRoute();
  @override
  void didUpdateWidget(covariant _Host oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.owner != widget.owner || !widget.admitted) {
      session.retire();
      session = OwnedSettingsRoute();
    }
  }

  @override
  void dispose() {
    session.retire();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: !widget.admitted
        ? null
        : () {
            final current = session;
            unawaited(
              current.show(
                context,
                child: _NestedSettings(dispatch: widget.dispatch),
                onChanged: () {
                  if (mounted && identical(current, session))
                    widget.changes.add(!current.isOpen);
                },
              ),
            );
          },
    child: const Text('Open settings'),
  );
}

class _NestedSettings extends StatelessWidget {
  const _NestedSettings({required this.dispatch});
  final VoidCallback dispatch;
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () async {
        final accepted = await showDialog<bool>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: const Text('Nested confirmation'),
            content: const TextField(
              decoration: InputDecoration(labelText: 'Client name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Dispatch'),
              ),
            ],
          ),
        );
        if (accepted == true) dispatch();
      },
      child: const Text('Nested action'),
    ),
  );
}

void main() {
  for (final retirement in [
    'owner replacement',
    'admission loss',
    'host disposal',
  ]) {
    testWidgets('settings and nested routes retire on $retirement', (
      tester,
    ) async {
      final changes = <bool>[];
      var dispatches = 0;
      final first = Object(), second = Object();
      Widget view(Object owner, {bool admitted = true, bool present = true}) =>
          MaterialApp(
            theme: BrandTheme.dark,
            home: Scaffold(
              body: present
                  ? _Host(
                      owner: owner,
                      admitted: admitted,
                      changes: changes,
                      dispatch: () => dispatches++,
                    )
                  : const Text('Retired host'),
            ),
          );
      await tester.pumpWidget(view(first));
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(changes, [false]);
      await tester.tap(find.text('Nested action'));
      await tester.pumpAndSettle();
      expect(find.text('Nested confirmation'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'Synthetic retired client',
      );
      await tester.pumpWidget(
        view(
          retirement == 'owner replacement' ? second : first,
          admitted: retirement != 'admission loss',
          present: retirement != 'host disposal',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Nested confirmation'), findsNothing);
      expect(find.text('Synthetic retired client'), findsNothing);
      expect(dispatches, 0);
      expect(changes, [false]);
      await tester.pumpWidget(view(second));
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(changes, [false, false]);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(changes, [false, false, true]);
      expect(find.byType(Dialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
