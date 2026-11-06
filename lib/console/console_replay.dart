import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/models.dart';
import 'console_models.dart';

/// Memory-only mutation receipts. Authorization belongs to the owner and must
/// precede every lookup, including a replay. No input or output text is retained.
final class ConsoleReplayBook {
  ConsoleReplayBook(this.ownerEpoch);
  final String ownerEpoch;
  final _principals = <(String, int), _Principal>{};

  int next(String clientId, int grantVersion) {
    final highWater = _principals[(clientId, grantVersion)]?.highWater ?? 0;
    if (highWater >= 9007199254740991)
      throw const OperationFailure(FailureCode.resourceExhausted);
    return highWater + 1;
  }

  ConsoleActionValue? begin(
    String clientId,
    int grantVersion,
    String epoch,
    int sequence,
    Map<String, Object?> payload,
  ) {
    if (epoch != ownerEpoch || sequence < 1 || sequence > 9007199254740991) {
      throw const OperationFailure(FailureCode.conflict);
    }
    final key = (clientId, grantVersion);
    var principal = _principals[key];
    if (principal == null) {
      if (_principals.length >= 64) {
        throw const OperationFailure(FailureCode.resourceExhausted);
      }
      if (sequence != 1) throw const OperationFailure(FailureCode.conflict);
      principal = _principals[key] = _Principal();
    }
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(_canonical(payload))))
        .toString();
    if (sequence <= principal.highWater) {
      final receipt = principal.receipts[sequence];
      if (receipt == null) {
        throw const OperationFailure(FailureCode.consoleReplayExpired);
      }
      if (receipt.fingerprint != fingerprint) {
        throw const OperationFailure(FailureCode.conflict);
      }
      if (!receipt.finished) {
        throw const OperationFailure(FailureCode.conflict, retryable: true);
      }
      if (receipt.failure case final failure?) throw failure;
      return receipt.value!.asReplay();
    }
    if (sequence != principal.highWater + 1 || principal.pending != null) {
      throw const OperationFailure(FailureCode.conflict);
    }
    principal.highWater = sequence;
    principal.pending = sequence;
    principal.receipts[sequence] = _Receipt(fingerprint);
    while (principal.receipts.length > 64) {
      principal.receipts.remove(principal.receipts.keys.first);
    }
    return null;
  }

  void complete(
    String clientId,
    int grantVersion,
    int sequence,
    ConsoleActionValue value,
  ) {
    final receipt = _finish(clientId, grantVersion, sequence);
    if (utf8.encode(jsonEncode(value.toJson())).length > 4096) {
      receipt.failure = const OperationFailure(FailureCode.resourceExhausted);
    } else {
      receipt.value = value;
    }
  }

  void fail(
    String clientId,
    int grantVersion,
    int sequence,
    OperationFailure failure,
  ) {
    _finish(clientId, grantVersion, sequence).failure = failure;
  }

  _Receipt _finish(String clientId, int grantVersion, int sequence) {
    final principal = _principals[(clientId, grantVersion)]!;
    if (principal.pending != sequence)
      throw StateError('No pending console mutation');
    principal.pending = null;
    final receipt = principal.receipts[sequence]!;
    receipt.finished = true;
    return receipt;
  }

  static Object? _canonical(Object? value) {
    if (value is Map<String, Object?>) {
      final keys = value.keys.toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return [for (final item in value) _canonical(item)];
    return value;
  }
}

final class _Principal {
  int highWater = 0;
  int? pending;
  final receipts = LinkedHashMap<int, _Receipt>();
}

final class _Receipt {
  _Receipt(this.fingerprint);
  final String fingerprint;
  bool finished = false;
  ConsoleActionValue? value;
  OperationFailure? failure;
}
