import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/app.dart';
import 'package:serverdeck/bootstrap/bootstrap_controller.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';

class ClosingClient extends LocalApiClient {
  ClosingClient() : super(connect: () => throw StateError('UNUSED'));
  final gate = Completer<void>();
  int closes = 0;
  @override
  Future<void> close() async {
    closes++;
    await gate.future;
    await super.close();
  }
}

void main() {
  for (final failing in [false, true]) {
    testWidgets('native exit waits for one close; failing=$failing', (
      tester,
    ) async {
      final client = ClosingClient();
      final bootstrap = BootstrapController(
        client: client,
        prepare: () async {},
        ensureService: () async {},
      );
      await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
      AppExitResponse? response;
      final exit = tester.binding.handleRequestAppExit().then((value) {
        response = value;
      });
      await tester.pump();
      expect(client.closes, 1);
      expect(response, isNull);
      // Disposal during the pending native exit must not close resources twice.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(client.closes, 1);
      if (failing) {
        client.gate.completeError(StateError('TRANSPORT_CLOSE_FAILED'));
      } else {
        client.gate.complete();
      }
      await tester.pump();
      await exit;
      expect(response, AppExitResponse.exit);
      expect(client.closes, 1);
    });
  }
}
