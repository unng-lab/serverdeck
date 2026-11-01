import 'dart:async';
import 'dart:convert';

import 'package:serverdeck_engine/credentials/discovery_custody.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_protocol/discovery.dart';
import 'package:test/test.dart';

import '../support/memory_platform.dart' show Protection;

const sid = 'S-1-5-21-1-2-3-1001';
const generation = '12345678-1234-4234-9234-123456789ad1';
const workspace = '12345678-1234-4234-9234-123456789ad2';
final build = '${'a' * 40}+Release+${'b' * 64}';
Matcher failure([String code = 'STORAGE_BLOCKED']) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));
Future<DiscoveryDescriptor> create({String? identity}) =>
    DiscoveryDescriptor.create(
      ownerSid: identity ?? sid,
      buildId: build,
      serverPid: 1,
      generation: generation,
      workspaceId: workspace,
    );

final class ObservedProtection implements UserProtection {
  final base = Protection();
  List<int>? input, entropy, output;
  Completer<void>? paused;
  Object? error;
  List<int>? overrideOutput;
  @override
  Future<List<int>> protect(List<int> clear, List<int> purpose) async {
    input = clear;
    entropy = List.of(purpose);
    await paused?.future;
    if (error != null) throw error!;
    return output = overrideOutput ?? await base.protect(clear, purpose);
  }

  @override
  Future<List<int>> unprotect(List<int> wrapped, List<int> purpose) async {
    input = wrapped;
    entropy = List.of(purpose);
    await paused?.future;
    if (error != null) throw error!;
    return output = overrideOutput ?? await base.unprotect(wrapped, purpose);
  }
}

void main() {
  test(
    'wrapped16KiB bounds apply before provider input and after protect',
    () async {
      final protection = ObservedProtection(), descriptor = await create();
      addTearDown(protection.base.dispose);
      addTearDown(descriptor.close);
      final custody = DiscoveryCustody(protection, sid);
      for (final invalid in [<int>[], List.filled(16385, 1)]) {
        await expectLater(custody.unprotect(invalid, build), failure());
        expect(protection.input, isNull);
        protection.overrideOutput = invalid;
        await expectLater(custody.protect(descriptor), failure());
        expect(protection.input!.every((byte) => byte == 0), isTrue);
        protection.input = null;
      }
      protection.overrideOutput = List.filled(16384, 1);
      final wrapped = await custody.protect(descriptor);
      expect(wrapped, hasLength(16384));
      expect(identical(wrapped, protection.overrideOutput), isFalse);
      protection.overrideOutput = descriptor.encode();
      final loaded = await custody.unprotect(wrapped, build);
      loaded.close();
      expect(protection.output!.every((byte) => byte == 0), isTrue);
    },
  );
  test('portable custody binds exact embedded entropy and wipes transient plaintext', () async {
    final protection = ObservedProtection(), descriptor = await create();
    addTearDown(protection.base.dispose);
    addTearDown(descriptor.close);
    final custody = DiscoveryCustody(protection, sid);
    final wrapped = await custody.protect(descriptor);
    expect(
      utf8.decode(protection.entropy!),
      'ServerDeckNext\nv1\ndefault\n$sid\nembedded-v1',
    );
    expect(protection.input!.every((b) => b == 0), isTrue);
    final loaded = await custody.unprotect(wrapped, build);
    addTearDown(loaded.close);
    expect(loaded.encode(), descriptor.encode());
    expect(protection.output!.every((b) => b == 0), isTrue);
    expect(descriptor.isClosed, isFalse);
  });

  test('owner mismatch and former entropy have no fallback', () async {
    final protection = ObservedProtection(), descriptor = await create();
    addTearDown(protection.base.dispose);
    addTearDown(descriptor.close);
    await expectLater(
      DiscoveryCustody(protection, 'S-1-5-21-9-8-7-1001').protect(descriptor),
      failure(),
    );
    expect(protection.input, isNull);
    final original = descriptor.encode();
    final legacy = await protection.base.protect(
      original,
      utf8.encode('ServerDeckNext\nv1\ndefault\n$sid\ndiscovery'),
    );
    await expectLater(
      DiscoveryCustody(protection, sid).unprotect(legacy, build),
      failure(),
    );
    expect(original, descriptor.encode());
  });

  test(
    'descriptor closed during protect cannot publish and cleartext is wiped',
    () async {
      final protection = ObservedProtection(), descriptor = await create();
      addTearDown(protection.base.dispose);
      protection.paused = Completer();
      final pending = DiscoveryCustody(protection, sid).protect(descriptor);
      descriptor.close();
      protection.paused!.complete();
      await expectLater(pending, failure());
      expect(protection.input!.every((b) => b == 0), isTrue);
    },
  );

  test('unprotect captures caller bytes and always wipes late or malformed plaintext', () async {
    final protection = ObservedProtection(), descriptor = await create();
    addTearDown(protection.base.dispose);
    addTearDown(descriptor.close);
    final custody = DiscoveryCustody(protection, sid);
    final wrapped = await custody.protect(descriptor);
    protection.paused = Completer();
    final pending = custody.unprotect(wrapped, build);
    wrapped.fillRange(0, wrapped.length, 255);
    protection.paused!.complete();
    final loaded = await pending;
    loaded.close();
    expect(protection.input, isNot(wrapped));
    expect(protection.output!.every((b) => b == 0), isTrue);
    protection.paused = null;
    for (final malformed in [
      <int>[],
      utf8.encode('private malformed text'),
      List.filled(8193, 32),
    ]) {
      protection.overrideOutput = malformed;
      await expectLater(custody.unprotect([1], build), failure());
      expect(malformed.every((b) => b == 0), isTrue);
    }
  });

  test('client enforces current build; owner inspection is data only and errors are safe', () async {
    final protection = ObservedProtection(), descriptor = await create();
    addTearDown(protection.base.dispose);
    addTearDown(descriptor.close);
    final custody = DiscoveryCustody(protection, sid),
        wrapped = await custody.protect(descriptor);
    await expectLater(
      custody.unprotect(wrapped, '${'c' * 40}+Release+${'d' * 64}'),
      failure('INCOMPATIBLE'),
    );
    expect(protection.output!.every((b) => b == 0), isTrue);
    final inspected = await custody.inspectForOwner(wrapped);
    expect(inspected.buildId, build);
    inspected.close();
    protection.error = StateError('private provider diagnostic');
    await expectLater(custody.protect(descriptor), failure());
    expect(protection.input!.every((b) => b == 0), isTrue);
    await expectLater(custody.unprotect(wrapped, build), failure());
  });
}
