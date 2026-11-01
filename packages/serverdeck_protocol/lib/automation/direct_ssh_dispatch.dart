import 'dart:convert';

import '../codec.dart';
import '../validation.dart';
import 'values.dart';

/// Durable metadata for one already-authorized dispatch, never authority by
/// itself. Live actors, target and selected consent are checked by the driver.
final class DirectSshDispatch {
  DirectSshDispatch._(this._json);

  factory DirectSshDispatch.fromJson(Map<String, Object?> input) {
    final value = StrictCodec().decode(
      StrictCodec().encode(input, maxBytes: 4096),
      maxBytes: 4096,
    );
    requireFields(value, {
      'format',
      'stepId',
      'stepDigest',
      'token',
      'bootIdHash',
      'issuedUptimeMs',
      'expiresUptimeMs',
      'authorityBindingDigest',
      'targetBindingDigest',
      'authorizedAt',
      'grantRevision',
      'grantExpiresAt',
      'state',
    });
    if (value['format'] is! int || value['format'] != 1) {
      invalidAutomationValue();
    }
    automationIdentifier(value['stepId']);
    requireUuid(value['token']);
    for (final field in [
      'stepDigest',
      'bootIdHash',
      'authorityBindingDigest',
      'targetBindingDigest',
    ]) {
      if (value[field] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value[field] as String)) {
        invalidAutomationValue();
      }
    }
    validateWindow(
      issuedUptimeMs: value['issuedUptimeMs'],
      expiresUptimeMs: value['expiresUptimeMs'],
    );
    final authorized = automationTimestamp(value['authorizedAt']);
    final revision = value['grantRevision'],
        grantExpiry = value['grantExpiresAt'];
    if ((revision == null) != (grantExpiry == null) ||
        revision != null &&
            (revision is! int || revision < 1 || revision > 2147483647)) {
      invalidAutomationValue();
    }
    if (grantExpiry != null) {
      final expires = automationTimestamp(grantExpiry);
      if (!expires.isAfter(authorized) ||
          (value['expiresUptimeMs'] as int) - (value['issuedUptimeMs'] as int) >
              expires.difference(authorized).inMilliseconds) {
        invalidAutomationValue();
      }
    }
    if (!const {
      'authorized',
      'sent',
      'completed',
      'unknown',
    }.contains(value['state'])) {
      invalidAutomationValue();
    }
    return DirectSshDispatch._(jsonEncode(value));
  }

  final String _json;
  static void validateWindow({
    required Object? issuedUptimeMs,
    required Object? expiresUptimeMs,
  }) {
    if (issuedUptimeMs is! int ||
        expiresUptimeMs is! int ||
        issuedUptimeMs < 0 ||
        expiresUptimeMs > 9223372036854775807 ||
        expiresUptimeMs <= issuedUptimeMs ||
        expiresUptimeMs - issuedUptimeMs > 5000) {
      invalidAutomationValue();
    }
  }

  Map<String, Object?> toJson() => jsonDecode(_json) as Map<String, Object?>;
  String get stepId => toJson()['stepId'] as String;
  String get stepDigest => toJson()['stepDigest'] as String;
  String get token => toJson()['token'] as String;
  String get bootIdHash => toJson()['bootIdHash'] as String;
  String get authorityBindingDigest =>
      toJson()['authorityBindingDigest'] as String;
  String get targetBindingDigest => toJson()['targetBindingDigest'] as String;
  int get issuedUptimeMs => toJson()['issuedUptimeMs'] as int;
  int get expiresUptimeMs => toJson()['expiresUptimeMs'] as int;
  String get state => toJson()['state'] as String;
  DateTime get authorizedAt => automationTimestamp(toJson()['authorizedAt']);
  int? get grantRevision => toJson()['grantRevision'] as int?;
  DateTime? get grantExpiresAt => toJson()['grantExpiresAt'] == null
      ? null
      : automationTimestamp(toJson()['grantExpiresAt']);

  /// A clock/boot predicate only. It neither issues a permit nor permits replay.
  bool canStartAt(String currentBootHash, int uptimeMs) =>
      const {'authorized', 'sent'}.contains(state) &&
      currentBootHash == bootIdHash &&
      uptimeMs >= issuedUptimeMs &&
      uptimeMs <= expiresUptimeMs;

  void validateTransitionTo(DirectSshDispatch next) {
    final previousIdentity = toJson()..remove('state');
    final nextIdentity = next.toJson()..remove('state');
    if (StrictCodec().canonical(previousIdentity).toString() !=
        StrictCodec().canonical(nextIdentity).toString()) {
      invalidAutomationValue();
    }
    const edges = {
      'authorized': {'sent', 'completed', 'unknown'},
      'sent': {'completed', 'unknown'},
      'unknown': {'completed'},
      'completed': <String>{},
    };
    if (state != next.state && !edges[state]!.contains(next.state)) {
      invalidAutomationValue();
    }
  }

  @override
  String toString() => 'DirectSshDispatch';
}
