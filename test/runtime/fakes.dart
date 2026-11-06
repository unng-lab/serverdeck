import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:serverdeck/runtime/capability.dart';
import 'package:serverdeck/runtime/native_platform.dart';

class FakePlatform implements RuntimePlatform {
  @override
  final ValueNotifier<String?> release = ValueNotifier<String?>('0.1.0+1');
  final controller = StreamController<PlatformEvent>.broadcast(sync: true);
  bool tray = true, visible = true, exited = false, activationClosed = false;
  int seq = 0;
  bool exitLatch = false, failActivation = false, failExit = false;
  int activationCloses = 0, exits = 0;
  @override
  Stream<PlatformEvent> get events => controller.stream;
  void emit(String type, {String epoch = 'owner', int? sequence}) {
    seq = sequence ?? seq + 1;
    controller.add(PlatformEvent(epoch, seq, type));
  }

  @override
  Future<PlatformSnapshot> snapshot({String? runtimeState}) async =>
      PlatformSnapshot(
        epoch: 'owner',
        seq: seq,
        window: visible ? WindowState.visible : WindowState.trayHidden,
        trayAvailable: tray,
        osEnding: false,
        exitRequested: exitLatch,
      );
  @override
  Future<bool> hideToTray() async {
    if (tray) visible = false;
    return tray;
  }

  @override
  Future<bool> restore() async {
    visible = true;
    return true;
  }

  @override
  Future<bool> retryTray() async => tray;
  @override
  Future<void> closeActivation() async {
    activationCloses++;
    if (failActivation) throw StateError('activation close failure');
    activationClosed = true;
  }

  @override
  Future<void> finishExit() async {
    exits++;
    if (failExit) throw StateError('exit failure');
    exited = true;
  }
}

class FakeStore implements RuntimeStore {
  @override
  String get theme => 'dark';
  bool admitted = false, closed = false, failOpen = false, failClose = false;
  int opens = 0, closes = 0;
  bool failWrites = false;
  Completer<void>? write, opening;
  @override
  Future<void> open() async {
    opens++;
    await opening?.future;
    if (failOpen) throw StateError('open failure');
    admitted = true;
  }

  @override
  void stopAdmission() => admitted = false;
  @override
  Future<void> finishWrites() async {
    if (failWrites) throw StateError('write drain failure');
    await write?.future;
  }

  @override
  Future<void> close() async {
    closes++;
    if (failClose) throw StateError('close failure');
    closed = true;
  }
}

class FakeCapability implements RuntimeCapability {
  FakeCapability({this.id = 'synthetic', this.onDispose});
  final void Function()? onDispose;
  final calls = <String>[];
  String? failure;
  Completer<void>? pending;
  String pendingStage = 'drain';
  @override
  final String id;
  Future<void> step(String name) async {
    calls.add(name);
    if (name == pendingStage) await pending?.future;
    if (failure == name) throw StateError('synthetic failure');
  }

  @override
  Future<void> stopAdmission() => step('stop');
  @override
  Future<void> cancelPending() => step('cancel');
  @override
  Future<void> closeSessions() => step('sessions');
  @override
  Future<void> drain() => step('drain');
  @override
  Future<void> dispose() async {
    await step('dispose');
    onDispose?.call();
  }
}

Future<void> settleEvents() => Future<void>.delayed(Duration.zero);
