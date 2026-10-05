import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rustore_update/flutter_rustore_update.dart';
import 'package:serverdeck/data/app_updates.dart';
import 'package:serverdeck/data/rustore_updates.dart';

class FakeStore implements RuStoreBridge {
  final stream = StreamController<RequestResponse>.broadcast(sync: true);
  int availability = 2, status = 0, result = -1, installs = 0, opens = 0;
  bool fail = false;
  @override
  Stream<RequestResponse> get states => stream.stream;
  @override
  Future<UpdateInfo> info() async {
    if (fail) throw StateError('fixture unavailable');
    return UpdateInfo(
      availableVersionCode: 2,
      installStatus: status,
      packageName: 'dev.unng.serverdeck',
      updateAvailability: availability,
    );
  }

  @override
  Future<DownloadResponse> download() async => DownloadResponse(code: result);
  @override
  Future<void> install() async {
    installs++;
  }

  @override
  Future<void> openStore() async {
    opens++;
  }

  void emit(int state) => stream.add(
    RequestResponse(
      bytesDownloaded: 5,
      totalBytesToDownload: 10,
      installErrorCode: 0,
      installStatus: state,
      packageName: 'dev.unng.serverdeck',
    ),
  );
}

void main() {
  late FakeStore store;
  late RuStoreUpdater updater;
  setUp(() {
    store = FakeStore();
    updater = RuStoreUpdater(
      installedVersion: '0.1.0+1',
      installedBuild: 1,
      packageName: 'dev.unng.serverdeck',
      bridge: store,
    );
  });
  tearDown(() async {
    updater.dispose();
    await store.stream.close();
  });
  test('current, unknown and unavailable states are honest', () async {
    store.availability = 1;
    await updater.check();
    expect(updater.state, UpdateState.current);
    store.availability = 0;
    await updater.check();
    expect(updater.state, UpdateState.unsupported);
    store.fail = true;
    await updater.check();
    expect(updater.state, UpdateState.error);
    await updater.openStore();
    expect(store.opens, 1);
  });
  test(
    'separate download/install actions with progress and stream completion',
    () async {
      await updater.check();
      expect(updater.state, UpdateState.available);
      await updater.openInstaller();
      expect(store.installs, 0);
      await updater.download();
      expect(updater.state, UpdateState.downloading);
      store.emit(2);
      expect(updater.progress, .5);
      store.emit(1);
      expect(updater.state, UpdateState.downloaded);
      expect(store.installs, 0);
      await updater.openInstaller();
      expect(store.installs, 1);
      expect(updater.state, UpdateState.downloaded);
    },
  );
  test(
    'user cancellation permits another download, errors never claim success',
    () async {
      await updater.check();
      store.result = 0;
      await updater.download();
      expect(updater.state, UpdateState.available);
      store.result = -1;
      await updater.download();
      store.emit(0);
      expect(updater.state, UpdateState.available);
      await updater.download();
      store.emit(3);
      expect(updater.state, UpdateState.error);
      expect(store.installs, 0);
    },
  );
}
