import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/validation.dart';

class DiscoveryNamespace {
  DiscoveryNamespace._(this.hash);
  final String hash;
  static Future<DiscoveryNamespace> forOwner(String sid) async {
    if (!RegExp(r'^S-1-\d+(?:-\d+)+$').hasMatch(sid))
      throw StateError('STORAGE_BLOCKED');
    final digest = await Sha256().hash(utf8.encode('${sid}default'));
    return DiscoveryNamespace._(
      digest.bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join(),
    );
  }

  String get mutexName => 'Global\\ServerDeckNext.v1.$hash';
  List<String> get pipeNames => List.unmodifiable(
    List.generate(8, (slot) => '\\\\.\\pipe\\ServerDeckNext.v1.$hash.$slot'),
  );
}

class DiscoveryDescriptor {
  DiscoveryDescriptor._(
    this._ownerSid,
    this.buildId,
    this.serverPid,
    this.generation,
    this.workspaceId,
    this.pipeNames,
    List<int> token,
  ) : _token = Uint8List.fromList(token);
  final String _ownerSid, buildId, generation;
  String get ownerSid => _ownerSid;
  final int serverPid;
  final String? workspaceId;
  final List<String> pipeNames;
  final Uint8List _token;
  bool _closed = false;
  bool get isClosed => _closed;
  List<int> get bootstrapToken {
    _open();
    return List<int>.of(_token);
  }

  void _open() {
    if (_closed) throw StateError('STORAGE_BLOCKED');
  }

  static final _build = RegExp(
    r'^[0-9a-f]{40}\+(Debug|Release)\+[0-9a-f]{64}$',
  );
  static Future<DiscoveryDescriptor> create({
    required String ownerSid,
    required String buildId,
    required int serverPid,
  }) async {
    if (!_build.hasMatch(buildId) || serverPid < 1 || serverPid > 0xffffffff)
      throw StateError('INCOMPATIBLE');
    final namespace = await DiscoveryNamespace.forOwner(ownerSid);
    final random = Random.secure();
    final id = List.generate(16, (_) => random.nextInt(256));
    id[6] = (id[6] & 15) | 64;
    id[8] = (id[8] & 63) | 128;
    final hex = id.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    final generation =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    return DiscoveryDescriptor._(
      ownerSid,
      buildId,
      serverPid,
      generation,
      null,
      namespace.pipeNames,
      List.generate(32, (_) => random.nextInt(256)),
    );
  }

  List<int> encode() {
    _open();
    return StrictCodec().encode({
      'format': 1,
      'product': 'serverdeck-next',
      'apiMajor': 1,
      'apiMinor': 0,
      'workspaceSlot': 'default',
      'workspaceId': workspaceId,
      'generation': generation,
      'bootstrapToken': base64Url.encode(_token).replaceAll('=', ''),
      'buildId': buildId,
      'serverPid': serverPid,
      'pipeNames': pipeNames,
    }, maxBytes: 8192);
  }

  static Future<DiscoveryDescriptor> decode(
    List<int> bytes, {
    required String ownerSid,
    required String expectedBuildId,
  }) async {
    Uint8List? token;
    try {
      final value = StrictCodec().decode(bytes, maxBytes: 8192);
      requireFields(value, {
        'format',
        'product',
        'apiMajor',
        'apiMinor',
        'workspaceSlot',
        'workspaceId',
        'generation',
        'bootstrapToken',
        'buildId',
        'serverPid',
        'pipeNames',
      });
      for (final version in {
        'format': 1,
        'apiMajor': 1,
        'apiMinor': 0,
      }.entries) {
        if (value[version.key] is! int || value[version.key] != version.value)
          throw StateError('INCOMPATIBLE');
      }
      if (value['buildId'] != expectedBuildId ||
          !_build.hasMatch(expectedBuildId))
        throw StateError('INCOMPATIBLE');
      requireUuid(value['generation']);
      if (value['workspaceId'] != null) requireUuid(value['workspaceId']);
      final pid = value['serverPid'], encoded = value['bootstrapToken'];
      if (value['product'] != 'serverdeck-next' ||
          value['workspaceSlot'] != 'default' ||
          pid is! int ||
          pid < 1 ||
          pid > 0xffffffff ||
          encoded is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(encoded))
        throw StateError('STORAGE_BLOCKED');
      token = Uint8List.fromList(base64Url.decode('$encoded='));
      if (token.length != 32 ||
          base64Url.encode(token).replaceAll('=', '') != encoded)
        throw StateError('STORAGE_BLOCKED');
      final namespace = await DiscoveryNamespace.forOwner(ownerSid);
      final names = value['pipeNames'];
      if (names is! List ||
          names.length != 8 ||
          List.generate(
            8,
            (i) => names[i] == namespace.pipeNames[i],
          ).contains(false))
        throw StateError('STORAGE_BLOCKED');
      return DiscoveryDescriptor._(
        ownerSid,
        expectedBuildId,
        pid,
        value['generation'] as String,
        value['workspaceId'] as String?,
        namespace.pipeNames,
        token,
      );
    } catch (error) {
      if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
      throw StateError('STORAGE_BLOCKED');
    } finally {
      token?.fillRange(0, token.length, 0);
    }
  }

  DiscoveryDescriptor withWorkspace(String id) {
    _open();
    try {
      requireUuid(id);
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    }
    if (workspaceId != null && workspaceId != id)
      throw StateError('STORAGE_BLOCKED');
    return DiscoveryDescriptor._(
      _ownerSid,
      buildId,
      serverPid,
      generation,
      id,
      pipeNames,
      _token,
    );
  }

  void close() {
    _closed = true;
    _token.fillRange(0, _token.length, 0);
  }
}
