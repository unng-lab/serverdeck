import 'dart:async';
import 'dart:convert';

import 'ports.dart';

/// Physical operation ownership shared by platform vault adapters. The trusted
/// composition supplies the actual OS provider and owner check; neither this
/// wrapper nor its probe grants identity, creates a workspace or repairs keys.
final class ManagedVault implements SecureVault {
  ManagedVault(this._provider, {required void Function() requireOwner})
    : _requireOwner = requireOwner;
  final UserProtection _provider;
  final void Function() _requireOwner;
  final _pending = <Future<void>>{};
  bool _closing = false;
  Future<void>? _closed;

  void _check() {
    if (_closing) throw StateError('PROTECTION_UNAVAILABLE');
    _requireOwner();
    if (_closing) throw StateError('PROTECTION_UNAVAILABLE');
  }

  Future<List<int>> _run(
    List<int> input,
    List<int> entropy,
    bool protect,
  ) async {
    final settled = Completer<void>();
    List<int>? result;
    try {
      _check();
      _pending.add(settled.future);
      result = await (protect
          ? _provider.protect(input, entropy)
          : _provider.unprotect(input, entropy));
      _check();
      return result;
    } catch (_) {
      result?.fillRange(0, result.length, 0);
      throw StateError('PROTECTION_UNAVAILABLE');
    } finally {
      _pending.remove(settled.future);
      settled.complete();
    }
  }

  @override
  Future<List<int>> protect(List<int> cleartext, List<int> entropy) =>
      _run(cleartext, entropy, true);
  @override
  Future<List<int>> unprotect(List<int> ciphertext, List<int> entropy) =>
      _run(ciphertext, entropy, false);
  @override
  Future<VaultAccess> accessStatus() async {
    final clear = List<int>.generate(32, (index) => index);
    final entropy = utf8.encode('ServerDeckNext\nv1\nvault-availability');
    List<int>? wrapped, opened;
    try {
      wrapped = await protect(clear, entropy);
      opened = await unprotect(wrapped, entropy);
      if (opened.length != clear.length) return VaultAccess.unavailable;
      for (var index = 0; index < clear.length; index++) {
        if (opened[index] != clear[index]) return VaultAccess.unavailable;
      }
      return VaultAccess.available;
    } catch (_) {
      return VaultAccess.unavailable;
    } finally {
      clear.fillRange(0, clear.length, 0);
      wrapped?.fillRange(0, wrapped.length, 0);
      opened?.fillRange(0, opened.length, 0);
    }
  }

  @override
  Future<void> dispose() {
    if (_closed != null) return _closed!;
    _closing = true; // No new protection after shutdown starts.
    return _closed = Future.wait(_pending.toList());
  }
}
