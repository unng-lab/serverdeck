import '../domain/actor.dart';
import '../domain/models.dart';
import '../runtime/owned_work.dart';
import 'monitoring_job.dart';

/// Immutable internal receipt distinguishes interrupted admission from failure.
final class MonitoringConnectResult {
  const MonitoringConnectResult(
    this.operation, {
    this.cancelledBeforeAdmission = false,
  });
  final OperationResult<ConnectionView> operation;
  final bool cancelledBeforeAdmission;
}

/// Internal owner capability, never exposed by AppOperations or MCP.
abstract interface class MonitoringConnectionPort {
  Stream<void> get changes;
  ConnectionView connection(String profileId);
  int generation(String profileId);
  Future<MonitoringConnectResult> connectForMonitoring(
    UiActor actor,
    String profileId, {
    required int expectedRevision,
    required WorkCancellation cancellation,
  });
  MonitoringJob beginMonitoring(
    UiActor actor,
    String profileId,
    String sessionId, {
    required int expectedConnectionRevision,
    required WorkCancellation cancellation,
  });
}
