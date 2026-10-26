import 'dart:async';

import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

import '../theme/motion.dart';
import '../theme/brand_tokens.dart';
import 'server_controller.dart';
import 'server_sections.dart';

/// Remote operations use the same service as MCP through a verified owner RPC.
class ServerPanel extends StatefulWidget {
  const ServerPanel({super.key, required this.client, required this.profile});
  final TrustedApiClient client;
  final ProfileView profile;
  @override
  State<ServerPanel> createState() => _ServerPanelState();
}

class _ServerPanelState extends State<ServerPanel> {
  late ServerController model;
  final _text = TextEditingController();
  final _profileChanges = ValueNotifier(0);
  bool _retired = false;
  ServerPresentationOperation _operation = ServerPresentationOperation.read;
  Object? _trustConfirmChallenge;
  bool _dispatching = false, _wasBusy = false;
  String _resource = 'system.motd';
  @override
  void initState() {
    super.initState();
    _create();
  }

  void _create() {
    _operation = ServerPresentationOperation.read;
    _trustConfirmChallenge = null;
    _wasBusy = false;
    model = ServerController(
      client: widget.client,
      profileId: widget.profile.id,
    );
    model.addListener(_observeOperation);
    model.refresh().ignore();
  }

  void _observeOperation() {
    // A sampler/read that starts outside an explicit panel dispatch must not
    // inherit an old write label. This observes existing owner notifications.
    if (model.busy && !_wasBusy && !_dispatching) {
      _operation = ServerPresentationOperation.read;
      _trustConfirmChallenge = null;
    }
    _wasBusy = model.busy;
  }

  Future<void> _dispatch(
    ServerPresentationOperation operation,
    Future<void> Function() action,
  ) async {
    if (!mounted || _retired || model.busy || widget.client.isClosed) return;
    _operation = operation;
    _trustConfirmChallenge =
        operation == ServerPresentationOperation.trustConfirm
        ? model.trustChallenge
        : null;
    _dispatching = true;
    late Future<void> result;
    try {
      result = action();
    } finally {
      _dispatching = false;
    }
    await result;
  }

  @override
  void didUpdateWidget(covariant ServerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client) ||
        oldWidget.profile.id != widget.profile.id) {
      model.removeListener(_observeOperation);
      model.dispose();
      _create();
    }
    _profileChanges.value++;
  }

  @override
  void dispose() {
    _retired = true;
    _profileChanges.value++;
    model.removeListener(_observeOperation);
    model.dispose();
    _text.dispose();
    _profileChanges.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, Widget content, String action) {
    final profile = widget.profile;
    return showServerConfirmationDialog(
      context: context,
      profile: profile,
      title: title,
      child: content,
      confirmLabel: action,
    );
  }

  Future<void> _trust() async {
    final owner = model;
    final challenge = model.trustChallenge;
    if (challenge == null) return;
    final profile = widget.profile;
    if (await showMotionDialog<bool>(
              context: context,
              barrierDismissible: true,
              builder: (context) => ServerTrustConfirmation(
                challenge: challenge,
                profile: profile,
                changes: Listenable.merge([owner, _profileChanges]),
                currentProfile: () =>
                    mounted && !_retired ? widget.profile : null,
                currentChallenge: () =>
                    mounted && !_retired && identical(owner, model)
                    ? model.trustChallenge
                    : null,
                onCancel: () => Navigator.pop(context, false),
                onConfirm: () => Navigator.pop(context, true),
              ),
            ) ==
            true &&
        mounted &&
        identical(owner, model) &&
        identical(challenge, model.trustChallenge) &&
        serverTrustReviewIsCurrent(
          challenge: challenge,
          profile: profile,
          currentProfile: widget.profile,
          currentChallenge: model.trustChallenge,
        ))
      await _dispatch(
        ServerPresentationOperation.trustConfirm,
        model.confirmTrust,
      );
  }

  Future<void> _executor() async {
    final owner = model;
    final inspection = model.executorInspection;
    if (inspection == null) return;
    final profile = widget.profile;
    final changes = Listenable.merge([owner, _profileChanges]);
    bool current() =>
        mounted &&
        !_retired &&
        identical(owner, model) &&
        serverExecutorReviewIsCurrent(
          inspection: inspection,
          profile: profile,
          currentProfile: widget.profile,
          currentInspection: model.executorInspection,
        );
    var retired = !current();
    void observe() => retired = retired || !current();
    changes.addListener(observe);
    try {
      final confirmed = await showMotionDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (context) => ServerExecutorConfirmation(
          inspection: inspection,
          profile: profile,
          changes: changes,
          currentProfile: () => mounted && !_retired ? widget.profile : null,
          currentInspection: () =>
              mounted && !_retired && identical(owner, model)
              ? model.executorInspection
              : null,
          onCancel: () => Navigator.pop(context, false),
          onConfirm: () => Navigator.pop(context, true),
        ),
      );
      if (confirmed == true && !retired && current())
        await _dispatch(
          ServerPresentationOperation.executorWrite,
          owner.confirmExecutor,
        );
    } finally {
      changes.removeListener(observe);
    }
  }

  Future<void> _revokeTrust() async {
    if (await _confirm(
          'Отозвать доверие',
          const Text(
            'Доступ к серверу будет остановлен до нового подтверждения ключа.',
          ),
          'Отозвать',
        ) &&
        mounted)
      // This handler reads before its write. Without an owner phase marker a
      // timeout cannot establish whether the revoke was dispatched or ACKed.
      await _dispatch(
        ServerPresentationOperation.trustRevoke,
        model.revokeTrust,
      );
  }

  Future<void> _revokeExecutor() async {
    if (await _confirm(
          'Отозвать привязку',
          const Text(
            'Новые изменения через этот исполнитель будут недоступны.',
          ),
          'Отозвать',
        ) &&
        mounted)
      await _dispatch(
        ServerPresentationOperation.executorWrite,
        model.revokeExecutor,
      );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      // Keep the target and result that supplied these rows together. A later
      // owner update must not relabel an already displayed record on tap.
      final profile = widget.profile;
      final logs = model.logs;
      final recordContext = ServerLogRecordContext.capture(profile, logs);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ServerOverviewSection(
            state: model.state,
            connection: ServerConnectionSection(
              connection: model.connection,
              trust: model.trust,
              busy: model.busy,
              error: model.error,
              operation: _operation,
              // confirmTrust clears the exact challenge only after its write
              // reply, before its existing readback. Client closure also clears
              // it, so that retirement must never be interpreted as an ACK.
              trustWriteAcknowledged:
                  _operation == ServerPresentationOperation.trustConfirm &&
                  _trustConfirmChallenge != null &&
                  model.trustChallenge == null &&
                  !widget.client.isClosed,
              hasTrustChallenge: model.trustChallenge != null,
              onRefresh: () => _dispatch(
                ServerPresentationOperation.read,
                model.refresh,
              ).ignore(),
              onProbeTrust: () => _dispatch(
                ServerPresentationOperation.read,
                model.probeTrust,
              ).ignore(),
              onConfirmTrust: () => _trust().ignore(),
              onConnect: () => _dispatch(
                ServerPresentationOperation.connectionWrite,
                model.connect,
              ).ignore(),
              onDisconnect: () => _dispatch(
                ServerPresentationOperation.connectionWrite,
                model.disconnect,
              ).ignore(),
              onRevokeTrust: () => _revokeTrust().ignore(),
              onCancel: () {
                _operation = ServerPresentationOperation.read;
                _trustConfirmChallenge = null;
                model.cancel().ignore();
              },
            ),
          ),
          const SizedBox(height: BrandSpacing.space16),
          ServerExecutorSection(
            executor: model.executor,
            hasInspection: model.executorInspection != null,
            busy: model.busy,
            onRefreshState: () => _dispatch(
              ServerPresentationOperation.read,
              model.refreshState,
            ).ignore(),
            onInspect: () => _dispatch(
              ServerPresentationOperation.read,
              model.inspectExecutor,
            ).ignore(),
            onConfirm: () => _executor().ignore(),
            onRevoke: () => _revokeExecutor().ignore(),
          ),
          const SizedBox(height: BrandSpacing.space16),
          ServerConfigurationSection(
            resource: _resource,
            busy: model.busy,
            onResourceChanged: (value) {
              if (value != null) setState(() => _resource = value);
            },
            onRead: () => _dispatch(
              ServerPresentationOperation.read,
              () => model.readConfiguration(_resource),
            ).ignore(),
            result: model.configuration == null
                ? null
                : _Configuration(value: model.configuration!),
          ),
          const SizedBox(height: BrandSpacing.space16),
          ServerLogsSection(
            logs: logs,
            filterController: _text,
            busy: model.busy,
            onLoad: () => _dispatch(
              ServerPresentationOperation.read,
              () => model.loadLogs(text: _text.text),
            ).ignore(),
            onPrevious: () => _dispatch(
              ServerPresentationOperation.read,
              () => model.loadLogs(
                text: _text.text,
                cursor: logs!['nextCursor'] as String,
              ),
            ).ignore(),
            onOpenRecord: (row) => showMotionDialog<void>(
              context: context,
              barrierDismissible: true,
              builder: (context) => ServerLogRecordDialog(
                recordContext: recordContext,
                record: row,
                onClose: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _Configuration extends StatefulWidget {
  const _Configuration({required this.value});
  final Map<String, Object?> value;
  @override
  State<_Configuration> createState() => _ConfigurationState();
}

class _ConfigurationState extends State<_Configuration> {
  Timer? _age;
  Map<String, Object?> get value => widget.value;
  @override
  void initState() {
    super.initState();
    _scheduleAge();
  }

  @override
  void didUpdateWidget(covariant _Configuration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.value, widget.value)) _scheduleAge();
  }

  void _scheduleAge() {
    _age?.cancel();
    final comparison = value['comparison'] as Map<String, Object?>;
    if (!const {'matched', 'drift'}.contains(comparison['status'])) return;
    final observed = DateTime.tryParse('${comparison['observedAt']}');
    if (observed == null) return;
    final left = observed
        .add(const Duration(seconds: 15, milliseconds: 1))
        .difference(DateTime.now().toUtc());
    if (left <= Duration.zero) return;
    _age = Timer(left, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _age?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comparison = value['comparison'] as Map<String, Object?>;
    var comparisonStatus = comparison['status'];
    if (const {'matched', 'drift'}.contains(comparisonStatus)) {
      final observed = DateTime.tryParse('${comparison['observedAt']}');
      final age = observed == null
          ? null
          : DateTime.now().toUtc().difference(observed);
      if (age == null || age.isNegative || age > const Duration(seconds: 15))
        comparisonStatus = 'stale';
    }
    return ServerConfigurationResult(
      value: value,
      comparisonStatus: comparisonStatus,
    );
  }
}
