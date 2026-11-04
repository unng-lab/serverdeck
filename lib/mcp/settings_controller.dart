import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/actor.dart';
import '../domain/models.dart';
import 'grant_owner.dart';

final class McpSettingsController extends ChangeNotifier {
  McpSettingsController({
    required this.owner,
    required this.actor,
    required this.retryTransport,
    required this.transportError,
    bool poll = true,
  }) {
    if (poll)
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(refresh()),
      );
  }
  final GrantOwner owner;
  final UiActor actor;
  final Future<void> Function() retryTransport;
  final String? Function() transportError;
  List<GrantInfo> grants = [];
  OperationFailure? error;
  McpConfiguration? configuration;
  bool pending = false, _disposed = false;
  Timer? _timer;
  Future<void>? _refresh;
  bool get enabled => owner.enabled;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() => _disposed
      ? Future<void>.value()
      : _refresh ??= _load().whenComplete(() => _refresh = null);
  Future<void> _load() async {
    try {
      final result = await owner.list(actor);
      if (!_disposed) grants = List.unmodifiable(result);
    } on OperationFailure catch (e) {
      if (!_disposed) error = e;
    } catch (_) {
      if (!_disposed)
        error = const OperationFailure(FailureCode.storageUnavailable);
    }
    _notify();
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_disposed || pending) return;
    pending = true;
    error = null;
    configuration = null;
    _notify();
    try {
      await action();
    } on OperationFailure catch (e) {
      error = e;
    } catch (_) {
      error = const OperationFailure(FailureCode.storageUnavailable);
    } finally {
      pending = false;
      if (!_disposed) {
        await refresh();
        _notify();
      }
    }
  }

  Future<void> issue(String name, {required bool confirmed}) =>
      _action(() async {
        final grant = await owner.issue(actor, name, confirmed: confirmed);
        configuration = await owner.configuration(actor, grant.clientId);
      });
  Future<void> rotate(String id, {required bool confirmed}) =>
      _action(() async {
        await owner.rotate(actor, id, confirmed: confirmed);
        configuration = await owner.configuration(actor, id);
      });
  Future<void> revoke(String id, {required bool confirmed}) =>
      _action(() async {
        await owner.revoke(actor, id, confirmed: confirmed);
      });
  Future<void> retry(String id) => _action(() => owner.retry(actor, id));
  Future<void> showConfiguration(String id) => _action(() async {
    configuration = await owner.configuration(actor, id);
  });
  Future<void> setEnabled(bool value) =>
      _action(() => owner.setEnabled(actor, value));
  Future<void> retryMcp() => _action(retryTransport);
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
