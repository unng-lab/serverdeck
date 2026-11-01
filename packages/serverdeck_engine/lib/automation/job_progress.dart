import 'package:serverdeck_protocol/automation/models.dart';

/// Data-only CAS retry used by the actual driver. Native/root/actor evidence is
/// checked by its caller. These callbacks neither mint nor restore authority.
/// Production ports read the shared store and call its actual queued writer.
Future<AutomationJobRecord> publishJobProgress({
  required String mode,
  required String state,
  required Future<AutomationJobRecord> Function() readCurrent,
  required Future<AutomationJobRecord> Function(
    AutomationJobRecord previous,
    String nextState,
  )
  compareAndSwap,
}) async {
  if (!{'apply', 'cancel', 'reconcile'}.contains(mode))
    throw ArgumentError('INVALID_DRIVER_MODE');
  while (true) {
    final previous = await readCurrent();
    // This predicate belongs to the CAS iteration, including every retry.
    // A newer accepted reconciliation owns its phase; an older mode cannot
    // overwrite it or publish unknown directly terminal.
    if (mode != 'reconcile' &&
        (previous.state == 'reconciling' ||
            previous.state == 'unknown' &&
                {'succeeded', 'failed', 'cancelled'}.contains(state)))
      return previous;
    if ({'succeeded', 'failed', 'cancelled'}.contains(previous.state))
      return previous;
    if (previous.state == 'unknown' && state == 'unknown') return previous;
    final nextState = previous.cancelRequested && state == 'running'
        ? 'cancel-requested'
        : state;
    try {
      return await compareAndSwap(previous, nextState);
    } on StateError catch (error) {
      if (error.message != 'REVISION_CONFLICT') rethrow;
    }
  }
}
