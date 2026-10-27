import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';

const generation = '10000000-0000-4000-8000-000000000001';
void check(bool value) {
  if (!value) throw StateError('SERVER_CONSTRUCTOR_FIXTURE_FAILED');
}

/// Observes reads of synthetic caller-owned bytes, never an owned secret getter.
/// Validation reads32; a subsequent defensive copy reads32 more.
final class CountingToken extends ListBase<int> {
  int reads = 0;
  @override
  int get length => 32;
  @override
  set length(int value) => throw UnsupportedError('FIXED');
  @override
  int operator [](int index) {
    RangeError.checkValidIndex(index, this);
    reads++;
    return index;
  }

  @override
  void operator []=(int index, int value) => throw UnsupportedError('FIXED');
}

Future<String> bounded(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    check(bytes.length + chunk.length <= 16384);
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}

Future<void> main(List<String> args) async {
  try {
    containCurrentFixtureTree();
    final trusted = args[3] == '3', root = args[1], name = args[2];
    if (args[0] == 'client') {
      final worker = trusted
          ? await PipeWorker.openTrustedClient(name, currentUserSid(), root)
          : await PipeWorker.openOperationalClient(
              name,
              currentUserSid(),
              root,
            );
      try {
        final token = CountingToken();
        final old = OperationalSessions(generation: generation);
        final next = TrustedSessions(generation: generation);
        try {
          final peer = trusted
              ? await worker.verifyTrustedPeer()
              : await worker.verifyOperationalPeer();
          try {
            if (trusted) {
              TrustedServerHandshake(
                peer: peer as TrustedPipePeer,
                token: token,
                channel: name,
                sessions: next,
              );
            } else {
              OperationalServerHandshake(
                peer: peer as OperationalPipePeer,
                token: token,
                channel: name,
                sessions: old,
              );
            }
            throw StateError('EXPECTED_WRONG_SIDE_REFUSAL');
          } on StateError catch (error) {
            check(error.message == 'UNAUTHORIZED');
          }
          check(token.reads == 32 && old.count == 0 && next.count == 0);
          stdout.writeln('CLIENT_PASS');
          await stdin.first;
        } finally {
          await old.close();
          await next.close();
        }
      } finally {
        await worker.close();
      }
      return;
    }
    final worker = trusted
        ? await PipeWorker.createTrustedServer(name, currentUserSid(), root)
        : await PipeWorker.createOperationalServer(
            name,
            currentUserSid(),
            root,
          );
    final old = OperationalSessions(generation: generation),
        next = TrustedSessions(generation: generation);
    Process? child;
    StreamIterator<String>? lines;
    try {
      final accepted = worker.accept(deadline: const Duration(seconds: 5));
      accepted.ignore();
      child = await Process.start(p.join(root, args[4]), [
        'client',
        root,
        name,
        args[3],
      ]);
      final errors = bounded(child.stderr);
      lines = StreamIterator(
        child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      await accepted;
      check(
        await lines.moveNext().timeout(const Duration(seconds: 8)) &&
            lines.current == 'CLIENT_PASS',
      );
      final token = CountingToken();
      if (trusted) {
        final handshake = TrustedServerHandshake(
          peer: await worker.verifyTrustedPeer(),
          token: token,
          channel: name,
          sessions: next,
        );
        try {
          check(token.reads == 64);
          await handshake.hello();
        } finally {
          handshake.close();
        }
      } else {
        final handshake = OperationalServerHandshake(
          peer: await worker.verifyOperationalPeer(),
          token: token,
          channel: name,
          sessions: old,
        );
        try {
          check(token.reads == 64);
          await handshake.hello();
        } finally {
          handshake.close();
        }
      }
      check(old.count == 0 && next.count == 0);
      final clockToken = CountingToken();
      Duration failingClock() => throw StateError('SYNTHETIC_CLOCK_FAILURE');
      try {
        if (trusted) {
          TrustedServerHandshake(
            peer: await worker.verifyTrustedPeer(),
            token: clockToken,
            channel: name,
            sessions: next,
            elapsed: failingClock,
          );
        } else {
          OperationalServerHandshake(
            peer: await worker.verifyOperationalPeer(),
            token: clockToken,
            channel: name,
            sessions: old,
            elapsed: failingClock,
          );
        }
        throw StateError('EXPECTED_CLOCK_FAILURE');
      } on StateError catch (error) {
        check(error.message == 'SYNTHETIC_CLOCK_FAILURE');
      }
      check(clockToken.reads == 64 && old.count == 0 && next.count == 0);
      child.stdin.writeln('exit');
      await child.stdin.close();
      final code = await child.exitCode.timeout(const Duration(seconds: 8));
      final error = await errors;
      if (code != 0 || error.isNotEmpty) {
        stderr.write(error);
        throw StateError('CONSTRUCTOR_CHILD_FAILED');
      }
      stdout.writeln('PASS');
    } finally {
      if (child != null) {
        try {
          await child.stdin.close();
        } on IOException {
          /* Owned child exited. */
        }
        child.kill();
        await child.exitCode.timeout(const Duration(seconds: 5));
      }
      await lines?.cancel();
      await old.close();
      await next.close();
      await worker.close();
    }
  } catch (error, stack) {
    stderr.writeln(error);
    stderr.writeln(stack);
    exitCode = 1;
  }
}
