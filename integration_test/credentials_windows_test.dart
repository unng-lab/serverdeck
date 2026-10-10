import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverdeck/data/credentials.dart';
import 'package:win32/win32.dart';

void writeRaw(String reference, List<int> bytes) {
  final target = 'serverdeck-credential-$reference'.toNativeUtf16();
  final native = calloc<CREDENTIAL>();
  final blob = calloc<Uint8>(bytes.length);
  try {
    blob.asTypedList(bytes.length).setAll(0, bytes);
    native.ref.Type = CRED_TYPE_GENERIC;
    native.ref.TargetName = PWSTR(target);
    native.ref.Persist = CRED_PERSIST_LOCAL_MACHINE;
    native.ref.CredentialBlobSize = bytes.length;
    native.ref.CredentialBlob = blob;
    final result = CredWrite(native, 0);
    expect(
      result.value,
      isTrue,
      reason: 'Fixture CredWrite error ${result.error}',
    );
  } finally {
    blob.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
    calloc.free(blob);
    calloc.free(native);
    calloc.free(target);
  }
}

class FailingCredentialApi implements CredentialNativeApi {
  FailingCredentialApi(this.operation);
  final String operation;
  final calls = <String>[];
  Win32Result<bool> invoke(String name, Win32Result<bool> Function() native) {
    calls.add(name);
    return operation == name
        ? const Win32Result(value: false, error: ERROR_ACCESS_DENIED)
        : native();
  }

  @override
  Win32Result<bool> read(
    Pointer<Utf16> target,
    Pointer<Pointer<CREDENTIAL>> output,
  ) =>
      invoke('read', () => CredRead(PCWSTR(target), CRED_TYPE_GENERIC, output));
  @override
  Win32Result<bool> write(Pointer<CREDENTIAL> credential) =>
      invoke('write', () => CredWrite(credential, 0));
  @override
  Win32Result<bool> delete(Pointer<Utf16> target) =>
      invoke('delete', () => CredDelete(PCWSTR(target), CRED_TYPE_GENERIC));
}

class CredentialWorker {
  CredentialWorker(this.process)
    : lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
      errors = process.stderr.transform(utf8.decoder).join();
  final Process process;
  final StreamIterator<String> lines;
  final Future<String> errors;
  bool finished = false;

  static Future<CredentialWorker> start(
    String reference,
    String operation,
    String label,
  ) async {
    const executable = String.fromEnvironment('CREDENTIAL_TEST_WORKER');
    if (executable.isEmpty || !File(executable).existsSync()) {
      throw StateError('Pass the compiled fixture with CREDENTIAL_TEST_WORKER');
    }
    final worker = CredentialWorker(
      await Process.start(executable, [
        reference,
        operation,
        label,
      ], workingDirectory: Directory.current.path),
    );
    try {
      expect(
        await worker.lines.moveNext().timeout(const Duration(seconds: 30)),
        isTrue,
      );
      expect(worker.lines.current, 'ready');
      return worker;
    } catch (_) {
      await worker.close();
      rethrow;
    }
  }

  Future<void> apply() async {
    process.stdin.writeln('apply');
    await process.stdin.flush();
    expect(await lines.moveNext().timeout(const Duration(seconds: 30)), isTrue);
    expect(lines.current, 'done');
    expect(await process.exitCode.timeout(const Duration(seconds: 30)), 0);
    expect(await errors, isEmpty);
    finished = true;
  }

  Future<void> close() async {
    await process.stdin.close();
    if (!finished) process.kill();
    await process.exitCode.timeout(const Duration(seconds: 5));
    await lines.cancel();
    await errors;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in [
    (first: 'write', second: 'write', order: 'ab', outcomes: <String?>['b']),
    (first: 'write', second: 'write', order: 'ba', outcomes: <String?>['a']),
    (first: 'write', second: 'delete', order: 'ab', outcomes: <String?>[null]),
    (first: 'delete', second: 'write', order: 'ab', outcomes: <String?>['b']),
    (
      first: 'write',
      second: 'write',
      order: 'overlap',
      outcomes: <String?>['a', 'b'],
    ),
    (
      first: 'delete',
      second: 'write',
      order: 'overlap',
      outcomes: <String?>[null, 'b'],
    ),
  ]) {
    testWidgets(
      'two processes ${scenario.first}/${scenario.second} ${scenario.order}',
      (_) async {
        final reference = 'fixture-${DateTime.now().microsecondsSinceEpoch}';
        final store = OsCredentialStore();
        CredentialWorker? a, b;
        try {
          await store.write(
            reference,
            const SshCredential.password('synthetic-initial'),
          );
          a = await CredentialWorker.start(reference, scenario.first, 'a');
          b = await CredentialWorker.start(reference, scenario.second, 'b');
          // Both processes prepare their operations before either applies one.
          if (scenario.order == 'overlap') {
            await Future.wait([a.apply(), b.apply()]);
          } else {
            final ordered = scenario.order == 'ab' ? [a, b] : [b, a];
            for (final worker in ordered) {
              await worker.apply();
            }
          }
          final actual = await OsCredentialStore().read(reference);
          final outcome = actual == null
              ? null
              : actual.material == 'synthetic-a-key'
              ? 'a'
              : actual.material == 'synthetic-b-key'
              ? 'b'
              : 'unexpected';
          expect(scenario.outcomes, contains(outcome));
          if (actual != null) {
            expect(actual.kind, 'key');
            expect(actual.passphrase, 'synthetic-$outcome-phrase');
          }
        } finally {
          await a?.close();
          await b?.close();
          await store.delete(reference);
        }
      },
      skip: !Platform.isWindows,
    );
  }
  for (final operation in ['read', 'write', 'delete']) {
    testWidgets('controlled Cred$operation failure preserves native credential', (
      _,
    ) async {
      final reference = 'fixture-${DateTime.now().microsecondsSinceEpoch}';
      final store = OsCredentialStore();
      const original = SshCredential.key(
        'synthetic-original-key',
        passphrase: 'synthetic-original-phrase',
      );
      try {
        await store.write(reference, original);
        final api = FailingCredentialApi(operation);
        final failing = OsCredentialStore.withNativeApi(api);
        final Future<Object?> request = switch (operation) {
          'read' => failing.read(reference),
          'write' => failing.write(
            reference,
            const SshCredential.key(
              'synthetic-replacement-key',
              passphrase: 'synthetic-replacement-phrase',
            ),
          ),
          _ => failing.delete(reference),
        };
        await expectLater(
          request,
          throwsA(
            isA<StateError>().having(
              (e) => e.toString(),
              'diagnostic',
              'Bad state: Credential Manager $operation failed: $ERROR_ACCESS_DENIED',
            ),
          ),
        );
        expect(api.calls, [operation]); // No retry or alternate write/delete.
        final retained = await OsCredentialStore().read(reference);
        expect(retained?.kind, original.kind);
        expect(retained?.material, original.material);
        expect(retained?.passphrase, original.passphrase);
      } finally {
        await store.delete(reference);
      }
    }, skip: !Platform.isWindows);
  }
  testWidgets('password accepts absent/null passphrase and rejects a string', (
    _,
  ) async {
    final reference = 'fixture-${DateTime.now().microsecondsSinceEpoch}';
    final store = OsCredentialStore();
    try {
      for (final fields in [
        <String, dynamic>{},
        {'passphrase': null},
      ]) {
        writeRaw(
          reference,
          utf8.encode(
            jsonEncode({
              'kind': 'password',
              'material': 'synthetic-password',
              ...fields,
            }),
          ),
        );
        final password = await store.read(reference);
        expect(password?.material, 'synthetic-password');
        expect(password?.passphrase, isNull);
      }
      for (final phrase in ['', 'synthetic-phrase']) {
        writeRaw(
          reference,
          utf8.encode(
            jsonEncode({
              'kind': 'password',
              'material': 'synthetic-password',
              'passphrase': phrase,
            }),
          ),
        );
        await expectLater(
          store.read(reference),
          throwsA(
            isA<FormatException>().having(
              (e) => e.toString(),
              'diagnostic',
              'FormatException: Protected credential is invalid',
            ),
          ),
        );
      }
    } finally {
      await store.delete(reference);
    }
  }, skip: !Platform.isWindows);
  testWidgets('password/key/passphrase roundtrip, overwrite and delete', (
    _,
  ) async {
    final reference = 'fixture-${DateTime.now().microsecondsSinceEpoch}';
    final store = OsCredentialStore();
    try {
      expect(await store.read(reference), isNull);
      await store.write(
        reference,
        const SshCredential.password('synthetic-password'),
      );
      final password = await OsCredentialStore().read(reference);
      expect(password?.kind, 'password');
      expect(password?.material, 'synthetic-password');
      expect(password?.passphrase, isNull);
      await store.write(
        reference,
        const SshCredential.key(
          'синтетический key',
          passphrase: 'fixture-phrase',
        ),
      );
      final key = await OsCredentialStore().read(reference);
      expect(key?.kind, 'key');
      expect(key?.material, 'синтетический key');
      expect(key?.passphrase, 'fixture-phrase');
      await expectLater(
        store.write(reference, SshCredential.key('x' * 3000)),
        throwsArgumentError,
      );
      expect((await store.read(reference))?.material, 'синтетический key');
      await store.delete(reference);
      expect(await store.read(reference), isNull);
      await store.delete(reference);
    } finally {
      await store.delete(reference);
    }
  }, skip: !Platform.isWindows);
  testWidgets(
    'UTF-8 byte limit rejects replacement and preserves prior value',
    (_) async {
      final reference = 'fixture-${DateTime.now().microsecondsSinceEpoch}';
      final store = OsCredentialStore();
      try {
        final overhead = utf8
            .encode(
              jsonEncode({
                'kind': 'password',
                'material': '',
                'passphrase': null,
              }),
            )
            .length;
        final exact = 'x' * (2560 - overhead);
        await store.write(reference, SshCredential.password(exact));
        expect((await store.read(reference))?.material, exact);
        await expectLater(
          store.write(reference, SshCredential.password('${exact}x')),
          throwsArgumentError,
        );
        await expectLater(
          store.write(reference, SshCredential.password('ж' * 1300)),
          throwsArgumentError,
        );
        expect((await store.read(reference))?.material, exact);
      } finally {
        await store.delete(reference);
      }
    },
    skip: !Platform.isWindows,
  );
  testWidgets('malformed JSON/UTF-8/type has a fixed secret-free error', (
    _,
  ) async {
    final reference = 'fixture-${DateTime.now().microsecondsSinceEpoch}';
    final store = OsCredentialStore();
    try {
      for (final bytes in [
        utf8.encode('synthetic-private-secret broken json'),
        [0xff, ...utf8.encode('synthetic-private-secret')],
        utf8.encode(
          jsonEncode({
            'kind': 'unknown',
            'material': 'synthetic-private-secret',
          }),
        ),
        utf8.encode(
          jsonEncode({
            'kind': 'key',
            'material': 'synthetic-private-secret',
            'passphrase': 1,
          }),
        ),
      ]) {
        writeRaw(reference, bytes);
        await expectLater(
          store.read(reference),
          throwsA(
            isA<FormatException>().having(
              (e) => e.toString(),
              'diagnostic',
              'FormatException: Protected credential is invalid',
            ),
          ),
        );
      }
    } finally {
      await store.delete(reference);
    }
  }, skip: !Platform.isWindows);
}
