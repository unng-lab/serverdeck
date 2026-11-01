import 'package:serverdeck_protocol/validation.dart';

import 'in_process_gateway.dart';

/// Private VM root intent, not an external RPC, owner grant or persisted record.
final class WorkerPowerIntent {
  WorkerPowerIntent(this.epoch, this.suspended, this.expiresAt) {
    if (epoch < 1 ||
        epoch > 0x7fffffffffffffff ||
        expiresAt < 1 ||
        expiresAt > 0x7fffffffffffffff) {
      throw EngineCallFailure('VALIDATION');
    }
  }
  factory WorkerPowerIntent.fromFrame(Object? value) {
    if (value is! Map<String, Object?>) throw EngineCallFailure('VALIDATION');
    requireFields(value, {'kind', 'epoch', 'suspended', 'expiresAt'});
    if (value['kind'] != 'power' ||
        value['epoch'] is! int ||
        value['suspended'] is! bool ||
        value['expiresAt'] is! int) {
      throw EngineCallFailure('VALIDATION');
    }
    return WorkerPowerIntent(
      value['epoch'] as int,
      value['suspended'] as bool,
      value['expiresAt'] as int,
    );
  }
  final int epoch, expiresAt;
  final bool suspended;
  Map<String, Object?> toFrame() => {
    'kind': 'power',
    'epoch': epoch,
    'suspended': suspended,
    'expiresAt': expiresAt,
  };
}

/// Bounded pre-mailbox controls. Power coalesces separately and precedes begin,
/// so the worker cannot open storage/publication before seeing the early intent.
final class WorkerStartupQueue {
  final _ordinary = <Map<String, Object?>>[];
  WorkerPowerIntent? _power;
  void add(Map<String, Object?> frame) {
    if (frame['kind'] == 'power') {
      final next = WorkerPowerIntent.fromFrame(frame);
      if (_power == null || next.epoch > _power!.epoch) _power = next;
      return;
    }
    if (_ordinary.length >= 26) throw EngineCallFailure('RESOURCE_LIMIT');
    _ordinary.add(Map.unmodifiable(frame));
  }

  List<Map<String, Object?>> takeForStart() {
    final result = <Map<String, Object?>>[
      if (_power != null) _power!.toFrame(),
      const {'kind': 'begin'},
      ..._ordinary,
    ];
    clear();
    return result;
  }

  void clear() {
    _ordinary.clear();
    _power = null;
  }
}
