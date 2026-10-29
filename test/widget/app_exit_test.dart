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
    for (final disposeWhilePending in [true, false]) {
      testWidgets(
        '${disposeWhilePending ? 'application exit callback with disposal' : 'registered binding exit while mounted'} waits for one close; failing=$failing',
        (tester) async {
          final client = ClosingClient();
          final bootstrap = BootstrapController(
            client: client,
            prepare: () async {},
            ensureService: () async {},
          );
          await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
          final app = tester.state(find.byType(FoundationApp));
          final observer = app as WidgetsBindingObserver;
          AppExitResponse? response;
          // The SDK snapshots every observer before awaiting each one. Disposing
          // the tree during that dispatch also disposes later EditableText lifecycle
          // listeners in its snapshot. The disposal race here exercises the public
          // application callback; the mounted branch separately verifies real
          // binding registration and dispatch without that unrelated SDK race.
          final exit =
              (disposeWhilePending
                      ? observer.didRequestAppExit()
                      : tester.binding.handleRequestAppExit())
                  .then((value) {
                    response = value;
                  });
          await tester.pump();
          expect(client.closes, 1);
          expect(response, isNull);
          if (disposeWhilePending) {
            await tester.pumpWidget(const SizedBox.shrink());
            expect(app.mounted, isFalse);
          } else {
            expect(app.mounted, isTrue);
          }
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
          expect(tester.takeException(), isNull);
          if (!disposeWhilePending) {
            await tester.pumpWidget(const SizedBox.shrink());
            expect(app.mounted, isFalse);
            expect(client.closes, 1);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
