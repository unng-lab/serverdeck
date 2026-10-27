import 'dart:convert';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/discovery.dart';

import 'security.dart';

export 'package:serverdeck_protocol/discovery.dart';

class DiscoveryCustody {
  DiscoveryCustody(this.protection, this.ownerSid);
  final UserProtection protection;
  final String ownerSid;
  List<int> get _entropy =>
      utf8.encode('ServerDeckNext\nv1\ndefault\n$ownerSid\ndiscovery');
  Future<List<int>> protect(DiscoveryDescriptor descriptor) async {
    List<int>? clear;
    try {
      if (descriptor.ownerSid != ownerSid) throw StateError('STORAGE_BLOCKED');
      clear = descriptor.encode();
      final wrapped = await protection.protect(clear, _entropy);
      if (descriptor.isClosed) throw StateError('STORAGE_BLOCKED');
      if (wrapped.isEmpty || wrapped.length > 16384)
        throw StateError('STORAGE_BLOCKED');
      return List<int>.of(wrapped);
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    } finally {
      clear?.fillRange(0, clear.length, 0);
    }
  }

  Future<DiscoveryDescriptor> unprotect(
    List<int> bytes,
    String expectedBuildId,
  ) => _unprotect(bytes, expectedBuildId);

  /// Used only by the mutex owner to inspect stale discovery before replacing
  /// it. Clients must use unprotect with their verified bundle identity.
  Future<DiscoveryDescriptor> inspectForOwner(List<int> bytes) =>
      _unprotect(bytes, null);

  Future<DiscoveryDescriptor> _unprotect(
    List<int> bytes,
    String? expectedBuildId,
  ) async {
    List<int>? clear;
    try {
      if (bytes.isEmpty || bytes.length > 16384)
        throw StateError('STORAGE_BLOCKED');
      clear = await protection.unprotect(List<int>.of(bytes), _entropy);
      final recordedBuild =
          expectedBuildId ??
          StrictCodec().decode(clear, maxBytes: 8192)['buildId'];
      if (recordedBuild is! String) throw StateError('STORAGE_BLOCKED');
      return await DiscoveryDescriptor.decode(
        clear,
        ownerSid: ownerSid,
        expectedBuildId: recordedBuild,
      );
    } catch (error) {
      if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
      throw StateError('STORAGE_BLOCKED');
    } finally {
      clear?.fillRange(0, clear.length, 0);
    }
  }
}
