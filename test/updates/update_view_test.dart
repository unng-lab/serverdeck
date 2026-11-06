import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/runtime/owned_settings_route.dart';
import 'package:serverdeck/updates/update_owner.dart';
import 'package:serverdeck/updates/update_view.dart';

const _offer = UpdateOffer(
  version: '0.2.0',
  notes: 'Новые возможности и исправления',
  publishedUtc: 1700000000,
  setupSize: 123456,
  platform: 'windows-x64',
  bootstrapAbi: 1,
  storeFormat: 2,
  compatibility: 'compatible',
  compatibilityReason: 'Выпуск совместим с этой установкой.',
);

final class _Port implements UpdatePort {
  UpdateSnapshot value = const UpdateSnapshot(
    currentVersion: '0.1.0',
    state: UpdateState.available,
    enabled: false,
    offer: _offer,
  );
  int downloads = 0, checks = 0, deferrals = 0, cancels = 0;
  String? confirmedVersion;
  Completer<UpdateSnapshot>? reply;
  bool noOpCancel = false;
  @override
  Future<UpdateSnapshot> snapshot() async => reply?.future ?? value;
  @override
  Future<bool> check() async {
    checks++;
    value = const UpdateSnapshot(
      currentVersion: '0.1.0',
      state: UpdateState.checking,
      enabled: false,
    );
    return true;
  }

  @override
  Future<bool> download(String version) async {
    downloads++;
    confirmedVersion = version;
    value = const UpdateSnapshot(
      currentVersion: '0.1.0',
      state: UpdateState.downloading,
      enabled: false,
      offer: _offer,
    );
    return true;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    if (noOpCancel) return;
    value = const UpdateSnapshot(
      currentVersion: '0.1.0',
      state: UpdateState.failed,
      enabled: false,
      code: 'CANCELLED',
    );
  }

  @override
  Future<void> defer() async {
    deferrals++;
    value = UpdateSnapshot(
      currentVersion: '0.1.0',
      enabled: false,
      preparedVersion: value.preparedVersion,
      preparedCode: value.preparedCode,
    );
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    value = value.withEnabled(enabled);
  }
}

Future<UpdateOwner> _mount(WidgetTester tester, _Port port) async {
  final owner = UpdateOwner(
    port: port,
    currentVersion: '0.1.0',
    schedule: (_, _) => () {},
  );
  await owner.start();
  await tester.pumpWidget(
    MaterialApp(
      theme: BrandTheme.light,
      home: Scaffold(body: UpdateView(owner: owner)),
    ),
  );
  return owner;
}

Future<void> _tap(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'failed status read after late cancel never displays a false cancelled message',
    (tester) async {
      final port = _Port();
      port.value = const UpdateSnapshot(
        currentVersion: '0.1.0',
        state: UpdateState.verifying,
        enabled: false,
        offer: _offer,
      );
      final owner = await _mount(tester, port);
      port.noOpCancel = true;
      port.value = const UpdateSnapshot(
        currentVersion: '0.1.0',
        state: UpdateState.ready,
        enabled: false,
        offer: _offer,
      );
      final reply = Completer<UpdateSnapshot>();
      port.reply = reply;
      await _tap(tester, 'Отменить');
      expect(find.text('Проверка или скачивание отменены.'), findsNothing);
      reply.completeError(const FormatException('synthetic read failure'));
      await owner.drain();
      await tester.pump();
      expect(find.text('Проверка или скачивание отменены.'), findsNothing);
      port.reply = null;
      await owner.refresh();
      await tester.pump();
      expect(find.text('Обновление готово'), findsOneWidget);
      await owner.dispose();
    },
  );
  testWidgets(
    'new offer and later retain the separately prepared version and reason',
    (tester) async {
      final port = _Port();
      port.value = const UpdateSnapshot(
        currentVersion: '0.1.0',
        state: UpdateState.available,
        enabled: false,
        offer: _offer,
        preparedVersion: '0.1.1',
        preparedCode: 'RELEASE_REVOKED',
      );
      final owner = await _mount(tester, port);
      expect(find.text('Ранее подготовлено 0.1.1'), findsOneWidget);
      expect(
        find.textContaining('больше не доступен в каталоге'),
        findsOneWidget,
      );
      expect(find.text('0.2.0'), findsOneWidget);
      await _tap(tester, 'Позже');
      expect(find.text('Ранее подготовлено 0.1.1'), findsOneWidget);
      expect(port.downloads, 0);
      await owner.dispose();
    },
  );
  testWidgets('global owned settings retirement closes nested update consent', (
    tester,
  ) async {
    final port = _Port();
    final owner = UpdateOwner(
      port: port,
      currentVersion: '0.1.0',
      schedule: (_, _) => () {},
    );
    await owner.start();
    final route = OwnedSettingsRoute();
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                route.show(
                  context,
                  child: UpdateView(owner: owner),
                  onChanged: () {},
                ),
              ),
              child: const Text('Открыть настройки'),
            ),
          ),
        ),
      ),
    );
    await _tap(tester, 'Открыть настройки');
    await _tap(tester, 'Подготовить обновление');
    expect(find.text('Подготовить обновление 0.2.0?'), findsOneWidget);
    await owner.stopAdmission();
    route.retire();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Подготовить обновление 0.2.0?'), findsNothing);
    expect(port.downloads, 0);
    await owner.dispose();
  });
  testWidgets(
    'cancel remains actionable while accepted command refresh is delayed',
    (tester) async {
      for (final download in [false, true]) {
        final port = _Port();
        final owner = await _mount(tester, port);
        final delayed = Completer<UpdateSnapshot>();
        port.reply = delayed;
        if (download) {
          await _tap(tester, 'Подготовить обновление');
          await _tap(tester, 'Скачать и установить при следующем запуске');
        } else {
          await _tap(tester, 'Проверить сейчас');
        }
        final late = port.value;
        port.reply = null;
        await _tap(tester, 'Отменить');
        expect(port.cancels, 1);
        delayed.complete(late);
        await owner.drain();
        expect(owner.snapshot.state, UpdateState.failed);
        await tester.pumpWidget(const SizedBox.shrink());
        await owner.dispose();
      }
    },
  );
  testWidgets('shows signed release data and requires C14 before download', (
    tester,
  ) async {
    final port = _Port();
    final owner = await _mount(tester, port);
    expect(find.text('0.1.0'), findsOneWidget);
    expect(find.text('0.2.0'), findsOneWidget);
    expect(find.text('123456 байт'), findsOneWidget);
    expect(find.text('windows-x64'), findsOneWidget);
    expect(find.text('2023-11-14T22:13:20.000Z · UTC'), findsOneWidget);
    expect(find.textContaining('ABI 1; формат данных 2.'), findsOneWidget);
    expect(find.text(_offer.notes), findsOneWidget);
    expect(port.downloads, 0);
    await _tap(tester, 'Подготовить обновление');
    expect(find.text('Подготовить обновление 0.2.0?'), findsOneWidget);
    expect(find.textContaining('следующем запуске программы'), findsOneWidget);
    expect(port.downloads, 0);
    await _tap(tester, 'Отмена');
    expect(port.downloads, 0);
    await _tap(tester, 'Подготовить обновление');
    await _tap(tester, 'Скачать и установить при следующем запуске');
    expect(port.downloads, 1);
    expect(port.confirmedVersion, _offer.version);
    await owner.dispose();
  });

  testWidgets(
    'later and manual check do not download or enable automatic checks',
    (tester) async {
      final port = _Port();
      final owner = await _mount(tester, port);
      await _tap(tester, 'Позже');
      expect(port.deferrals, 1);
      expect(port.downloads, 0);
      await _tap(tester, 'Проверить сейчас');
      expect(port.checks, 1);
      expect(owner.snapshot.enabled, isFalse);
      expect(port.downloads, 0);
      await owner.dispose();
    },
  );

  testWidgets('changed offer while dialog is open requires new confirmation', (
    tester,
  ) async {
    final port = _Port();
    final owner = await _mount(tester, port);
    await _tap(tester, 'Подготовить обновление');
    port.value = const UpdateSnapshot(
      currentVersion: '0.1.0',
      state: UpdateState.available,
      enabled: false,
      offer: UpdateOffer(
        version: '0.2.0',
        notes: 'Другой выпуск',
        publishedUtc: 1700000100,
        setupSize: 654321,
        platform: 'windows-x64',
        bootstrapAbi: 1,
        storeFormat: 2,
        compatibility: 'compatible',
        compatibilityReason: 'Совместимо',
      ),
    );
    await owner.refresh();
    await tester.pump();
    await _tap(tester, 'Скачать и установить при следующем запуске');
    expect(port.downloads, 0);
    expect(find.text('654321 байт'), findsOneWidget);
    await owner.dispose();
  });

  testWidgets('unknown download length stays distinct from signed setup size', (
    tester,
  ) async {
    final port = _Port();
    port.value = const UpdateSnapshot(
      currentVersion: '0.1.0',
      state: UpdateState.downloading,
      enabled: false,
      offer: _offer,
      bytes: 4096,
    );
    final owner = await _mount(tester, port);
    expect(find.text('123456 байт'), findsOneWidget);
    expect(
      find.text('4096 байт · общий объём загрузки не сообщён'),
      findsOneWidget,
    );
    await _tap(tester, 'Отменить');
    expect(port.cancels, 1);
    await owner.dispose();
  });

  testWidgets('ready instructs tray exit and has no restart action', (
    tester,
  ) async {
    final port = _Port();
    port.value = const UpdateSnapshot(
      currentVersion: '0.1.0',
      state: UpdateState.ready,
      enabled: false,
      offer: _offer,
    );
    final owner = await _mount(tester, port);
    expect(find.text('Обновление готово'), findsOneWidget);
    expect(
      find.textContaining('выйдите из ServerDeck через меню трея'),
      findsOneWidget,
    );
    expect(find.text('Перезапустить'), findsNothing);
    expect(port.downloads, 0);
    await owner.dispose();
  });

  testWidgets(
    'failure and unconfigured source are distinguishable from current',
    (tester) async {
      final port = _Port();
      port.value = const UpdateSnapshot(
        currentVersion: '0.1.0',
        state: UpdateState.failed,
        enabled: false,
        code: 'UPDATE_NOT_CONFIGURED',
      );
      final owner = await _mount(tester, port);
      expect(
        find.text('Источник обновлений не настроен для этой сборки.'),
        findsOneWidget,
      );
      expect(find.text('Установлена актуальная версия'), findsNothing);
      port.value = const UpdateSnapshot(
        currentVersion: '0.1.0',
        state: UpdateState.failed,
        enabled: false,
        code: 'NETWORK_UNAVAILABLE',
      );
      await owner.refresh();
      await tester.pump();
      expect(
        find.text('Источник обновлений недоступен. Проверьте подключение.'),
        findsOneWidget,
      );
      expect(find.text('Установлена актуальная версия'), findsNothing);
      await owner.dispose();
    },
  );
}
