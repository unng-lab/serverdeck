import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/automation/values.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../storage/state_store.dart';

/// Internal owner-adapter input, never an authentication capability. No wire
/// route is enabled here; the verified Local API owner gate remains required.
final class OwnerGrantCommand {
  OwnerGrantCommand._(
    this.operation,
    this.requestId,
    this.grantId,
    this.expectedRevision,
    this.label,
    this.policy,
    this.lifetimeSeconds,
  );

  factory OwnerGrantCommand.parse(
    String operation,
    Map<String, Object?> input,
  ) {
    if (!{'grant.create', 'grant.replace', 'grant.revoke'}.contains(operation))
      throw const FormatException('VALIDATION');
    // Validate original types/text before canonical encoding: canonical JSON can
    // normalize decomposed strings or integral doubles, which must not turn an
    // invalid request into valid input. Parsed immutable fields capture input
    // synchronously, with no caller-owned list retained across an await.
    final value = input;
    final revoke = operation == 'grant.revoke';
    requireFields(
      value,
      {
        'requestId',
        'grantId',
        if (operation != 'grant.create') 'expectedRevision',
        if (!revoke) ...{'label', 'scopes', 'serverIds'},
      },
      {if (!revoke) 'lifetimeSeconds'},
    );
    final request = requireUuid(value['requestId']),
        grant = requireUuid(value['grantId']);
    final revision = operation == 'grant.create'
        ? null
        : requireAutomationRevision(value['expectedRevision']);
    final lifetime = revoke
        ? null
        : value.containsKey('lifetimeSeconds')
        ? value['lifetimeSeconds']
        : 28800;
    if (!revoke && (lifetime is! int || lifetime < 300 || lifetime > 2592000))
      throw const FormatException('VALIDATION');
    final policy = revoke
        ? null
        : GrantScopePolicy.fromJson({
            'scopes': value['scopes'],
            'serverIds': value['serverIds'],
          });
    final label = revoke
        ? null
        : automationText(value['label'], min: 1, max: 100);
    StrictCodec().encode(value, maxBytes: 16384);
    return OwnerGrantCommand._(
      operation,
      request,
      grant,
      revision,
      label,
      policy,
      lifetime as int?,
    );
  }

  final String operation, requestId, grantId;
  final int? expectedRevision, lifetimeSeconds;
  final String? label;
  final GrantScopePolicy? policy;

  Map<String, Object?> get canonicalRequest => {
    'operation': operation,
    'originGrantId': null,
    'params': {
      'grantId': grantId,
      if (expectedRevision != null) 'expectedRevision': expectedRevision,
      if (policy != null) ...{
        'label': label,
        'scopes': policy!.toJson()['scopes'],
        'serverIds': policy!.serverIds.toList()..sort(),
        'lifetimeSeconds': lifetimeSeconds,
      },
    },
  };
}

final class OwnerGrantService {
  OwnerGrantService(this.store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final StateStore store;
  final DateTime Function() _clock;

  Future<Map<String, Object?>> submitOwner(
    String operation,
    Map<String, Object?> input,
  ) {
    try {
      return store.mutateOwnerGrant(
        OwnerGrantCommand.parse(operation, input),
        clock: _clock,
      );
    } on FormatException {
      return Future.error(StateError('VALIDATION'));
    } catch (_) {
      return Future.error(StateError('STORAGE_BLOCKED'));
    }
  }
}
