import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/wire.dart';
import 'package:test/test.dart';

const generation = '12345678-1234-4234-8234-123456789abc';
final buildId = '${'a' * 40}+Debug+${'b' * 64}';
String nonce(int byte) =>
    base64Url.encode(List.filled(32, byte)).replaceAll('=', '');
const workspaceId = '12345678-1234-4234-8234-123456789abd';
const grantId = '12345678-1234-4234-8234-123456789abe';
const secretRef = '12345678-1234-4234-8234-123456789abf';
const expiry = '2027-01-01T00:00:00.000Z';

OperationalHello hello({OperationalRole role = OperationalRole.mcp}) =>
    OperationalHello(
      generation: generation,
      serverNonce: nonce(1),
      buildId: buildId,
      clientRole: role,
    );
OperationalAuthenticate authentication() => OperationalAuthenticate(
  clientNonce: nonce(2),
  clientBuildId: buildId,
  requestedCapabilities: ['mcp'],
  proof: nonce(0),
);
OperationalAuthenticated authenticated({
  OperationalRole role = OperationalRole.mcp,
}) => OperationalAuthenticated(
  sessionId: nonce(3),
  clientRole: role,
  capabilities: [role.name],
  proof: nonce(0),
);
McpOpenRequest openRequest() =>
    McpOpenRequest(grantId: grantId, clientNonce: nonce(4), proof: nonce(0));
McpOpenResult openResult({int revision = 7}) => McpOpenResult(
  workspaceId: workspaceId,
  grantId: grantId,
  revision: revision,
  expiresAt: expiry,
  proof: nonce(0),
);
OperationalBootstrapTranscript bootstrap({
  OperationalHello? source,
  String? clientNonce,
}) {
  final value = source ?? hello();
  return OperationalBootstrapTranscript(
    hello: value,
    clientNonce: clientNonce ?? nonce(2),
    requestedCapabilities: [value.clientRole.name],
  );
}

McpOpenTranscript openTranscript({
  OperationalHello? source,
  String? workspace,
  String? session,
  String? clientNonce,
  String? grant,
  String? secret,
}) => McpOpenTranscript(
  hello: source ?? hello(),
  workspaceId: workspace ?? workspaceId,
  sessionId: session ?? nonce(3),
  clientNonce: clientNonce ?? nonce(4),
  grantId: grant ?? grantId,
  secretRef: secret ?? secretRef,
);
Matcher get invalid => throwsA(
  isA<FormatException>()
      .having((e) => e.message, 'safe message', 'VALIDATION')
      .having((e) => e.source, 'no source', isNull)
      .having((e) => e.offset, 'no offset', isNull),
);
Map<String, Object?> body(Map<String, Object?> doc, String key) =>
    Map<String, Object?>.of(doc[key] as Map<String, Object?>);
String macHex(List<int> bytes) {
  final key = SecretKeyData(
    List.generate(32, (i) => i),
    overwriteWhenDestroyed: true,
  );
  try {
    return DartHmac.sha256()
        .calculateMacSync(bytes, secretKeyData: key, nonce: const [])
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  } finally {
    key.destroy();
  }
}

void main() {
  test('operational hello explicitly binds API1.1, image role and build', () {
    final hello = OperationalHello(
      generation: generation,
      serverNonce: nonce(1),
      buildId: buildId,
      clientRole: OperationalRole.mcp,
    );
    expect((hello.toJson()['hello'] as Map)['apiMinor'], 1);
    expect(
      OperationalHello.fromJson(hello.toJson()).clientRole,
      OperationalRole.mcp,
    );
  });

  test('each message has closed required fields and safe invalid errors', () {
    final docs = <Map<String, Object?>>[
      hello().toJson(),
      authentication().toJson(),
      authenticated().toJson(),
      openRequest().toJson(),
      openResult().toJson(),
    ];
    final parse = <Object Function(Object?)>[
      OperationalHello.fromJson,
      OperationalAuthenticate.fromJson,
      OperationalAuthenticated.fromJson,
      McpOpenRequest.fromJson,
      McpOpenResult.fromJson,
    ];
    for (var i = 0; i < docs.length; i++) {
      final doc = docs[i];
      expect(() => parse[i](doc), returnsNormally);
      for (final bad in [
        null,
        [],
        'private payload',
        1,
        true,
        {...doc, 'unknown': 'private payload'},
      ]) {
        expect(() => parse[i](bad), invalid);
      }
      final wrapper = i < 3
          ? ['hello', 'authenticate', 'authenticated'][i]
          : null;
      final inner = wrapper == null ? doc : body(doc, wrapper);
      for (final key in inner.keys) {
        final removed = Map<String, Object?>.of(inner)..remove(key);
        final nulled = {...inner, key: null};
        for (final bad in [
          removed,
          nulled,
          {...inner, 'unknown': 'private payload'},
        ]) {
          expect(
            () => parse[i](wrapper == null ? bad : {wrapper: bad}),
            invalid,
            reason: 'packet$i/$key',
          );
        }
      }
    }
  });

  test('identity, integer versions, image role and build syntax are exact', () {
    final original = body(hello().toJson(), 'hello');
    for (final entry in <String, List<Object?>>{
      'product': ['other', 'SERVERDECK-NEXT'],
      'apiMajor': [1.0, '1', 0, 2],
      'apiMinor': [1.0, '1', 0, 2],
      'workspaceSlot': ['other', 'DEFAULT'],
      'generation': [
        '12345678-1234-4234-8234-123456789abC',
        'x',
        generation.toUpperCase(),
      ],
      'clientRole': ['locald', 'Owner', 'MCP', 1, {}],
      'buildId': [
        '',
        'a' * 114,
        buildId.toUpperCase(),
        '$buildId\n',
        buildId.replaceFirst('Debug', 'debug'),
      ],
    }.entries) {
      for (final value in entry.value) {
        expect(
          () => OperationalHello.fromJson({
            'hello': {...original, entry.key: value},
          }),
          invalid,
        );
      }
    }
    expect(
      () => OperationalHello(
        generation: generation,
        serverNonce: nonce(1),
        buildId: buildId.replaceFirst('Debug', 'Release'),
        clientRole: OperationalRole.owner,
      ),
      returnsNormally,
    );
    for (final value in [60.0, '60', 59, 61]) {
      expect(
        () => OperationalAuthenticated.fromJson({
          'authenticated': {
            ...body(authenticated().toJson(), 'authenticated'),
            'idleLeaseSeconds': value,
          },
        }),
        invalid,
      );
    }
  });

  test(
    'capability singletons are copied, immutable and contextually role-bound',
    () {
      for (final role in OperationalRole.values) {
        final caps = [role.name];
        final a = OperationalAuthenticate(
          clientNonce: nonce(2),
          clientBuildId: buildId,
          requestedCapabilities: caps,
          proof: nonce(0),
        );
        final b = OperationalAuthenticated(
          sessionId: nonce(3),
          clientRole: role,
          capabilities: caps,
          proof: nonce(0),
        );
        final c = OperationalBootstrapTranscript(
          hello: hello(role: role),
          clientNonce: nonce(2),
          requestedCapabilities: caps,
        );
        caps[0] = 'changed';
        expect(a.requestedCapabilities, [role.name]);
        expect(b.capabilities, [role.name]);
        expect(c.requestedCapabilities, [role.name]);
        expect(() => a.requestedCapabilities.clear(), throwsUnsupportedError);
        expect(() => b.capabilities.clear(), throwsUnsupportedError);
        expect(() => c.requestedCapabilities.clear(), throwsUnsupportedError);
        (a.toJson()['authenticate'] as Map)['requestedCapabilities'] = [];
        (b.toJson()['authenticated'] as Map)['capabilities'] = [];
        expect(a.requestedCapabilities, [role.name]);
        expect(b.capabilities, [role.name]);
        expect(c.serverBytes(b), isNotEmpty);
      }
      final source = body(authentication().toJson(), 'authenticate');
      for (final value in [
        [],
        ['mcp', 'mcp'],
        ['mcp', 'owner'],
        ['owner', 'mcp'],
        ['profiles.read'],
        ['executor.run'],
        [1],
        'mcp',
        [null],
      ]) {
        expect(
          () => OperationalAuthenticate.fromJson({
            'authenticate': {...source, 'requestedCapabilities': value},
          }),
          invalid,
        );
      }
      expect(
        () => OperationalAuthenticated(
          sessionId: nonce(3),
          clientRole: OperationalRole.owner,
          capabilities: ['mcp'],
          proof: nonce(0),
        ),
        invalid,
      );
      expect(
        () => OperationalBootstrapTranscript(
          hello: hello(),
          clientNonce: nonce(2),
          requestedCapabilities: ['owner'],
        ),
        invalid,
      );
      expect(
        () =>
            bootstrap().serverBytes(authenticated(role: OperationalRole.owner)),
        invalid,
      );
      final mutable = ['mcp'];
      final doc = {
        'authenticate': {...source, 'requestedCapabilities': mutable},
      };
      final parsed = OperationalAuthenticate.fromJson(doc);
      mutable.clear();
      doc.clear();
      expect(parsed.requestedCapabilities, ['mcp']);
      (parsed.toJson()['authenticate'] as Map)['requestedCapabilities'].clear();
      expect(parsed.requestedCapabilities, ['mcp']);
    },
  );

  test(
    'all nonce/proof/session encodings reject noncanonical padding bits',
    () {
      final docs = [
        hello().toJson(),
        authentication().toJson(),
        authenticated().toJson(),
        openRequest().toJson(),
        openResult().toJson(),
      ];
      final parse = <Object Function(Object?)>[
        OperationalHello.fromJson,
        OperationalAuthenticate.fromJson,
        OperationalAuthenticated.fromJson,
        McpOpenRequest.fromJson,
        McpOpenResult.fromJson,
      ];
      for (var i = 0; i < docs.length; i++) {
        final wrapper = i < 3
            ? ['hello', 'authenticate', 'authenticated'][i]
            : null;
        final source = wrapper == null ? docs[i] : body(docs[i], wrapper);
        for (final key in source.keys.where(
          (k) =>
              ['serverNonce', 'clientNonce', 'sessionId', 'proof'].contains(k),
        )) {
          for (final bad in [
            '',
            nonce(0) + '=',
            'A' * 42,
            'A' * 44,
            '${'A' * 42}B',
            '${'A' * 42}/',
            '${'A' * 42}+',
            '$key\n',
            32,
          ]) {
            final altered = {...source, key: bad};
            expect(
              () => parse[i](wrapper == null ? altered : {wrapper: altered}),
              invalid,
            );
          }
        }
      }
    },
  );

  test(
    'grant result shares ClientGrant revision and canonical timestamp bounds',
    () {
      expect(openResult(revision: 2147483647).revision, 2147483647);
      expect(
        openTranscript().serverBytes(openResult(revision: 2147483647)),
        isNotEmpty,
      );
      for (final revision in [
        0,
        -1,
        2147483648,
        9223372036854775807,
        7.0,
        '7',
      ]) {
        expect(
          () => McpOpenResult.fromJson({
            ...openResult().toJson(),
            'revision': revision,
          }),
          invalid,
        );
      }
      for (final time in [
        '2027-01-01T00:00:00Z',
        '2027-01-01T00:00:00.000+00:00',
        '2027-02-30T00:00:00.000Z',
        '2027-01-01T00:00:00.000001Z',
        'private',
      ]) {
        expect(
          () => McpOpenResult.fromJson({
            ...openResult().toJson(),
            'expiresAt': time,
          }),
          invalid,
        );
      }
      for (final key in ['workspaceId', 'grantId']) {
        expect(
          () => McpOpenResult.fromJson({...openResult().toJson(), key: 'bad'}),
          invalid,
        );
      }
      // Parsing historical metadata does not evaluate live authority/expiry.
      expect(
        () => McpOpenResult.fromJson({
          ...openResult().toJson(),
          'expiresAt': '2000-01-01T00:00:00.000Z',
        }),
        returnsNormally,
      );
    },
  );

  test('every bounded decode rejects duplicate keys/UTF8/oversize safely', () {
    final decode = <Object Function(List<int>)>[
      OperationalHello.decode,
      OperationalAuthenticate.decode,
      OperationalAuthenticated.decode,
      McpOpenRequest.decode,
      McpOpenResult.decode,
    ];
    final docs = [
      hello().toJson(),
      authentication().toJson(),
      authenticated().toJson(),
      openRequest().toJson(),
      openResult().toJson(),
    ];
    for (var i = 0; i < decode.length; i++) {
      expect(() => decode[i](StrictCodec().encode(docs[i])), returnsNormally);
      for (final bytes in <List<int>>[
        [],
        [-1],
        [256],
        [0xff],
        List.filled(8193, 32),
        utf8.encode('[]'),
        utf8.encode('{"private":"value","private":2}'),
        utf8.encode('null'),
        utf8.encode('{"private":"\\ud800"}'),
        utf8.encode('{"private":1e999}'),
        utf8.encode('{'),
      ]) {
        expect(() => decode[i](bytes), invalid);
      }
      final json = utf8.decode(StrictCodec().encode(docs[i]));
      // A duplicate key nested inside an otherwise valid message must not be lost.
      final key = i < 3
          ? ['hello', 'authenticate', 'authenticated'][i]
          : 'grantId';
      final duplicate = json.replaceFirst('"$key":', '"$key":null,"$key":');
      expect(() => decode[i](utf8.encode(duplicate)), invalid);
    }
  });

  test(
    'operational and legacy handshake packets mutually refuse each other',
    () {
      final oldHello = ServerHello(
        generation: generation,
        serverNonce: nonce(1),
      );
      final oldAuth = Authenticate(
        clientNonce: nonce(2),
        clientBuildId: buildId,
        requestedCapabilities: ['readiness.read'],
        proof: nonce(0),
      );
      final oldGranted = Authenticated(
        sessionId: nonce(3),
        capabilities: ['readiness.read'],
        proof: nonce(0),
      );
      validateHello(oldHello.toJson());
      validateAuthenticate(oldAuth.toJson());
      validateAuthenticated(oldGranted.toJson());
      expect(() => OperationalHello.fromJson(oldHello.toJson()), invalid);
      expect(() => OperationalAuthenticate.fromJson(oldAuth.toJson()), invalid);
      expect(
        () => OperationalAuthenticated.fromJson(oldGranted.toJson()),
        invalid,
      );
      expect(() => validateHello(hello().toJson()), throwsFormatException);
      expect(
        () => validateAuthenticate(authentication().toJson()),
        throwsFormatException,
      );
      expect(
        () => validateAuthenticated(authenticated().toJson()),
        throwsFormatException,
      );
    },
  );

  test('four exact canonical and HMAC vectors are independently fixed', () {
    // Generated with Python stdlib JSON/HMAC, independently checked using .NET
    // HMACSHA256. The fixture/key are synthetic; no runtime or Python dependency.
    final vectors = jsonDecode(
      File('test/fixtures/mcp_handshake_vectors.json').readAsStringSync(),
    ) as Map;
    final actual = {
      'bootstrapClient': bootstrap().clientBytes(),
      'bootstrapServer': bootstrap().serverBytes(authenticated()),
      'openClient': openTranscript().clientBytes(),
      'openServer': openTranscript().serverBytes(openResult()),
    };
    for (final entry in actual.entries) {
      expect(
        utf8.decode(entry.value),
        vectors[entry.key]['canonical'],
        reason: entry.key,
      );
      expect(
        macHex(entry.value),
        vectors[entry.key]['hmacSha256'],
        reason: entry.key,
      );
      // Returned transcript buffers are fresh and don't mutate future proofs.
      entry.value.fillRange(0, entry.value.length, 0);
    }
    expect(
      macHex(bootstrap().clientBytes()),
      vectors['bootstrapClient']['hmacSha256'],
    );
    expect(
      macHex(openTranscript().clientBytes()),
      vectors['openClient']['hmacSha256'],
    );
    expect(
      macHex(bootstrap().clientBytes()),
      isNot(macHex(bootstrap().serverBytes(authenticated()))),
    );
    expect(
      macHex(openTranscript().clientBytes()),
      isNot(macHex(openTranscript().serverBytes(openResult()))),
    );
    final old =
        'client\n1\ndefault\n$generation\n${nonce(1)}\n${nonce(2)}\n$buildId\nmcp';
    expect(macHex(utf8.encode(old)), isNot(macHex(bootstrap().clientBytes())));
  });

  test('every bootstrap binding dimension changes the proof or is refused', () {
    final base = macHex(bootstrap().clientBytes());
    final original = body(hello().toJson(), 'hello');
    for (final change in [
      {'generation': workspaceId},
      {'serverNonce': nonce(9)},
      {'buildId': buildId.replaceFirst('Debug', 'Release')},
      {'clientRole': 'owner'},
    ]) {
      final altered = OperationalHello.fromJson({
        'hello': {...original, ...change},
      });
      expect(macHex(bootstrap(source: altered).clientBytes()), isNot(base));
    }
    expect(macHex(bootstrap(clientNonce: nonce(9)).clientBytes()), isNot(base));
    final response = body(authenticated().toJson(), 'authenticated');
    final serverBase = macHex(bootstrap().serverBytes(authenticated()));
    expect(
      macHex(
        bootstrap().serverBytes(
          OperationalAuthenticated.fromJson({
            'authenticated': {...response, 'sessionId': nonce(9)},
          }),
        ),
      ),
      isNot(serverBase),
    );
    // The proof itself is excluded from the signed transcript.
    expect(
      bootstrap().serverBytes(
        OperationalAuthenticated.fromJson({
          'authenticated': {...response, 'proof': nonce(9)},
        }),
      ),
      bootstrap().serverBytes(authenticated()),
    );
  });

  test('open binds lookup secretRef without guessing a pre-open revision', () {
    final baseline = macHex(openTranscript().clientBytes());
    final current =
        jsonDecode(utf8.decode(openTranscript().clientBytes())) as Map;
    expect(current.containsKey('revision'), isFalse);
    expect(current.containsKey('grantRevision'), isFalse);
    for (final context in [
      openTranscript(workspace: generation),
      openTranscript(session: nonce(9)),
      openTranscript(clientNonce: nonce(9)),
      openTranscript(grant: generation),
      openTranscript(secret: generation),
      openTranscript(
        source: OperationalHello(
          generation: workspaceId,
          serverNonce: nonce(1),
          buildId: buildId,
          clientRole: OperationalRole.mcp,
        ),
      ),
      openTranscript(
        source: OperationalHello(
          generation: generation,
          serverNonce: nonce(9),
          buildId: buildId,
          clientRole: OperationalRole.mcp,
        ),
      ),
      openTranscript(
        source: OperationalHello(
          generation: generation,
          serverNonce: nonce(1),
          buildId: buildId.replaceFirst('Debug', 'Release'),
          clientRole: OperationalRole.mcp,
        ),
      ),
    ]) {
      expect(macHex(context.clientBytes()), isNot(baseline));
    }
    final signed = macHex(openTranscript().serverBytes(openResult()));
    expect(
      macHex(openTranscript().serverBytes(openResult(revision: 8))),
      isNot(signed),
    );
    expect(
      macHex(
        openTranscript().serverBytes(
          McpOpenResult.fromJson({
            ...openResult().toJson(),
            'expiresAt': '2027-01-02T00:00:00.000Z',
          }),
        ),
      ),
      isNot(signed),
    );
    for (final field in ['workspaceId', 'grantId']) {
      expect(
        () => openTranscript().serverBytes(
          McpOpenResult.fromJson({...openResult().toJson(), field: generation}),
        ),
        invalid,
      );
    }
    expect(
      () => openTranscript(source: hello(role: OperationalRole.owner)),
      invalid,
    );
    for (final action in <Object Function()>[
      () => openTranscript(workspace: 'bad'),
      () => openTranscript(session: 'bad'),
      () => openTranscript(clientNonce: 'bad'),
      () => openTranscript(grant: 'bad'),
      () => openTranscript(secret: 'bad'),
      () => bootstrap(clientNonce: 'bad'),
    ]) {
      expect(action, invalid);
    }
  });
}
