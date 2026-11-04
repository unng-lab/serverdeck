import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/domain/receipt_book.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/profiles/profile_owner.dart';
import 'package:serverdeck/runtime/native_platform.dart';
import 'package:serverdeck/theme/brand_theme.dart';

import '../fixtures/profile_harness.dart';

final class ChannelProtector implements SecretProtector {
  ChannelProtector(this.platform);
  final NativePlatform platform;
  @override
  Future<Uint8List> protect(Uint8List bytes, String purpose) =>
      platform.protect(bytes, purpose);
}

final class FormOperations extends Fake implements AppOperations {
  FormOperations(this.owner);
  final ProfileOwner owner;
  @override
  Future<OperationResult<MutationValue>> createProfile(
    Actor actor,
    ProfileDraft draft, {
    required String mutationId,
  }) => owner.createProfile(actor, draft, mutationId: mutationId);
  @override
  Future<OperationResult<ProfilesPage>> listProfiles(
    Actor actor, {
    int limit = 50,
    String? cursor,
  }) => owner.listProfiles(actor, limit: limit, cursor: cursor);
  @override
  Future<OperationResult<TrustView>> getTrust(Actor actor, String id) async =>
      const OperationResult.success(
        TrustView(trustRevision: 1, observationRevision: 1, changed: false),
        OperationMeta(
          dataRevision: 2,
          ownerEpoch: '00000001-0000-4000-8000-000000000000',
        ),
      );
}

void main() {
  for (final mode in ['password', 'rsa2048']) {
    testWidgets(
      'form saves $mode through codec replies and closes without a cleanup error',
      (tester) async {
        final h = ProfileHarness();
        addTearDown(() async {
          var closed = false;
          final closing = h.dispose().whenComplete(() => closed = true);
          for (var i = 0; i < 20 && !closed; i++) {
            await tester.pump();
          }
          expect(closed, isTrue);
          await closing;
        });
        const channel = MethodChannel('form-save-binary-unit');
        final platform = NativePlatform(
          epoch: h.actors.ownerEpoch,
          channel: channel,
        );
        final keyBytes = File('test/fixtures/ssh/rsa2048.txt')
            .readAsBytesSync();
        var protects = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler(channel.name, (message) async {
              const codec = StandardMethodCodec();
              final call = codec.decodeMethodCall(message!);
              if (call.method == 'credential.pickKey')
                return codec
                    .encodeSuccessEnvelope(keyBytes)
                    .asUnmodifiableView();
              expect(call.method, 'secret.protect');
              protects++;
              if (mode == 'rsa2048')
                expect((call.arguments as Map)['bytes'], keyBytes);
              return codec
                  .encodeSuccessEnvelope(Uint8List.fromList([81, 82, 83]))
                  .asUnmodifiableView();
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMessageHandler(channel.name, null),
        );
        final owner = ProfileOwner(
          gate: h.gate,
          repository: h.repository,
          receipts: ReceiptBook(h.signer, () => h.now),
          credentials: CredentialPreparer(
            ChannelProtector(platform),
            h.inspector,
          ),
          connections: h.connections,
          newId: () => fixtureId(++h.sequence),
          utcNow: () => h.now,
        );
        addTearDown(owner.dispose);
        final controller = ProfileController(
          operations: FormOperations(owner),
          actor: h.actors.ui,
          newId: () => fixtureId(++h.sequence),
          poll: false,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.dark,
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog<ProfileSaveOutcome>(
                  context: context,
                  builder: (_) => ProfileForm(
                    controller: controller,
                    pickKey: platform.pickPrivateKey,
                  ),
                ),
                child: const Text('Open form'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open form'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).at(0),
          'Synthetic server',
        );
        await tester.enterText(find.byType(TextField).at(1), 'server.invalid');
        await tester.enterText(find.byType(TextField).at(3), 'root');
        if (mode == 'rsa2048') {
          await tester.tap(find.byType(DropdownButtonFormField<AuthKind>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Приватный ключ SSH').last);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Выбрать файл ключа'));
          await tester.tap(find.text('Выбрать файл ключа'));
          await tester.pumpAndSettle();
          expect(find.text('Ключ выбран — заменить'), findsOneWidget);
        } else {
          await tester.enterText(
            find.byType(TextField).at(4),
            'synthetic-password',
          );
        }
        await tester.ensureVisible(find.text('Сохранить'));
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ProfileForm), findsNothing);
        expect(controller.error, isNull);
        expect(controller.items.single.displayName, 'Synthetic server');
        expect(
          controller.items.single.authKind,
          mode == 'rsa2048' ? AuthKind.privateKey : AuthKind.password,
        );
        expect(protects, 1);
        final saved = h.repository.read(
          (r) => r.profile(controller.items.single.profileId)!,
        );
        expect(
          h.repository.read(
            (r) => r.credential(saved.credentialId)!.protectedBytes,
          ),
          [81, 82, 83],
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
