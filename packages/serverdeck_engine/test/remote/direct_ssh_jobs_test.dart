import 'dart:convert';

import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_engine/remote/direct_ssh_records.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:test/test.dart';

import '../storage/actual_plan_job_store_test.dart' show job;
import '../storage/actual_state_store_test.dart' as actual;
import '../support/actual_plan_fixture.dart';

Future<DirectSshAttempt> attemptFixture() async {
  final setup = await actual.Setup.create(), store = await setup.open();
  final built = await planFixture(store, 40, directSsh: true);
  await persist(store, built);
  await approve(store, built.$2, 50);
  final saved = await job(
    store,
    'job.apply',
    60,
    built.$2.id,
    verifiedDigest: built.$2.toJson()['digest'] as String,
  );
  return DirectSshAttempt.fromRecords(
    store.snapshot.automation.jobs[saved['jobId']]!,
    built.$2,
  );
}

DirectSshOutput output(Map<String, String> rows) => DirectSshOutput(
  ascii.encode(
    rows.entries
        .map(
          (entry) =>
              '${entry.key}\t${base64.encode(utf8.encode(entry.value))}\n',
        )
        .join(),
  ),
  exitCode: 0,
  truncated: false,
);

Map<String, String> absent() => {
  'presence': 'absent',
  'disposition': 'absent',
  'owner': '',
  'admission': '',
  'plan': '',
  'stop': '',
  'terminal': '',
};

void main() {
  tearDown(() => expect(StateStore.hasOpenReservation, isFalse));

  test('stop B fences a delayed reserve while A owns the host, including partial plan marker', () async {
    final attempt = await attemptFixture();
    final stopCommand = DirectSshCommand.stopAttempt(attempt).script;
    expect(
      stopCommand,
      isNot(contains(r'matches "$expected_owner" "$root/owner"')),
    );
    final reserveCommand = DirectSshCommand.reserveAttempt(attempt).script;
    expect(
      reserveCommand.indexOf(r'if [ -e "$stop_file" ]'),
      lessThan(reserveCommand.indexOf(r'exclusive_record "$expected_owner"')),
    );
    String record(String kind, Map<String, String> fields) =>
        ascii.decode(DirectHostRecord.create(kind, fields).encode());
    final otherOwner = record('owner', {
      ...attempt.identity,
      'attemptId': actual.id(120),
      'jobId': actual.id(121),
      'planDigest': 'a' * 64,
    });
    final stopRecord = record('stop', {
      'attemptId': attempt.attemptId,
      'planDigest': attempt.planDigest,
    });
    // Metadata sequence only: no shell race/crash execution is simulated here.
    final afterStop = {
      ...absent(),
      'presence': 'present',
      'disposition': 'stopped',
      'owner': otherOwner,
      'stop': stopRecord,
    };
    final fenced = DirectAttemptSnapshot.fromOutput(attempt, output(afterStop));
    expect(fenced.stop, isNotNull);
    expect(fenced.foreignOwnerPresent, isTrue);
    expect(fenced.owner, isNull);
    final afterLostAck = {...afterStop, 'disposition': 'snapshot'};
    expect(
      DirectAttemptSnapshot.fromOutput(attempt, output(afterLostAck)).plan,
      isNull,
    );
    final afterOwnerRelease = {...afterStop, 'owner': ''};
    expect(
      DirectAttemptSnapshot.fromOutput(attempt, output(afterOwnerRelease)).stop,
      isNotNull,
    );
  });

  test('terminal A remains readable with unrelated current owner B', () async {
    final attempt = await attemptFixture();
    String record(String kind, Map<String, String> fields) =>
        ascii.decode(DirectHostRecord.create(kind, fields).encode());
    final rows = {
      ...absent(),
      'presence': 'present',
      'disposition': 'snapshot',
      'owner': record('owner', {
        ...attempt.identity,
        'jobId': actual.id(120),
        'attemptId': actual.id(121),
        'planDigest': 'a' * 64,
      }),
      'admission': record('admission', attempt.identity),
      'plan': record('plan', {
        'attemptId': attempt.attemptId,
        'planDigest': attempt.planDigest,
        'terminal': 'succeeded',
      }),
      'terminal': record('terminal', {
        ...attempt.identity,
        'state': 'succeeded',
        'checksDigest': 'b' * 64,
      }),
    };
    final snapshot = DirectAttemptSnapshot.fromOutput(attempt, output(rows));
    expect(snapshot.owner, isNull);
    expect(snapshot.foreignOwnerPresent, isTrue);
    expect(snapshot.records.containsKey('owner'), isFalse);
    expect(snapshot.terminal!.fields['state'], 'succeeded');
    for (final foreign in [
      {...attempt.identity, 'jobId': actual.id(122)},
      {...attempt.identity, 'attemptId': actual.id(123)},
      {
        ...attempt.identity,
        'attemptId': actual.id(123),
        'planDigest': 'a' * 64,
      },
      {
        ...attempt.identity,
        'attemptId': actual.id(123),
        'planDigest': 'a' * 64,
        'hostId': actual.id(124),
      },
    ]) {
      expect(
        () => DirectAttemptSnapshot.fromOutput(
          attempt,
          output({...rows, 'owner': record('owner', foreign)}),
        ),
        throwsA(isA<DirectSshFailure>()),
      );
    }
    for (final changed in [
      record('terminal', {
        ...attempt.identity,
        'jobId': actual.id(122),
        'state': 'succeeded',
        'checksDigest': 'b' * 64,
      }),
      'truncated',
    ]) {
      expect(
        () => DirectAttemptSnapshot.fromOutput(
          attempt,
          output({...rows, 'terminal': changed}),
        ),
        throwsA(isA<DirectSshFailure>()),
      );
    }
  });

  test(
    'closed attempt commands separate mutation from read-only recovery',
    () async {
      final attempt = await attemptFixture();
      final reserve = DirectSshCommand.reserveAttempt(attempt);
      final stop = DirectSshCommand.stopAttempt(attempt);
      final status = DirectSshCommand.attemptStatus(attempt);
      expect(reserve.mutates, isTrue);
      expect(stop.mutates, isTrue);
      expect(status.mutates, isFalse);
      expect(stop.maximumDuration, const Duration(seconds: 10));
      for (final command in [reserve, stop, status]) {
        expect(command.outputLimit, 128 * 1024);
        expect(
          utf8.encode(command.script).length,
          lessThanOrEqualTo(256 * 1024),
        );
        expect(command.script, contains('/var/lib/serverdeck/ssh-v1'));
        expect(command.script, contains('/usr/bin/flock -n 9'));
        expect(command.script, isNot(contains('eval ')));
        expect(command.script, isNot(contains('kill ')));
        expect(command.script, isNot(contains('systemctl stop')));
        for (final executable in command.requiredExecutables) {
          expect(command.script, contains('[ -x $executable ]'));
        }
      }
      for (final mutation in [
        '/usr/bin/mkdir ',
        '/usr/bin/mv ',
        '/usr/bin/rm ',
        '/usr/bin/sync ',
      ]) {
        expect(status.script, isNot(contains(mutation)));
      }
      expect(status.script, contains('exec 9<'));
      expect(
        reserve.script.indexOf(r'boot_digest=$'),
        lessThan(reserve.script.indexOf('\n  initialize\n')),
      );
      expect(
        reserve.script.indexOf('/usr/bin/flock -n 9'),
        lessThan(reserve.script.indexOf('reserve_attempt\n')),
      );
      expect(stop.script, contains('stops/${attempt.planDigest}'));
      expect(reserve.script, contains('stops/${attempt.planDigest}'));
      expect(stop.script, isNot(contains(r'rm -- "$root/owner"')));
    },
  );

  test(
    'absence and valid root records remain observations, not result proof',
    () async {
      final attempt = await attemptFixture();
      final empty = DirectAttemptSnapshot.fromOutput(attempt, output(absent()));
      expect(empty.disposition, 'absent');
      expect(empty.owner, isNull);
      final identity = attempt.identity;
      final rows = {
        ...absent(),
        'presence': 'present',
        'disposition': 'reserved',
        'owner': ascii.decode(
          DirectHostRecord.create('owner', identity).encode(),
        ),
        'admission': ascii.decode(
          DirectHostRecord.create('admission', identity).encode(),
        ),
        'plan': ascii.decode(
          DirectHostRecord.create('plan', {
            'planDigest': attempt.planDigest,
            'attemptId': attempt.attemptId,
            'terminal': 'pending',
          }).encode(),
        ),
      };
      final snapshot = DirectAttemptSnapshot.fromOutput(attempt, output(rows));
      expect(snapshot.owner!.fields, identity);
      expect(snapshot.plan!.fields['terminal'], 'pending');
      for (final patch in <Map<String, String>>[
        {'presence': 'absent'},
        {'admission': ''},
        {'plan': ''},
        {'owner': rows['owner']!.replaceFirst(attempt.jobId, actual.id(99))},
        {'disposition': 'succeeded'},
        {'terminal': 'partial'},
      ]) {
        expect(
          () => DirectAttemptSnapshot.fromOutput(
            attempt,
            output({...rows, ...patch}),
          ),
          throwsA(isA<DirectSshFailure>()),
        );
      }
      expect(() => attempt.identity.clear(), throwsUnsupportedError);
    },
  );

  test(
    'stop-before-reserve and terminal records correlate the complete tuple',
    () async {
      final attempt = await attemptFixture();
      String record(String kind, Map<String, String> fields) =>
          ascii.decode(DirectHostRecord.create(kind, fields).encode());
      final stop = record('stop', {
        'attemptId': attempt.attemptId,
        'planDigest': attempt.planDigest,
      });
      final cancelled = record('plan', {
        'attemptId': attempt.attemptId,
        'planDigest': attempt.planDigest,
        'terminal': 'cancelled',
      });
      final stopped = {
        ...absent(),
        'presence': 'present',
        'disposition': 'stopped',
        'stop': stop,
        'plan': cancelled,
      };
      final observed = DirectAttemptSnapshot.fromOutput(
        attempt,
        output(stopped),
      );
      expect(observed.stop!.fields['attemptId'], attempt.attemptId);
      expect(
        observed.admission,
        isNull,
      ); // Never turns absent admission into proof.
      final terminal = record('terminal', {
        ...attempt.identity,
        'state': 'cancelled',
        'checksDigest': 'a' * 64,
      });
      final terminalRows = {
        ...stopped,
        'disposition': 'existing',
        'terminal': terminal,
      };
      expect(
        DirectAttemptSnapshot.fromOutput(
          attempt,
          output(terminalRows),
        ).terminal!.fields['state'],
        'cancelled',
      );
      for (final field in attempt.identity.keys) {
        final value = attempt.identity[field]!;
        final replacement = field.endsWith('Digest') || field.endsWith('Hash')
            ? (value.startsWith('a') ? 'b' : 'a') * 64
            : actual.id(123);
        final foreign = record('terminal', {
          ...attempt.identity,
          field: replacement,
          'state': 'cancelled',
          'checksDigest': 'a' * 64,
        });
        expect(
          () => DirectAttemptSnapshot.fromOutput(
            attempt,
            output({...terminalRows, 'terminal': foreign}),
          ),
          throwsA(isA<DirectSshFailure>()),
        );
      }
      expect(
        () => DirectAttemptSnapshot.fromOutput(
          attempt,
          output({...stopped, 'stop': ''}),
        ),
        throwsA(isA<DirectSshFailure>()),
      );
      expect(() => observed.records.clear(), throwsUnsupportedError);
      expect(
        () => DirectAttemptSnapshot.fromOutput(
          attempt,
          output({...absent(), 'owner': 'x' * 131073}),
        ),
        throwsA(
          isA<DirectSshFailure>().having(
            (failure) => failure.code,
            'safe code',
            'RESOURCE_LIMIT',
          ),
        ),
      );
    },
  );
}
