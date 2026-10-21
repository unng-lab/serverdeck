import 'dart:typed_data';

import '../automation/models.dart' show requireAutomationRevision;
import '../automation/values.dart' show automationTimestamp;
import '../codec.dart';
import '../protocol.dart' show maxHandshakeBytes;
import '../validation.dart' show requireNonce, requireUuid;

/// Wire vocabulary only. Authority comes from the retained native connection,
/// never a caller-constructed DTO or transcript.
enum OperationalRole { owner, mcp }

Never _invalid() => throw const FormatException('VALIDATION');

Map<String, Object?> _object(Object? value, Set<String> fields) {
  if (value is! Map<String, Object?> ||
      value.length != fields.length ||
      !fields.containsAll(value.keys)) {
    _invalid();
  }
  return value;
}

Map<String, Object?> _body(Object? value, String name, Set<String> fields) =>
    _object(_object(value, {name})[name], fields);

void _exact(Object? value, Object expected) {
  if (value.runtimeType != expected.runtimeType || value != expected)
    _invalid();
}

Map<String, Object?> _decode(List<int> bytes) {
  if (bytes.isEmpty ||
      bytes.length > maxHandshakeBytes ||
      bytes.any((b) => b < 0 || b > 255)) {
    _invalid();
  }
  try {
    return StrictCodec().decode(bytes, maxBytes: maxHandshakeBytes);
  } on FormatException {
    _invalid();
  }
}

String _nonce(Object? value) {
  try {
    requireNonce(value);
  } on FormatException {
    // A base64 decoder may retain malformed proof bytes as exception.source.
    _invalid();
  }
  return value as String;
}

String _build(Object? value) {
  if (value is! String ||
      value.length > 113 ||
      !RegExp(r'^[a-f0-9]{40}\+(Debug|Release)\+[a-f0-9]{64}$')
          .hasMatch(value)) {
    _invalid();
  }
  return value;
}

OperationalRole _role(Object? value) => switch (value) {
  'owner' => OperationalRole.owner,
  'mcp' => OperationalRole.mcp,
  _ => _invalid(),
};

List<String> _caps(Object? value, [OperationalRole? role]) {
  if (value is! List || value.length != 1) _invalid();
  final name = value.single;
  final parsed = _role(name);
  if (role != null && parsed != role) _invalid();
  return List<String>.unmodifiable([parsed.name]);
}

const _identity = <String, Object?>{
  'product': 'serverdeck-next',
  'apiMajor': 1,
  'apiMinor': 1,
  'workspaceSlot': 'default',
};

final class OperationalHello {
  factory OperationalHello({
    required String generation,
    required String serverNonce,
    required String buildId,
    required OperationalRole clientRole,
  }) => OperationalHello.fromJson({
    'hello': {
      ..._identity,
      'generation': generation,
      'serverNonce': serverNonce,
      'buildId': buildId,
      'clientRole': clientRole.name,
    },
  });

  factory OperationalHello.fromJson(Object? value) {
    final body = _body(value, 'hello', {
      ..._identity.keys,
      'generation',
      'serverNonce',
      'buildId',
      'clientRole',
    });
    for (final entry in _identity.entries) {
      _exact(body[entry.key], entry.value!);
    }
    return OperationalHello._(
      requireUuid(body['generation']),
      _nonce(body['serverNonce']),
      _build(body['buildId']),
      _role(body['clientRole']),
    );
  }

  factory OperationalHello.decode(List<int> bytes) =>
      OperationalHello.fromJson(_decode(bytes));

  OperationalHello._(
    this.generation,
    this.serverNonce,
    this.buildId,
    this.clientRole,
  );
  final String generation, serverNonce, buildId;
  final OperationalRole clientRole;

  Map<String, Object?> toJson() => {
    'hello': {
      ..._identity,
      'generation': generation,
      'serverNonce': serverNonce,
      'buildId': buildId,
      'clientRole': clientRole.name,
    },
  };
}

final class OperationalAuthenticate {
  factory OperationalAuthenticate({
    required String clientNonce,
    required String clientBuildId,
    required List<String> requestedCapabilities,
    required String proof,
  }) => OperationalAuthenticate.fromJson({
    'authenticate': {
      'clientNonce': clientNonce,
      'clientBuildId': clientBuildId,
      'requestedCapabilities': List<String>.of(requestedCapabilities),
      'proof': proof,
    },
  });

  factory OperationalAuthenticate.fromJson(Object? value) {
    final body = _body(value, 'authenticate', {
      'clientNonce',
      'clientBuildId',
      'requestedCapabilities',
      'proof',
    });
    return OperationalAuthenticate._(
      _nonce(body['clientNonce']),
      _build(body['clientBuildId']),
      _caps(body['requestedCapabilities']),
      _nonce(body['proof']),
    );
  }

  factory OperationalAuthenticate.decode(List<int> bytes) =>
      OperationalAuthenticate.fromJson(_decode(bytes));

  OperationalAuthenticate._(
    this.clientNonce,
    this.clientBuildId,
    this.requestedCapabilities,
    this.proof,
  );
  final String clientNonce, clientBuildId, proof;
  final List<String> requestedCapabilities;

  Map<String, Object?> toJson() => {
    'authenticate': {
      'clientNonce': clientNonce,
      'clientBuildId': clientBuildId,
      'requestedCapabilities': List<String>.of(requestedCapabilities),
      'proof': proof,
    },
  };
}

final class OperationalAuthenticated {
  factory OperationalAuthenticated({
    required String sessionId,
    required OperationalRole clientRole,
    required List<String> capabilities,
    required String proof,
  }) => OperationalAuthenticated.fromJson({
    'authenticated': {
      'sessionId': sessionId,
      'clientRole': clientRole.name,
      'capabilities': List<String>.of(capabilities),
      'idleLeaseSeconds': 60,
      'proof': proof,
    },
  });

  factory OperationalAuthenticated.fromJson(Object? value) {
    final body = _body(value, 'authenticated', {
      'sessionId',
      'clientRole',
      'capabilities',
      'idleLeaseSeconds',
      'proof',
    });
    _exact(body['idleLeaseSeconds'], 60);
    final role = _role(body['clientRole']);
    return OperationalAuthenticated._(
      _nonce(body['sessionId']),
      role,
      _caps(body['capabilities'], role),
      _nonce(body['proof']),
    );
  }

  factory OperationalAuthenticated.decode(List<int> bytes) =>
      OperationalAuthenticated.fromJson(_decode(bytes));

  OperationalAuthenticated._(
    this.sessionId,
    this.clientRole,
    this.capabilities,
    this.proof,
  );
  final String sessionId, proof;
  final OperationalRole clientRole;
  final List<String> capabilities;

  Map<String, Object?> toJson() => {
    'authenticated': {
      'sessionId': sessionId,
      'clientRole': clientRole.name,
      'capabilities': List<String>.of(capabilities),
      'idleLeaseSeconds': 60,
      'proof': proof,
    },
  };
}

/// Parameters of mcp.open, not an authenticated grant or key reference.
final class McpOpenRequest {
  factory McpOpenRequest({
    required String grantId,
    required String clientNonce,
    required String proof,
  }) => McpOpenRequest.fromJson({
    'grantId': grantId,
    'clientNonce': clientNonce,
    'proof': proof,
  });

  factory McpOpenRequest.fromJson(Object? value) {
    final body = _object(value, {'grantId', 'clientNonce', 'proof'});
    return McpOpenRequest._(
      requireUuid(body['grantId']),
      _nonce(body['clientNonce']),
      _nonce(body['proof']),
    );
  }

  factory McpOpenRequest.decode(List<int> bytes) =>
      McpOpenRequest.fromJson(_decode(bytes));
  McpOpenRequest._(this.grantId, this.clientNonce, this.proof);
  final String grantId, clientNonce, proof;
  Map<String, Object?> toJson() => {
    'grantId': grantId,
    'clientNonce': clientNonce,
    'proof': proof,
  };
}

/// Structurally valid result only. Its proof/current policy must still be checked.
final class McpOpenResult {
  factory McpOpenResult({
    required String workspaceId,
    required String grantId,
    required int revision,
    required String expiresAt,
    required String proof,
  }) => McpOpenResult.fromJson({
    'workspaceId': workspaceId,
    'grantId': grantId,
    'revision': revision,
    'expiresAt': expiresAt,
    'proof': proof,
  });

  factory McpOpenResult.fromJson(Object? value) {
    final body = _object(value, {
      'workspaceId',
      'grantId',
      'revision',
      'expiresAt',
      'proof',
    });
    automationTimestamp(body['expiresAt']);
    return McpOpenResult._(
      requireUuid(body['workspaceId']),
      requireUuid(body['grantId']),
      requireAutomationRevision(body['revision']),
      body['expiresAt'] as String,
      _nonce(body['proof']),
    );
  }

  factory McpOpenResult.decode(List<int> bytes) =>
      McpOpenResult.fromJson(_decode(bytes));
  McpOpenResult._(
    this.workspaceId,
    this.grantId,
    this.revision,
    this.expiresAt,
    this.proof,
  );
  final String workspaceId, grantId, expiresAt, proof;
  final int revision;
  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    'grantId': grantId,
    'revision': revision,
    'expiresAt': expiresAt,
    'proof': proof,
  };
}

/// Pure, immutable transcript context; carries no verified identity or key.
final class OperationalBootstrapTranscript {
  factory OperationalBootstrapTranscript({
    required OperationalHello hello,
    required String clientNonce,
    required List<String> requestedCapabilities,
  }) => OperationalBootstrapTranscript._(
    hello,
    _nonce(clientNonce),
    _caps(List<String>.of(requestedCapabilities), hello.clientRole),
  );
  OperationalBootstrapTranscript._(
    this.hello,
    this.clientNonce,
    this.requestedCapabilities,
  );
  final OperationalHello hello;
  final String clientNonce;
  final List<String> requestedCapabilities;

  Map<String, Object?> _fields(String purpose) => {
    ..._identity,
    'purpose': purpose,
    'generation': hello.generation,
    'buildId': hello.buildId,
    'clientRole': hello.clientRole.name,
    'serverNonce': hello.serverNonce,
    'clientNonce': clientNonce,
    'requestedCapabilities': List<String>.of(requestedCapabilities),
  };

  Uint8List clientBytes() => Uint8List.fromList(
    StrictCodec().canonical(_fields('serverdeck-next-bootstrap-client-v1.1')),
  );

  Uint8List serverBytes(OperationalAuthenticated response) {
    if (response.clientRole != hello.clientRole) _invalid();
    _caps(response.capabilities, hello.clientRole);
    return Uint8List.fromList(
      StrictCodec().canonical({
        ..._fields('serverdeck-next-bootstrap-server-v1.1'),
        'sessionId': response.sessionId,
        'capabilities': List<String>.of(response.capabilities),
        'idleLeaseSeconds': 60,
      }),
    );
  }
}

/// Inputs obtained independently from protected lookup (bridge) or current
/// committed grant (locald). This context never establishes live authorization.
final class McpOpenTranscript {
  factory McpOpenTranscript({
    required OperationalHello hello,
    required String workspaceId,
    required String sessionId,
    required String clientNonce,
    required String grantId,
    required String secretRef,
  }) {
    if (hello.clientRole != OperationalRole.mcp) _invalid();
    return McpOpenTranscript._(
      hello,
      requireUuid(workspaceId),
      _nonce(sessionId),
      _nonce(clientNonce),
      requireUuid(grantId),
      requireUuid(secretRef),
    );
  }
  McpOpenTranscript._(
    this.hello,
    this.workspaceId,
    this.sessionId,
    this.clientNonce,
    this.grantId,
    this.secretRef,
  );
  final OperationalHello hello;
  final String workspaceId, sessionId, clientNonce, grantId, secretRef;

  Map<String, Object?> _fields(String purpose) => {
    ..._identity,
    'purpose': purpose,
    'workspaceId': workspaceId,
    'generation': hello.generation,
    'buildId': hello.buildId,
    'clientRole': 'mcp',
    'sessionId': sessionId,
    'serverNonce': hello.serverNonce,
    'clientNonce': clientNonce,
    'grantId': grantId,
    'secretRef': secretRef,
  };

  Uint8List clientBytes() => Uint8List.fromList(
    StrictCodec().canonical(_fields('serverdeck-next-mcp-open-client-v1.1')),
  );

  Uint8List serverBytes(McpOpenResult response) {
    if (response.workspaceId != workspaceId || response.grantId != grantId)
      _invalid();
    return Uint8List.fromList(
      StrictCodec().canonical({
        ..._fields('serverdeck-next-mcp-open-server-v1.1'),
        'revision': response.revision,
        'expiresAt': response.expiresAt,
      }),
    );
  }
}
