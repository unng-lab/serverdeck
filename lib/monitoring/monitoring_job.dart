import 'linux_metrics.dart';

/// Application-owned cancellation handle. No socket, command or raw output API.
final class MonitoringJob {
  const MonitoringJob(this.result, this._cancel);
  final Future<LinuxSample> result;
  final void Function() _cancel;
  void cancel() => _cancel();
}
