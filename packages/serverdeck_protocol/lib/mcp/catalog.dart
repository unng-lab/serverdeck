import '../automation/models.dart';
import '../codec.dart';

typedef _Schema = Map<String, Object?>;

const _uuid = <String, Object?>{
  'type': 'string',
  'pattern':
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
};
const _digest = <String, Object?>{
  'type': 'string',
  'pattern': r'^[a-f0-9]{64}$',
};
const _revision = <String, Object?>{
  'type': 'integer',
  'minimum': 1,
  'maximum': 2147483647,
};
const _boolean = <String, Object?>{'type': 'boolean'};
const _refresh = <String, Object?>{'type': 'boolean', 'default': false};
const _cursor = <String, Object?>{
  'type': 'string',
  'minLength': 1,
  'maxLength': 512,
};
const _resource = <String, Object?>{
  'type': 'string',
  'pattern': r'^[a-z][a-z0-9_.-]{0,63}$',
};
const _identifier = <String, Object?>{
  'type': 'string',
  'pattern': r'^[a-z][a-z0-9_]{0,31}$',
};
const _timestamp = <String, Object?>{
  'type': 'string',
  'format': 'date-time',
  'pattern': r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
};
const _publicString = <String, Object?>{'type': 'string', 'maxLength': 4096};
const _integerValue = <String, Object?>{
  'type': 'integer',
  'minimum': 0,
  'maximum': 1000000,
};
const _listFields = <String, _Schema>{
  'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100, 'default': 50},
  'cursor': _cursor,
};

_Schema _object(Map<String, _Schema> fields, [Set<String>? required]) => {
  'type': 'object',
  'properties': fields,
  'required': (required ?? fields.keys.toSet()).toList(),
  'additionalProperties': false,
};

_Schema _reference(_Schema value) => {
  'oneOf': [
    value,
    _object({'param': _identifier}),
  ],
};

_Schema _parametersSchema() => {
  'type': 'object',
  'maxProperties': 32,
  'propertyNames': _identifier,
  'additionalProperties': {
    'oneOf': [_boolean, _integerValue, _publicString],
  },
};

_Schema _profileBody() => _object({
  'format': {'const': 1},
  'environment': {'const': 'ubuntu24.04-amd64-systemd'},
  'parameters': {
    'type': 'object',
    'maxProperties': 32,
    'propertyNames': _identifier,
    'additionalProperties': {
      'oneOf': [
        _object({
          'type': {'const': 'boolean'},
          'default': _boolean,
        }),
        _object({
          'type': {'const': 'integer'},
          'minimum': _integerValue,
          'maximum': _integerValue,
          'default': _integerValue,
        }),
        _object({
          'type': {'const': 'enum'},
          'values': {
            'type': 'array',
            'minItems': 1,
            'maxItems': 32,
            'uniqueItems': true,
            'items': {'type': 'string', 'minLength': 1, 'maxLength': 64},
          },
          'default': {'type': 'string', 'minLength': 1, 'maxLength': 64},
        }),
        _object({
          'type': {'const': 'string'},
          'maxLength': {'type': 'integer', 'minimum': 1, 'maximum': 4096},
          'default': _publicString,
        }),
      ],
    },
  },
  'steps': {
    'type': 'array',
    'maxItems': 32,
    'description': 'Unique step IDs/resources, parameter references and resource schemas are also checked by ServerDeck.',
    'items': {
      'oneOf': [
        _object(
          {
            'id': _identifier,
            'kind': {'const': 'service'},
            'resourceId': _resource,
            'state': _reference({
              'type': 'string',
              'enum': ['started', 'stopped', 'restarted'],
            }),
            'enabled': _reference(_boolean),
          },
          {'id', 'kind', 'resourceId', 'state'},
        ),
        _object({
          'id': _identifier,
          'kind': {'const': 'config_file'},
          'resourceId': _resource,
          'values': {
            'type': 'object',
            'maxProperties': 32,
            'propertyNames': _identifier,
            'additionalProperties': _reference({
              'oneOf': [
                _boolean,
                {'type': 'integer'},
                _publicString,
              ],
              'description': 'Literal bounds are checked against the registered resource; declared parameter ranges remain separately bounded.',
            }),
          },
        }),
        _object({
          'id': _identifier,
          'kind': {'const': 'install_recipe'},
          'recipeDigest': _digest,
          'version': _reference({
            'type': 'string',
            'minLength': 1,
            'maxLength': 256,
          }),
        }),
      ],
    },
  },
});

final _resultSchema =
    _object(
        {
          'ok': _boolean,
          'data': {'type': 'object'},
          'error': _object({
            'code': {'type': 'string'},
            'boundary': {
              'type': 'string',
              'enum': ['local', 'remote', 'executor'],
            },
            'retry': {
              'type': 'string',
              'enum': [
                'none',
                'reload',
                'reconnect',
                'retry-same-request',
                'manual-recovery',
              ],
            },
          }),
          'requestId': _uuid,
        },
        {'ok'},
      )
      ..['oneOf'] = [
        {
          'properties': {
            'ok': {'const': true},
          },
          'required': ['data'],
          'not': {
            'anyOf': [
              {
                'required': ['error'],
              },
              {
                'required': ['requestId'],
              },
            ],
          },
        },
        {
          'properties': {
            'ok': {'const': false},
          },
          'required': ['error'],
          'not': {
            'required': ['data'],
          },
        },
      ];

/// Discovery metadata, never an alternative to locald's live authorization.
final class McpToolDefinition {
  McpToolDefinition._(
    String suffix,
    this.description,
    Set<McpScope> scopes,
    _Schema input, {
    this.readOnly = true,
  }) : name = 'serverdeck_$suffix',
       requiredScopes = Set.unmodifiable(scopes),
       _inputBytes = List.unmodifiable(
         StrictCodec().encode(_compactInput(input)),
       );

  final String name, description;
  final Set<McpScope> requiredScopes;
  final bool readOnly;
  final List<int> _inputBytes;
  _Schema get inputSchema => StrictCodec().decode(_inputBytes);

  _Schema toJson() => {
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
    'outputSchema': StrictCodec().decode(StrictCodec().encode(_resultSchema)),
    'annotations': {'readOnlyHint': readOnly, 'openWorldHint': true},
  };
}

// Hoist only the deeply nested author inputs. Each definition refers only to
// earlier definitions, so the emitted fixed local graph is deterministic/acyclic.
_Schema _compactInput(_Schema input) {
  if (!(input['properties'] as Map).containsKey('body')) return input;
  final definitions = <String, Object?>{};
  _Schema visit(_Schema schema, {bool root = false}) {
    final transformed = <String, Object?>{};
    for (final entry in schema.entries) {
      final value = entry.value;
      if (entry.key == 'properties') {
        transformed[entry.key] = (value as Map<String, Object?>).map(
          (key, schema) => MapEntry(key, visit(schema as _Schema)),
        );
      } else if (entry.key == 'oneOf') {
        transformed[entry.key] = (value as List)
            .map((s) => visit(s as _Schema))
            .toList();
      } else if (const {
            'additionalProperties',
            'propertyNames',
            'items',
          }.contains(entry.key) &&
          value is _Schema) {
        transformed[entry.key] = visit(value);
      } else {
        transformed[entry.key] = value;
      }
    }
    if (root) return {...transformed, r'$defs': definitions};
    final name = 's${definitions.length}';
    definitions[name] = transformed;
    return {r'$ref': '#/\$defs/$name'};
  }

  return visit(input, root: true);
}

McpToolDefinition _tool(
  String name,
  String description,
  Set<McpScope> scopes,
  Map<String, _Schema> fields, {
  Set<String>? required,
  bool readOnly = true,
}) => McpToolDefinition._(
  name,
  description,
  scopes,
  _object(fields, required),
  readOnly: readOnly,
);

final List<McpToolDefinition> mcpTools = List.unmodifiable([
  _tool(
    'servers_list',
    'List only explicitly permitted servers.',
    {McpScope.read},
    _listFields,
    required: {},
  ),
  _tool(
    'server_get',
    'Read one permitted server profile and capabilities.',
    {McpScope.read},
    {'serverId': _uuid},
  ),
  _tool(
    'server_connect',
    'Connect with existing owner-confirmed trust; never accept a host key.',
    {McpScope.read},
    {'serverId': _uuid},
    readOnly: false,
  ),
  _tool(
    'server_disconnect',
    'Release this client interest without cancelling jobs or other clients.',
    {McpScope.read},
    {'serverId': _uuid},
    readOnly: false,
  ),
  _tool(
    'state_get',
    'Read observed OS, software and resources with freshness and completeness.',
    {McpScope.read},
    {'serverId': _uuid, 'refresh': _refresh},
    required: {'serverId'},
  ),
  _tool(
    'configuration_get',
    'Compare saved desired state and observed managed configuration.',
    {McpScope.read},
    {'serverId': _uuid, 'resourceId': _resource, 'refresh': _refresh},
    required: {'serverId', 'resourceId'},
  ),
  _tool(
    'logs_read',
    'Read bounded untrusted journal data with explicit gaps and cursor.',
    {McpScope.logs},
    {
      'serverId': _uuid,
      'unit': _resource,
      'since': _timestamp,
      'until': _timestamp,
      'priority': {'type': 'integer', 'minimum': 0, 'maximum': 7},
      'text': {'type': 'string', 'maxLength': 256},
      'limit': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 1000,
        'default': 100,
      },
      'cursor': _cursor,
    },
    required: {'serverId'},
  ),
  _tool(
    'profiles_list',
    'List authorable workspace automation profiles.',
    {McpScope.author},
    {..._listFields, 'includeArchived': _refresh},
    required: {},
  ),
  _tool(
    'profiles_get',
    'Read immutable automation content and revision identity.',
    {McpScope.author},
    {'profileId': _uuid, 'revision': _revision},
    required: {'profileId'},
  ),
  _tool(
    'profiles_create',
    'Save a new declarative automation profile; does not grant execution.',
    {McpScope.author},
    {
      'requestId': _uuid,
      'name': {'type': 'string', 'minLength': 1, 'maxLength': 100},
      'description': {'type': 'string', 'maxLength': 2000},
      'body': _profileBody(),
    },
    required: {'requestId', 'name', 'body'},
    readOnly: false,
  ),
  _tool(
    'profiles_update',
    'Create a new immutable revision using optimistic concurrency.',
    {McpScope.author},
    {
      'requestId': _uuid,
      'profileId': _uuid,
      'expectedRevision': _revision,
      'name': {'type': 'string', 'minLength': 1, 'maxLength': 100},
      'description': {'type': 'string', 'maxLength': 2000},
      'body': _profileBody(),
    },
    required: {'requestId', 'profileId', 'expectedRevision', 'body'},
    readOnly: false,
  ),
  _tool(
    'profiles_compare',
    'Compare two saved immutable revisions without executing them.',
    {McpScope.author},
    {'profileId': _uuid, 'fromRevision': _revision, 'toRevision': _revision},
  ),
  _tool(
    'profiles_validate',
    'Validate declarative content; no remote effects or execution.',
    {McpScope.author},
    {'body': _profileBody()},
  ),
  _tool(
    'profiles_archive',
    'Archive a profile without deleting referenced history.',
    {McpScope.author},
    {'requestId': _uuid, 'profileId': _uuid, 'expectedRevision': _revision},
    readOnly: false,
  ),
  _tool(
    'recipes_list',
    'List exact qualified installation recipes and prerequisites.',
    {McpScope.plan},
    {'serverId': _uuid},
  ),
  _tool(
    'plan_create',
    'Build an immutable exact-target plan with no server changes.',
    {McpScope.plan},
    {
      'requestId': _uuid,
      'serverId': _uuid,
      'profileId': _uuid,
      'revision': _revision,
      'parameters': _parametersSchema(),
    },
    readOnly: false,
  ),
  _tool(
    'plans_get',
    'Read this client immutable plan and prerequisites.',
    {McpScope.plan},
    {'planId': _uuid},
  ),
  _tool(
    'approval_request',
    'Request owner consent; cannot approve or expand authority.',
    {McpScope.plan, McpScope.apply},
    {'requestId': _uuid, 'planId': _uuid},
    readOnly: false,
  ),
  _tool(
    'apply',
    'Admit one durable job under exact owner authority; no automatic replay.',
    {McpScope.plan, McpScope.apply},
    {'requestId': _uuid, 'planId': _uuid},
    readOnly: false,
  ),
  _tool(
    'jobs_list',
    'List only this client jobs on currently allowed servers.',
    {McpScope.read},
    {'serverId': _uuid, ..._listFields},
    required: {},
  ),
  _tool(
    'jobs_get',
    'Read durable job status and post-check results.',
    {McpScope.read},
    {'jobId': _uuid},
  ),
  _tool(
    'jobs_events',
    'Read ordered bounded job events, including dropped progress.',
    {McpScope.read},
    {
      'jobId': _uuid,
      'after': {
        'type': 'integer',
        'minimum': 0,
        'maximum': 9223372036854775807,
        'default': 0,
      },
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100, 'default': 50},
    },
    required: {'jobId'},
  ),
  _tool(
    'jobs_cancel',
    'Request a safe stop; already committed effects may finish.',
    {McpScope.apply},
    {'requestId': _uuid, 'jobId': _uuid},
    readOnly: false,
  ),
  _tool(
    'jobs_reconcile',
    'Inspect the previous attempt without running a new playbook.',
    {McpScope.read},
    {'requestId': _uuid, 'jobId': _uuid},
    readOnly: false,
  ),
]);

McpToolDefinition? mcpTool(String name) {
  for (final tool in mcpTools) {
    if (tool.name == name) return tool;
  }
  return null;
}

Iterable<McpToolDefinition> mcpToolsFor(GrantScopePolicy policy) =>
    mcpTools.where((tool) => policy.scopes.containsAll(tool.requiredScopes));
