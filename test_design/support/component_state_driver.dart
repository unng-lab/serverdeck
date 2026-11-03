import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real traversal and pointer input. State names never replace user events.
Future<Future<void> Function()> driveComponentState(
  WidgetTester tester,
  String state,
) async {
  if (state == 'focus') {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.hasFocus, true);
    expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
    return () async {};
  }
  if (state != 'hover' && state != 'pressed') return () async {};
  Finder controls = find.byWidgetPredicate(
    (widget) =>
        widget is ButtonStyleButton && widget.onPressed != null ||
        widget is IconButton && widget.onPressed != null,
  );
  if (controls.evaluate().isEmpty) {
    controls = find.byWidgetPredicate(
      (widget) => widget is InkWell && widget.onTap != null,
    );
  }
  expect(
    controls,
    findsWidgets,
    reason: '$state requires an enabled real control',
  );
  final target = controls.first;
  await tester.ensureVisible(target);
  await tester.pump();
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(-10, -10));
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 200));
  if (state == 'pressed') {
    await mouse.down(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 100));
  }
  return () async {
    if (state == 'pressed') await mouse.cancel();
    await mouse.removePointer();
    await tester.pump();
  };
}
