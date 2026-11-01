import 'dart:async';

import 'package:flutter/services.dart';
import 'package:serverdeck_engine/hosting/worker_controller.dart';

import 'desktop_lifecycle.dart';

final class NativeDesktopPlatform implements DesktopPlatform {
  NativeDesktopPlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'action' || call.arguments is! String) return;
      final event = DesktopAction.values
          .where((e) => e.name == call.arguments)
          .firstOrNull;
      if (event != null) _events.add(event);
    });
  }
  final _channel = const MethodChannel('serverdeck/desktop');
  final _events = StreamController<DesktopAction>.broadcast(sync: true);
  @override
  Stream<DesktopAction> get events => _events.stream;
  @override
  Future<bool> initialize() async =>
      await _channel.invokeMethod<bool>('initialize') ?? false;
  @override
  Future<bool> hide() async =>
      await _channel.invokeMethod<bool>('hide') ?? false;
  @override
  Future<void> show() => _channel.invokeMethod<void>('show');
  @override
  Future<void> update(DesktopEngineStatus status) =>
      _channel.invokeMethod<void>('status', {
        'phase': status.status.phase,
        'mcpSessions': status.mcpSessions,
      });
  @override
  Future<bool> fallbackClose() async =>
      await _channel.invokeMethod<bool>('fallbackClose') ?? false;
  @override
  Future<bool> confirmExit(int? count) async =>
      await _channel.invokeMethod<bool>('confirmExit', count) ?? false;
  @override
  Future<BlockedChoice> blockedClose() async {
    final choice = await _channel.invokeMethod<String>('blockedClose');
    return BlockedChoice.values.where((c) => c.name == choice).firstOrNull ??
        BlockedChoice.stay;
  }

  @override
  Future<void> finishExit() => _channel.invokeMethod<void>('finishExit');
  @override
  Future<void> forceExit() => _channel.invokeMethod<void>('forceExit');
}
