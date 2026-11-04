import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_view.dart';
import 'package:serverdeck/theme/brand_theme.dart';

import 'monitoring_harness.dart';

final class MonitoringProfileOperations extends Fake implements AppOperations {
  MonitoringProfileOperations(this.h);
  final MonitoringHarness h;
  final trusts = <String, TrustView>{};
  int manualConnects = 0, disconnects = 0;
  final selected = <String>[];
  @override
  Future<OperationResult<ProfilesPage>> listProfiles(
    Actor actor, {
    int limit = 50,
    String? cursor,
  }) => h.operations.listProfiles(actor, limit: limit, cursor: cursor);
  TrustView trust(String id) =>
      trusts[id] ??
      const TrustView(trustRevision: 1, observationRevision: 1, changed: false);
  @override
  Future<OperationResult<TrustView>> getTrust(Actor actor, String id) async =>
      OperationResult.success(trust(id), h.operations.meta);
  @override
  Future<OperationResult<ProfileDetails>> getProfile(
    Actor actor,
    String id,
  ) async {
    selected.add(id);
    final found = h.operations.items.where((p) => p.profileId == id);
    if (found.isEmpty)
      return const OperationResult.failure(
        OperationFailure(FailureCode.profileNotFound),
      );
    return OperationResult.success(
      ProfileDetails(
        profile: found.single,
        connection: h.port.connection(id),
        trust: trust(id),
      ),
      h.operations.meta,
    );
  }

  @override
  Future<OperationResult<ConnectionView>> connect(
    Actor actor,
    String id, {
    required int expectedRevision,
  }) async {
    manualConnects++;
    h.port.connected(id);
    h.port.emit();
    return OperationResult.success(h.port.connection(id), h.operations.meta);
  }

  @override
  Future<OperationResult<ConnectionView>> disconnect(
    Actor actor,
    String id, {
    required String sessionId,
  }) async {
    disconnects++;
    h.port.generations[id] = h.port.generation(id) + 1;
    h.port.views[id] = const ConnectionView(
      state: ConnectionState.disconnected,
    );
    h.port.emit();
    return OperationResult.success(h.port.connection(id), h.operations.meta);
  }
}

final class MonitoringWidgetHarness {
  MonitoringWidgetHarness({bool autoAllowed = true})
    : h = MonitoringHarness(autoAllowed: autoAllowed) {
    operations = MonitoringProfileOperations(h);
    controller = ProfileController(
      operations: operations,
      actor: h.actors.ui,
      newId: () => mid(8000),
      poll: false,
      onAction: () => unawaited(h.owner.reconcile()),
    );
  }
  final MonitoringHarness h;
  late final MonitoringProfileOperations operations;
  late final ProfileController controller;
  Widget get widget => MaterialApp(
    theme: BrandTheme.dark,
    home: Scaffold(
      body: ProfileViewPanel(
        controller: controller,
        monitoring: h.owner,
        pickKey: () async => null,
      ),
    ),
  );
  Future<void> mount(WidgetTester tester) async {
    h.owner.setActive(true);
    await h.owner.reconcile();
    await controller.refresh();
    await tester.pumpWidget(widget);
    await tester.pump();
  }

  Future<void> tick(WidgetTester tester, int seconds) async {
    h.clock.advance(Duration(seconds: seconds));
    await h.owner.reconcile();
    await tester.pump();
  }

  // Cancel pending fake-zone jobs while the widget test is still pumping.
  Future<void> finish(WidgetTester tester) async {
    final stop = h.owner.stopAdmission();
    await tester.pumpWidget(const SizedBox.shrink());
    await stop;
    await tester.pump();
    await h.owner.drain();
  }

  Future<void> dispose() async {
    controller.dispose();
    await h.dispose();
  }
}
