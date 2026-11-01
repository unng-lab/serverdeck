import 'package:serverdeck_engine/hosting/engine_host.dart';
import 'package:serverdeck_engine/hosting/worker_controller.dart';
import 'package:serverdeck_windows/engine_worker.dart';

import 'engine_client.dart';

/// One UI window borrows the process root's single engine incarnation. Closing
/// its client detaches interest; application Exit uses the separate Host shutdown.
final class DesktopEngineHost {
  DesktopEngineHost({EngineWorkerController? engine})
    : engine = engine ?? desktopEngineController() {
    client = EngineApiClient(
      attach: () => this.engine.openOwner(_window),
      detach: () => this.engine.detachOwner(_window),
    );
  }
  final EngineWorkerController engine;
  final Object _window = Object();
  late final EngineApiClient client;
  Future<WorkerStatus> start() async {
    final initial = await engine.start();
    // Busy is a durable explanation after contender cleanup; lifecycle status
    // must reflect the controller now, not its historical initial start reply.
    return initial.phase == 'busy' ? initial : engine.status;
  }

  Future<HostCloseResult> shutdown() => engine.shutdown();
  Future<HostCloseResult> waitForClose() => engine.waitForClose();
  Future<void> close() => client.close();
}
