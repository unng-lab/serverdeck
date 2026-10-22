import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/automation/values.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/validation.dart';

/// Captured internal input, never an authentication capability. The shared
/// service derives origin from an actual native actor before storage admission.
final class AutomationProfileCommand {
  AutomationProfileCommand._(
    this.operation,
    this.requestId,
    this.profileId,
    this.expectedRevision,
    this.name,
    this.description,
    this.body,
  );

  factory AutomationProfileCommand.parse(
    String operation,
    Map<String, Object?> input,
  ) {
    if (!{
      'profile.create',
      'profile.update',
      'profile.archive',
    }.contains(operation)) {
      throw const FormatException('VALIDATION');
    }
    final create = operation == 'profile.create',
        archive = operation == 'profile.archive';
    requireFields(
      input,
      {
        'requestId',
        if (!create) ...{'profileId', 'expectedRevision'},
        if (create) 'name',
        if (!archive) 'body',
      },
      {if (!archive) 'description', if (!create && !archive) 'name'},
    );
    final requestId = requireUuid(input['requestId']);
    final profileId = create ? null : requireUuid(input['profileId']);
    final revision = create
        ? null
        : requireAutomationRevision(input['expectedRevision']);
    final name = input.containsKey('name')
        ? automationText(input['name'], min: 1, max: 100)
        : null;
    final description = input.containsKey('description')
        ? automationText(input['description'], max: 2000, multiline: true)
        : create
        ? ''
        : null;
    AutomationBody? body;
    if (!archive) {
      final raw = input['body'];
      if (raw is! Map<String, Object?>)
        throw const FormatException('VALIDATION');
      body = AutomationBody.fromJson(raw);
    }
    StrictCodec().encode(input, maxBytes: 256 * 1024);
    return AutomationProfileCommand._(
      operation,
      requestId,
      profileId,
      revision,
      name,
      description,
      body,
    );
  }

  final String operation, requestId;
  final String? profileId, name, description;
  final int? expectedRevision;
  final AutomationBody? body;

  Map<String, Object?> canonicalRequest(String? originGrantId) => {
    'operation': operation,
    'originGrantId': originGrantId,
    'params': {
      if (profileId != null) 'profileId': profileId,
      if (expectedRevision != null) 'expectedRevision': expectedRevision,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (body != null) 'body': body!.toJson(),
    },
  };
}
