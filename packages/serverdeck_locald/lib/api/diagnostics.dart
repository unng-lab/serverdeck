import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';

enum DiagnosticStage {
  bootstrap,
  identity,
  handshake,
  storage,
  request,
  shutdown,
}

class DiagnosticEvent {
  const DiagnosticEvent({
    required this.timestamp,
    required this.code,
    required this.stage,
    required this.duration,
    this.requestId,
    this.generation,
  });
  final DateTime timestamp;
  final ErrorCode code;
  final DiagnosticStage stage;
  final Duration duration;
  final String? requestId, generation;
  Map<String, Object?> toJson() {
    try {
      if (requestId != null) requireUuid(requestId);
      if (generation != null) requireUuid(generation);
    } on FormatException {
      throw ArgumentError('INVALID_DIAGNOSTIC');
    }
    if (duration.isNegative) {
      throw ArgumentError('INVALID_DIAGNOSTIC');
    }
    return {
      'timestamp': timestamp.toUtc().toIso8601String(),
      'code': code.wireName,
      'stage': stage.name,
      'duration': duration.inMilliseconds,
      if (requestId != null) 'requestId': requestId,
      if (generation != null) 'generation': generation,
    };
  }
}
