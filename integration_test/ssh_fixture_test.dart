import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverdeck/data/credentials.dart';
import 'package:serverdeck/data/read_adapters.dart';
import 'package:serverdeck/data/ssh.dart';
import 'package:serverdeck/domain/models.dart';

class FixtureCredentials implements CredentialStore {
  @override
  Future<SshCredential?> read(String reference) async =>
      const SshCredential.password('serverdeck-disposable-fixture-only');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const fingerprint = String.fromEnvironment('FIXTURE_SSH_FINGERPRINT');
  const port = int.fromEnvironment('FIXTURE_SSH_PORT');
  if (fingerprint.isEmpty || port == 0) {
    throw StateError(
      'Requires local disposable SSH fixture; see tools/test-ssh-fixture.ps1',
    );
  }
  final profile = ServerProfile(
    id: 'disposable',
    name: 'Disposable SSH container',
    endpoint: '127.0.0.1',
    port: port,
    user: 'observer',
    observedAt: DateTime.now().toUtc(),
  );
  EnrolledIdentity identity(String value) => EnrolledIdentity(
    endpoint: profile.endpoint,
    port: profile.port,
    keyType: 'ssh-ed25519',
    fingerprint: value,
  );
  testWidgets('BR-P01 real SSH rejects mismatched host key', (tester) async {
    await expectLater(
      SshReadClient.connect(
        profile: profile,
        identity: identity('SHA256:${'A' * 43}'),
        credentialReference: 'fixture',
        credentials: FixtureCredentials(),
      ),
      throwsA(isA<HostIdentityRejected>()),
    );
  });
  testWidgets(
    'BR-C01 fixture SSH performs bounded read-only package/proc queries',
    (tester) async {
      final client = await SshReadClient.connect(
        profile: profile,
        identity: identity(fingerprint),
        credentialReference: 'fixture',
        credentials: FixtureCredentials(),
      );
      try {
        final packages = await client.execute(ReadOperation.packages);
        expect(packages.succeeded, isTrue);
        expect(parsePackages(packages.stdout).values, isNotEmpty);
        final cpu = await client.execute(ReadOperation.cpu);
        expect(cpu.succeeded, isTrue);
        expect(CpuCounters.parse(cpu.stdout).total, greaterThan(0));
        final memory = await client.execute(ReadOperation.memory);
        expect(memory.succeeded, isTrue);
        expect(parseMemoryUsage(memory.stdout), isNotNull);
        final journal = await client.execute(ReadOperation.journal());
        // This minimal fixture intentionally lacks journald/systemd. Not AC03 proof.
        expect(journal.succeeded, isFalse);
        expect(journal.failure, ReadFailure.unsupported);
      } finally {
        await client.close();
      }
    },
  );
  testWidgets('BR-P01 oversized real SSH output terminates read', (
    tester,
  ) async {
    final client = await SshReadClient.connect(
      profile: profile,
      identity: identity(fingerprint),
      credentialReference: 'fixture',
      credentials: FixtureCredentials(),
    );
    try {
      await expectLater(
        client.execute(ReadOperation.packages, maxBytes: 1),
        throwsA(isA<ReadBudgetExceeded>()),
      );
    } finally {
      await client.close();
    }
  });
}
