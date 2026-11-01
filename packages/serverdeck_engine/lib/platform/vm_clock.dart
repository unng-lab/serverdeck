import 'dart:developer' show Timeline;

import 'ports.dart';

/// Shared process epoch for native Dart VM worker/UI deadlines. Unlike a local
/// Stopwatch origin, this value can cross an in-process isolate queue unchanged.
final class VmEngineClock implements EngineClock {
  @override
  Duration get elapsed => Duration(microseconds: Timeline.now);
  @override
  DateTime get utcNow => DateTime.now().toUtc();
}
