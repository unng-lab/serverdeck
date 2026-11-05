import 'dart:async';

import 'package:flutter/services.dart';

import '../updates/update_owner.dart';

enum WindowState { visible, minimized, trayHidden }

class PlatformSnapshot {
  const PlatformSnapshot({
    required this.epoch,
    required this.seq,
    required this.window,
    required this.trayAvailable,
    required this.osEnding,
    this.exitRequested = false,
  });
  final String epoch;
  final int seq;
  final WindowState window;
  final bool trayAvailable, osEnding;
  final bool exitRequested;

  factory PlatformSnapshot.decode(Map<Object?, Object?> value) =>
      PlatformSnapshot(
        epoch: value['ownerEpoch'] as String,
        seq: value['seq'] as int,
        window: WindowState.values.byName(value['windowState'] as String),
        trayAvailable: value['trayAvailable'] as bool,
        osEnding: value['osEnding'] as bool,
        exitRequested: value['exitRequested'] == true,
      );
}

/// Restricted owner port: only version/boolean commands cross the channel.
/// Native code owns policy, URLs, paths, signature verification and file writes.
final class NativeUpdatePort implements UpdatePort, UpdateLifecyclePort {
  const NativeUpdatePort(this.platform);
  final NativePlatform platform;
  Future<bool> _accepted(String method, [Map<String, Object?>? extra]) async {
    final value = await platform._invoke<Object?>(method, extra);
    if (value is! bool) throw const FormatException('Invalid update admission');
    return value;
  }

  @override
  Future<UpdateSnapshot> snapshot() async {
    final value = await platform._invoke<Object?>('updates.snapshot');
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Invalid update snapshot');
    }
    return UpdateSnapshot.decode(value);
  }

  @override
  Future<bool> check() => _accepted('updates.check');
  @override
  Future<bool> download(String version) =>
      _accepted('updates.download', {'version': version});
  @override
  Future<void> cancel() => platform._invoke<void>('updates.cancel');
  @override
  Future<void> setEnabled(bool enabled) =>
      platform._invoke<void>('updates.setEnabled', {'enabled': enabled});
  @override
  Future<void> defer() => platform._invoke<void>('updates.defer');
  @override
  Future<void> stopAdmission() =>
      platform._invoke<void>('updates.stopAdmission');
  @override
  Future<void> drain() async {
    while (!await _accepted('updates.drained')) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }
}

class PlatformEvent {
  const PlatformEvent(
    this.epoch,
    this.seq,
    this.type, [
    this.payload = const {},
  ]);
  final String epoch, type;
  final int seq;
  final Map<Object?, Object?> payload;
}

class PlatformContext {
  const PlatformContext({
    required this.epoch,
    required this.dataRoot,
    required this.runtimeRoot,
    required this.exePath,
    required this.userSid,
    required this.logonSid,
    this.release = '0.1.0',
  });
  final String epoch,
      dataRoot,
      runtimeRoot,
      exePath,
      userSid,
      logonSid,
      release;
}

abstract interface class RuntimePlatform {
  Stream<PlatformEvent> get events;
  Future<PlatformSnapshot> snapshot({String? runtimeState});
  Future<bool> hideToTray();
  Future<bool> restore();
  Future<bool> retryTray();
  Future<void> closeActivation();
  Future<void> finishExit();
}

class NativePlatform implements RuntimePlatform {
  NativePlatform({required this.epoch, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('serverdeck/platform.v1') {
    _channel.setMethodCallHandler(_onMethod);
  }

  final MethodChannel _channel;
  final String epoch;
  final _events = StreamController<PlatformEvent>.broadcast();
  PlatformContext? _context;
  PlatformContext get context => _context!;
  @override
  Stream<PlatformEvent> get events => _events.stream;

  Future<PlatformContext> initialize() async {
    final value = (await _channel.invokeMapMethod<Object?, Object?>(
      'initialize',
      {'ownerEpoch': epoch},
    ))!;
    _context = PlatformContext(
      epoch: value['ownerEpoch'] as String,
      dataRoot: value['dataRoot'] as String,
      runtimeRoot: value['runtimeRoot'] as String,
      exePath: value['exePath'] as String,
      userSid: value['userSid'] as String,
      logonSid: value['logonSid'] as String,
      release: value['release'] as String? ?? '0.1.0',
    );
    return context;
  }

  Future<void> _onMethod(MethodCall call) async {
    if (call.method != 'platform.event') return;
    final value = call.arguments as Map<Object?, Object?>;
    if (value['version'] != 1) return;
    _events.add(
      PlatformEvent(
        value['ownerEpoch'] as String,
        value['seq'] as int,
        value['type'] as String,
        Map<Object?, Object?>.unmodifiable(value),
      ),
    );
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? extra]) =>
      _channel.invokeMethod<T>(method, {'ownerEpoch': epoch, ...?extra});

  /// Native publication must succeed before the caller admits auto connections.
  Future<bool> beginMonitoringRun() async {
    final reply = await _invoke<Object?>('monitoring.beginRun');
    if (reply is! Map || reply['autoAllowed'] is! bool) {
      throw const FormatException('Invalid monitoring run classification');
    }
    return reply['autoAllowed'] as bool;
  }

  @override
  Future<PlatformSnapshot> snapshot({String? runtimeState}) async =>
      PlatformSnapshot.decode(
        (await _invoke<Map<Object?, Object?>>('runtime.snapshot', {
          if (runtimeState != null) 'runtimeState': runtimeState,
        }))!,
      );
  @override
  Future<bool> hideToTray() async =>
      await _invoke<bool>('window.hideToTray') ?? false;
  @override
  Future<bool> restore() async =>
      await _invoke<bool>('window.restore') ?? false;
  @override
  Future<bool> retryTray() async => await _invoke<bool>('tray.retry') ?? false;
  @override
  Future<void> closeActivation() => _invoke<void>('runtime.closeActivation');
  @override
  Future<void> finishExit() =>
      _invoke<void>('runtime.finishExit', {'shutdownComplete': true});

  // Codec replies may be read-only views. Callers own and wipe these copies.
  Future<Uint8List> protect(Uint8List bytes, String purpose) async =>
      Uint8List.fromList(
        (await _invoke<Uint8List>('secret.protect', {
          'bytes': bytes,
          'purpose': purpose,
        }))!,
      );
  Future<Uint8List> unprotect(Uint8List bytes, String purpose) async =>
      Uint8List.fromList(
        (await _invoke<Uint8List>('secret.unprotect', {
          'bytes': bytes,
          'purpose': purpose,
        }))!,
      );
  Future<void> flushAtomic(String path, Uint8List bytes) =>
      _invoke<void>('file.flushAtomic', {'path': path, 'bytes': bytes});

  Future<void> publishMcpOwner() => _invoke<void>('mcp.publishOwner');
  Future<void> removeMcpOwner() => _invoke<void>('mcp.removeOwner');
  Future<void> sendMcpFrame(String channelId, String frame) =>
      _invoke<void>('mcp.sendFrame', {'channelId': channelId, 'frame': frame});
  Future<void> closeMcpChannel(String channelId) =>
      _invoke<void>('mcp.closeChannel', {'channelId': channelId});
  Future<void> acknowledgeMcpFrame(String channelId) =>
      _invoke<void>('mcp.ackFrame', {'channelId': channelId});
  Future<void> writeMcpGrant(String clientId, int version, Uint8List bytes) =>
      _invoke<void>('mcp.writeGrantBlob', {
        'clientId': clientId,
        'grantVersion': version,
        'protectedSecret': bytes,
      });
  Future<void> deleteMcpGrant(String clientId) =>
      _invoke<void>('mcp.deleteGrantBlob', {'clientId': clientId});
  Future<Uint8List?> pickPrivateKey() async {
    final bytes = await _invoke<Uint8List>('credential.pickKey');
    return bytes == null ? null : Uint8List.fromList(bytes);
  }
}
