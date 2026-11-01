import 'dart:async';

import 'package:serverdeck_engine/platform/managed_vault.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:test/test.dart';

final class Provider implements UserProtection {
  int calls = 0;
  bool fail = false;
  Completer<List<int>>? pending;
  Future<List<int>> run(List<int> input) {
    calls++;
    if (fail) throw StateError('private-provider-diagnostic');
    return pending?.future ?? Future.value(List<int>.of(input));
  }

  @override
  Future<List<int>> protect(List<int> cleartext, List<int> entropy) =>
      run(cleartext);
  @override
  Future<List<int>> unprotect(List<int> ciphertext, List<int> entropy) =>
      run(ciphertext);
}

Matcher unavailable() => throwsA(
  isA<StateError>().having(
    (e) => e.message,
    'safe code',
    'PROTECTION_UNAVAILABLE',
  ),
);

void main() {
  test('dispose stops admission and waits for physical return and late buffer wiping', () async {
    final provider = Provider()..pending = Completer<List<int>>();
    final vault = ManagedVault(provider, requireOwner: () {});
    final operation = vault.unprotect([9], [1]);
    final rejected = expectLater(operation, unavailable());
    var closed = false;
    final closing = vault.dispose();
    unawaited(closing.then((_) => closed = true));
    expect(identical(closing, vault.dispose()), isTrue);
    await expectLater(vault.protect([1], [2]), unavailable());
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(provider.calls, 1);
    final returned = [1, 2, 3];
    provider.pending!.complete(returned);
    await rejected;
    await closing;
    expect(returned, everyElement(0));
    expect(closed, isTrue);
    expect(await vault.accessStatus(), VaultAccess.unavailable);
    expect(provider.calls, 1);
  });

  test(
    'owner loss after await wipes output and never forwards a private failure',
    () async {
      var owned = true;
      final provider = Provider()..pending = Completer<List<int>>();
      final vault = ManagedVault(
        provider,
        requireOwner: () {
          if (!owned) throw StateError('private-owner-diagnostic');
        },
      );
      final operation = vault.unprotect([9], [1]);
      final rejected = expectLater(operation, unavailable());
      owned = false;
      final returned = [4, 5];
      provider.pending!.complete(returned);
      await rejected;
      expect(returned, everyElement(0));
      await expectLater(vault.protect([1], [2]), unavailable());
      expect(provider.calls, 1);
      await vault.dispose();
    },
  );

  test(
    'availability roundtrip does not turn provider failure into a fallback',
    () async {
      final provider = Provider();
      final vault = ManagedVault(provider, requireOwner: () {});
      expect(await vault.accessStatus(), VaultAccess.available);
      expect(provider.calls, 2);
      provider.fail = true;
      expect(await vault.accessStatus(), VaultAccess.unavailable);
      await expectLater(vault.unprotect([1], [2]), unavailable());
      await vault.dispose();
    },
  );

  test(
    'reentrant shutdown during owner check cannot start new physical work',
    () async {
      final provider = Provider();
      late ManagedVault vault;
      vault = ManagedVault(
        provider,
        requireOwner: () {
          unawaited(vault.dispose());
        },
      );
      await expectLater(vault.protect([1], [2]), unavailable());
      expect(provider.calls, 0);
      await vault.dispose();
    },
  );
}
