import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'runtime/native_platform.dart';
import 'runtime/runtime_coordinator.dart';
import 'storage/workspace_store.dart';
import 'runtime/capability.dart';

import 'dart:typed_data';

import 'domain/mutation_receipts.dart';
import 'runtime/feature_runtime.dart';
import 'storage/domain_repository.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = NativePlatform(epoch: arguments.single);
  final store = DesktopWorkspace(platform);
  final runtime = RuntimeCoordinator(
    platform: platform,
    store: store,
    epoch: platform.epoch,
  );
  store.isRunning = () => runtime.acceptsOperations;
  runtime.register(store);
  runApp(
    ServerDeckApp(
      runtime: runtime,
      store: store,
      features: () => store.features,
    ),
  );
  unawaited(runtime.start());
}

/// Platform/bootstrap failures use the same visible retry and tray-exit path as
/// database failures; the first frame does not depend on opening native storage.
class DesktopWorkspace implements RuntimeStore, RuntimeCapability {
  DesktopWorkspace(this.platform);
  final NativePlatform platform;
  WorkspaceStore? _store;
  bool _stopped = false;
  bool Function() isRunning = () => false;
  FeatureRuntime? features;
  Future<void>? _opening;
  @override
  String get id => 'workspace-features';
  @override
  String get theme => _store?.theme ?? 'dark';
  @override
  Future<void> open() =>
      _opening ??= _open().whenComplete(() => _opening = null);
  Future<void> _open() async {
    if (_store == null) {
      final context = await platform.initialize();
      _store = WorkspaceStore(
        dataRoot: context.dataRoot,
        libraryPath: '${context.runtimeRoot}\\libisar.dll',
        flushAtomic: platform.flushAtomic,
        protectReceiptKey: (bytes) =>
            platform.protect(bytes, 'receipt-hmac.v1'),
      );
    }
    await _store!.open();
    if (_stopped) {
      _store!.stopAdmission();
      return;
    }
    if (features == null) {
      final repository = WorkspaceDomainRepository(_store!);
      final cipher = Uint8List.fromList(
        repository.read((r) => r.security.protectedReceiptHmacKey),
      );
      Uint8List? key;
      try {
        key = await platform.unprotect(cipher, 'receipt-hmac.v1');
        if (_stopped) return;
        features = FeatureRuntime(
          platform: platform,
          repository: repository,
          signer: ReceiptSigner(key),
          isRunning: isRunning,
        );
      } finally {
        cipher.fillRange(0, cipher.length, 0);
        key?.fillRange(0, key.length, 0);
      }
    }
    if (!_stopped) await features!.initialize();
  }

  @override
  Future<void> stopAdmission() async {
    _stopped = true;
    await features?.stopAdmission();
    _store?.stopAdmission();
  }

  @override
  Future<void> finishWrites() async => await _store?.finishWrites();
  @override
  Future<void> close() async {
    await features?.dispose();
    await _store?.close();
  }

  @override
  Future<void> cancelPending() async {
    await features?.cancelPending();
  }

  @override
  Future<void> closeSessions() async {
    await features?.closeSessions();
  }

  @override
  Future<void> drain() async {
    await _opening;
    await features?.drain();
  }

  @override
  Future<void> dispose() async {
    await features?.dispose();
  }
}
