import 'dart:async';

import 'package:serverdeck_protocol/discovery.dart';

import '../credentials/discovery_custody.dart';
import 'mcp_endpoint_pool.dart';

/// One fixed protected runtime filename. Futures mean actual physical I/O.
/// Implementations reject reparses/non-regular files, enforce owner-only ACLs,
/// bound reads to16KiB and atomically replace. Compare/remove holds one file
/// object against write/delete until comparison and disposition are complete.
abstract interface class McpDiscoveryFile {
  Future<List<int>?> read();
  Future<void> replace(List<int> wrapped);

  /// Missing/different content stays untouched; failure means unconfirmed I/O.
  Future<void> removeExact(List<int> wrapped);

  /// Drains issued file work; unconfirmed native handle close stays failed.
  Future<void> close();
}

/// One publication attempt under the Host's retained runtime/writer lease.
/// The pool exclusively owns the descriptor; this object owns wrapped buffers
/// and all late file work, never a store, lease or process of its own.
final class ProtectedMcpDiscovery implements McpDiscoveryStore {
  ProtectedMcpDiscovery({
    required DiscoveryCustody custody,
    required McpDiscoveryFile file,
    required Future<void> Function() requireLive,
  }) : _custody = custody,
       _file = file,
       _requireLive = requireLive;
  final DiscoveryCustody _custody;
  final McpDiscoveryFile _file;
  final Future<void> Function() _requireLive;
  DiscoveryDescriptor? _descriptor;
  Future<void>? _publishing, _removing;
  List<int>? _expected;
  bool _closing = false;

  static StateError _safe(Object error) => StateError(
    error is StateError &&
            const {
              'INCOMPATIBLE',
              'UNAUTHORIZED',
              'NOT_READY',
              'TIMEOUT',
              'SERVICE_UNAVAILABLE',
              'RESOURCE_LIMIT',
            }.contains(error.message)
        ? error.message
        : 'STORAGE_BLOCKED',
  );
  static bool _same(List<int> a, List<int> b) {
    var difference = a.length ^ b.length;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ (i < b.length ? b[i] : 0);
    }
    return difference == 0;
  }

  Future<void> _check() async {
    if (_closing) throw StateError('SERVICE_UNAVAILABLE');
    await _requireLive();
    if (_closing) throw StateError('SERVICE_UNAVAILABLE');
  }

  @override
  Future<void> publish(DiscoveryDescriptor descriptor) {
    if (_closing ||
        (_descriptor != null && !identical(_descriptor, descriptor))) {
      return Future.error(StateError('SERVICE_UNAVAILABLE'));
    }
    if (_publishing != null) return _publishing!;
    final done = Completer<void>();
    _publishing = done.future;
    _descriptor = descriptor;
    done.future.ignore();
    () async {
      List<int>? old, wrapped, readback, original, decoded;
      DiscoveryDescriptor? inspected, loaded;
      try {
        await _check();
        old = await _file.read();
        await _check();
        if (old != null) {
          inspected = await _custody.inspectForOwner(old);
          inspected.close();
          inspected = null;
          await _check();
        }
        wrapped = await _custody.protect(descriptor);
        await _check();
        // Retain exact bytes BEFORE issuing I/O: a failed replace can have
        // committed its name, and remove must own that uncertain outcome too.
        _expected = List<int>.of(wrapped);
        await _file.replace(wrapped);
        await _check();
        readback = await _file.read();
        if (readback == null || !_same(wrapped, readback)) {
          throw StateError('STORAGE_BLOCKED');
        }
        loaded = await _custody.unprotect(readback, descriptor.buildId);
        original = descriptor.encode();
        decoded = loaded.encode();
        if (!_same(original, decoded)) throw StateError('STORAGE_BLOCKED');
        await _check();
      } finally {
        inspected?.close();
        loaded?.close();
        for (final bytes in [old, wrapped, readback, original, decoded]) {
          bytes?.fillRange(0, bytes.length, 0);
        }
      }
    }().then<void>(
      done.complete,
      onError: (Object e, StackTrace _) {
        done.completeError(_safe(e));
      },
    );
    return done.future;
  }

  @override
  Future<void> removeOwned(DiscoveryDescriptor descriptor) {
    if (_descriptor != null && !identical(_descriptor, descriptor)) {
      return Future.error(StateError('SERVICE_UNAVAILABLE'));
    }
    if (_removing != null) return _removing!;
    final done = Completer<void>();
    _removing = done.future;
    _closing = true;
    done.future.ignore();
    () async {
      try {
        await _publishing;
      } catch (_) {
        /* Publication failure does not prove a write did not commit. */
      }
      final expected = _expected;
      try {
        if (expected != null) await _file.removeExact(expected);
      } finally {
        expected?.fillRange(0, expected.length, 0);
        _expected = null;
        await _file.close();
      }
    }().then<void>(
      done.complete,
      onError: (Object e, StackTrace _) {
        done.completeError(_safe(e));
      },
    );
    return done.future;
  }
}
