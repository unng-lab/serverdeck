import 'package:serverdeck_windows/embedded_pipe_policy.dart';
import 'package:serverdeck_protocol/discovery.dart';
import 'package:test/test.dart';

void main() {
  test(
    'handshake5s then idle60s and partial5s preserve frame owner deadlines',
    () {
      expect(remainingPipeBudget(5000000, 4000000), const Duration(seconds: 1));
      expect(
        remainingPipeReadBudget(60000000, 5000000),
        const Duration(seconds: 55),
      );
      expect(
        remainingPipeReadBudget(65000000, 60000000),
        const Duration(seconds: 5),
      );
      expect(
        remainingPipeReadBudget(65000000, 64000000),
        const Duration(seconds: 1),
      );
      expect(
        () => remainingPipeReadBudget(65000000, 65000000),
        throwsStateError,
      );
      expect(() => remainingPipeReadBudget(61000000, 0), throwsStateError);
      expect(() => remainingPipeBudget(60000000, 0), throwsStateError);
    },
  );

  test(
    'only actual owner embedded8 namespace; no old names or caller app root',
    () async {
      const sid = 'S-1-5-21-1-2-3-1001', other = 'S-1-5-21-1-2-3-1002';
      final namespace = await DiscoveryNamespace.forOwner(sid);
      expect(namespace.pipeNames.length, 8);
      for (final name in namespace.pipeNames)
        await requireEmbeddedEndpoint(name, sid);
      for (final name in [
        namespace.pipeNames.first.replaceFirst('embedded-v1', 'v1'),
        namespace.pipeNames.first.replaceFirst('.0', '.8'),
        r'\\.\pipe\other',
      ]) {
        await expectLater(requireEmbeddedEndpoint(name, sid), throwsStateError);
      }
      await expectLater(
        requireEmbeddedEndpoint(namespace.pipeNames.first, other),
        throwsStateError,
      );
    },
  );
  test(
    'queued operations retain original5s and reject expired or enlarged budget',
    () {
      expect(remainingPipeBudget(5000000, 1000000), const Duration(seconds: 4));
      expect(() => remainingPipeBudget(5000000, 5000000), throwsStateError);
      expect(() => remainingPipeBudget(5000000, 6000000), throwsStateError);
      expect(() => remainingPipeBudget(6000000, 0), throwsStateError);
    },
  );
  test(
    'expected descriptor PID is a positive32bit identity, no claim of role',
    () {
      for (final value in [1, 0xffffffff]) requireEmbeddedPeerPid(value);
      for (final value in [0, -1, 0x100000000])
        expect(() => requireEmbeddedPeerPid(value), throwsStateError);
    },
  );
  test(
    'asymmetric server outbound vs client inbound quota proves consumed output',
    () {
      final server = [0, 2, 1, 1, 4096, 0, 8192, 8192, 3, 1];
      expect(
        embeddedPipeOutputEmpty(server, server: true, writing: false),
        isTrue,
      );
      final client = [0, 2, 1, 1, 4096, 0, 8192, 4096, 3, 0];
      expect(
        embeddedPipeOutputEmpty(client, server: false, writing: false),
        isTrue,
      );
      client[7] = 2048;
      expect(
        embeddedPipeOutputEmpty(client, server: false, writing: false),
        isFalse,
      );
      client[7] = 8192;
      expect(
        () => embeddedPipeOutputEmpty(client, server: false, writing: false),
        throwsStateError,
      );
      expect(
        embeddedPipeOutputEmpty(server, server: true, writing: true),
        isFalse,
      );
      server[8] = 4;
      expect(
        () => embeddedPipeOutputEmpty(server, server: true, writing: false),
        throwsStateError,
      );
      server[8] = 3;
      server[9] = 0;
      expect(
        () => embeddedPipeOutputEmpty(server, server: true, writing: false),
        throwsStateError,
      );
    },
  );
}
