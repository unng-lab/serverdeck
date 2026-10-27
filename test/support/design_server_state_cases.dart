import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/servers/metrics_history.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/remote_reads.dart';

import 'design_host.dart' show loadDesignFonts, expectDesignVisible;
import 'design_server_fixtures.dart';
import 'design_state_capture.dart';
import 'design_state_matrix.dart';

/// Actual server presentation journeys. No genuine native client is replaced.
/// Owner error/phase projections do not prove RPC, SSH or service authority.
void registerDesignServerStateCases({bool fullAdaptive = false}) {
  setUpAll(loadDesignFonts);
  final frames = fullAdaptive
      ? [
          for (final size in const [
            Size(1100, 760),
            Size(800, 600),
            Size(390, 800),
            Size(360, 800),
          ])
            for (final scale in [1.0, 2.0]) _Frame(size, scale),
        ]
      : const [_Frame(Size(1100, 760), 1), _Frame(Size(360, 800), 2)];
  for (final scenario in designStateCases.where(
    (item) => item.taskId == 'T035',
  )) {
    for (final frame in frames) {
      for (final dark in [false, true]) {
        testWidgets(
          '${scenario.caseId} ${frame.suffix} ${dark ? 'dark' : 'light'}',
          (tester) async {
            final counts = _Counts();
            if (scenario.originId == '06-server-overview') {
              await _overview(tester, scenario, frame, dark, counts);
            } else if (scenario.originId == '22-server-logs') {
              await _logs(tester, scenario, frame, dark, counts);
            } else if (scenario.originId == '23-log-record') {
              await _record(tester, scenario, frame, dark, counts);
            } else {
              await _review(tester, scenario, frame, dark, counts);
            }
            for (final action in scenario.actions) {
              expect(
                _actionCount(action.counter, counts),
                action.expectedDelta,
                reason:
                    '${scenario.caseId}: ${action.trigger}/${action.counter}',
              );
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
  for (final frame in frames) {
    for (final dark in [false, true]) {
      testWidgets(
        'T102 [state-23-log-record-data] pre-open identity ${frame.suffix} ${dark ? 'dark' : 'light'}',
        (tester) async {
          await _recordIdentity(tester, frame, dark);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}

class _Frame {
  const _Frame(this.size, this.scale);
  final Size size;
  final double scale;
  String get suffix => '${size.width.toInt()}-${(scale * 100).toInt()}';
}

final _host = GlobalKey<_HostState>();

class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.child,
    required this.dark,
    required this.scale,
  });
  final Widget child;
  final bool dark;
  final double scale;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool dark = widget.dark;
  late double scale = widget.scale;
  void restyle(bool nextDark, double nextScale) => setState(() {
    dark = nextDark;
    scale = nextScale;
  });
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: designStateCaptureBoundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Motion.theme(dark ? BrandTheme.dark : BrandTheme.light, true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(body: widget.child),
    ),
  );
}

class _Counts {
  final values = <String, int>{};
  int passiveDelta = 0;
  int callsBeforeIntent = 0;
  void hit(String action) =>
      values.update(action, (value) => value + 1, ifAbsent: () => 1);
  int get total => values.values.fold(0, (a, b) => a + b);
  int value(String action) => values[action] ?? 0;
  Map<String, Object?> get snapshot => {'totalUiCallbacks': total, ...values};
}

int _actionCount(String counter, _Counts counts) => switch (counter) {
  'sameActionCallbacks' => counts.total - counts.value('cancel'),
  'confirmCallbacks' => counts.value('confirm'),
  'onClose' => counts.value('close'),
  'recordReadRequests' => counts.value('read') + counts.value('load'),
  'explicitActionCallbacks' => counts.callsBeforeIntent,
  'additionalUiInitiatedOwnerActions' ||
  'automaticRetryCallbacks' ||
  'automaticRefreshCallbacks' ||
  'automaticRecoveryCallbacks' ||
  'automaticConnectCallbacks' ||
  'automaticConfirmConnectCallbacks' => counts.passiveDelta,
  _ => throw StateError('Unmeasured server counter $counter'),
};

Future<void> _mount(
  WidgetTester tester,
  Widget child,
  _Frame frame,
  bool dark,
) async {
  tester.view.physicalSize = frame.size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // Dispose a previous variant rather than retaining its synthetic state.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    _Host(
      key: _host,
      dark: dark,
      scale: frame.scale,
      child: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _passive(
  WidgetTester tester,
  _Frame frame,
  bool dark,
  _Counts counts,
) async {
  final before = Map<String, int>.of(counts.values);
  final totalBefore = counts.total;
  _host.currentState!.restyle(!dark, frame.scale);
  tester.view.physicalSize = Size(
    frame.size.width == 360
        ? 390
        : frame.size.width == 390
        ? 360
        : frame.size.width == 800
        ? 1100
        : 800,
    frame.size.height,
  );
  await tester.pumpAndSettle();
  _host.currentState!.restyle(dark, frame.scale);
  tester.view.physicalSize = frame.size;
  await tester.pumpAndSettle();
  expect(
    counts.values,
    before,
    reason: 'render/theme/resize emits no owner action',
  );
  counts.passiveDelta += counts.total - totalBefore;
  expect(tester.takeException(), isNull);
}

Future<void> _capture(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
  _Counts counts,
  List<String> assertions,
) async {
  counts.callsBeforeIntent = counts.total;
  await _passive(tester, frame, dark, counts);
  await captureDesignState(
    tester,
    family: 'server',
    caseIds: [scenario.caseId],
    phase:
        'server-${scenario.originId.substring(0, 2)}-${scenario.category.name.toLowerCase()}',
    theme: dark ? 'dark' : 'light',
    scale: frame.scale,
    counters: {
      ...counts.snapshot,
      'additionalUiInitiatedOwnerActions': counts.passiveDelta,
      for (final action in scenario.actions)
        action.counter: _actionCount(action.counter, counts),
      'checkpointPhase': 'after-primary-assertions-before-followup-actions',
    },
    assertions: assertions,
    scope: 'productionPresentation',
    limitations: const [
      'Typed synthetic production sections/reviews; no genuine owner RPC or native authority is established.',
      'Only the named primary checkpoint is captured; secondary variants remain test assertions.',
      'Counters describe this checkpoint; explicit close/confirm after capture is asserted by the enclosing test.',
      'Actual private client closure/authorization retirement belongs to T037 composition.',
      'The genuine-client ServerPanel is not mounted here; its dispatch context wiring is a source-review boundary.',
    ],
  );
}

ServerConnectionSection _connection(
  _Counts counts, {
  bool busy = false,
  String? error,
  bool offline = false,
  ServerPresentationOperation operation = ServerPresentationOperation.read,
  bool trustWriteAcknowledged = false,
}) => ServerConnectionSection(
  connection: DesignServerFixtures.connection(
    state: offline ? 'disconnected' : 'connected',
  ),
  trust: DesignServerFixtures.trust(),
  busy: busy,
  error: error,
  operation: operation,
  trustWriteAcknowledged: trustWriteAcknowledged,
  hasTrustChallenge: true,
  onRefresh: () => counts.hit('refresh'),
  onProbeTrust: () => counts.hit('probe'),
  onConfirmTrust: () => counts.hit('confirm'),
  onConnect: () => counts.hit('connect'),
  onDisconnect: () => counts.hit('disconnect'),
  onRevokeTrust: () => counts.hit('revoke'),
  onCancel: () => counts.hit('cancel'),
);

Map<String, Object?> _state({
  String quality = 'known',
  bool stale = false,
  bool absent = false,
  bool empty = false,
  bool cacheDropped = false,
  bool truncated = false,
  int parseErrors = 0,
}) {
  return DesignServerFixtures.state(
    quality: quality,
    stale: stale,
    points: empty ? [] : null,
    valuesAvailable: !absent,
    observedTimeAvailable: !absent,
    cacheDropped: cacheDropped,
    truncated: truncated,
    parseErrors: parseErrors,
    code: cacheDropped ? 'RESOURCE_LIMIT' : null,
  );
}

Finder _button(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    )
    .first;
Future<void> _click(WidgetTester tester, String label) async {
  final button = _button(label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  expect(tester.widget<ButtonStyleButton>(button).onPressed, isNotNull);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void _status(String text, DeckTone tone) {
  final matching = find.byWidgetPredicate(
    (widget) =>
        widget is DeckStatus &&
        widget.label.contains(text) &&
        widget.tone == tone,
  );
  expect(matching, findsWidgets);
  final icon = switch (tone) {
    DeckTone.available => Icons.circle_outlined,
    DeckTone.unavailable => Icons.close,
    DeckTone.unknown => Icons.help_outline,
    DeckTone.warning => Icons.warning_amber_rounded,
    DeckTone.error => Icons.report_outlined,
    DeckTone.running => Icons.timelapse,
    DeckTone.success => Icons.check,
    DeckTone.neutral => Icons.info_outline,
  };
  expect(
    find.descendant(of: matching, matching: find.byIcon(icon)),
    findsWidgets,
  );
}

void _context({bool observation = true, bool received = true}) {
  expect(find.textContaining('Источник:'), findsWidgets);
  if (observation)
    expect(
      find.textContaining('Наблюдение: ${DesignServerFixtures.observedAt}'),
      findsWidgets,
    );
  if (received)
    expect(
      find.textContaining('Получено: ${DesignServerFixtures.observedAt}'),
      findsWidgets,
    );
}

Future<void> _pending(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
  _Counts counts,
  Widget child,
) async {
  await _mount(tester, child, frame, dark);
  expect(find.text('Выполняется операция сервера'), findsOneWidget);
  expect(
    find.byWidgetPredicate((widget) => widget is DeckStatus && widget.pending),
    findsOneWidget,
  );
  for (final element in find.byType(OutlinedButton).evaluate()) {
    expect((element.widget as OutlinedButton).onPressed, isNull);
  }
  expect(find.byIcon(Icons.timelapse), findsOneWidget);
  for (final button
      in find.byType(OutlinedButton).evaluate().take(2).toList()) {
    final target = find.byWidget(button.widget);
    await tester.ensureVisible(target);
    await tester.tap(target, warnIfMissed: false);
    await tester.pumpAndSettle();
  }
  expect(counts.total, 0);
  await _capture(tester, scenario, frame, dark, counts, [
    'Actual owner pending text/static reduced-motion symbol',
    'Duplicate same-action callbacks0; no fictitious modal body status',
  ]);
  await _click(tester, 'Перестать ждать ответ');
  expect(counts.value('cancel'), 1);
  expect(counts.value('confirm'), 0);
  await _mount(tester, _connection(counts, error: 'CANCELLED'), frame, dark);
  _status(
    'Ожидание ответа прекращено. Это не подтверждает результат операции сервера.',
    DeckTone.warning,
  );
}

Future<void> _ownerError(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
  _Counts counts, {
  String? code,
  bool capture = true,
}) async {
  final category = scenario.category;
  final actual =
      code ??
      switch (category) {
        DesignStateCategory.validation => 'VALIDATION',
        DesignStateCategory.denied => 'FORBIDDEN',
        DesignStateCategory.unsupported => 'UNSUPPORTED',
        DesignStateCategory.unknown => 'TIMEOUT',
        _ => throw StateError('Not an owner-error category'),
      };
  if (TrustedLocalError.codes.contains(actual)) {
    TrustedLocalError(actual);
  } else {
    // CURSOR_EXPIRED is a read-operation domain failure, not an outer
    // TrustedLocalError. Validate the actual existing result shape instead.
    captureRemoteReadResult('servers.readStatus', {
      'operationId': DesignServerFixtures.challengeId,
      'state': 'failed',
      'code': actual,
    });
  }
  final operation = category != DesignStateCategory.unknown
      ? ServerPresentationOperation.read
      : scenario.originId == '10-host-trust'
      ? ServerPresentationOperation.trustConfirm
      : scenario.originId == '40-executor-binding'
      ? ServerPresentationOperation.executorWrite
      : ServerPresentationOperation.connectionWrite;
  await _mount(
    tester,
    _connection(counts, error: actual, operation: operation),
    frame,
    dark,
  );
  final expected = switch (actual) {
    'VALIDATION' => 'Проверьте параметры операции сервера.',
    'FORBIDDEN' => 'Недостаточно прав для этой операции.',
    'UNAUTHORIZED' => 'Доступ к локальному сервису больше не подтверждён.',
    'UNSUPPORTED' =>
      'Операция не поддерживается текущим сервисом или сервером.',
    'STORAGE_BLOCKED' => 'Защищённое хранилище недоступно. Восстановите защиту хранилища перед повторной операцией.',
    'TRUST_CHANGED' => 'SSH-ключ сервера изменился. Сверьте новый ключ и подтвердите доверие заново.',
    'REVISION_CONFLICT' => 'Данные сервера изменились. Получите их повторно.',
    'CURSOR_EXPIRED' => 'Страница журнала устарела. Получите журнал заново.',
    'TIMEOUT' => 'Исход не подтверждён',
    _ => throw StateError('Missing expected safe label'),
  };
  expect(find.text(expected), findsOneWidget);
  if (actual != 'STORAGE_BLOCKED' && actual != 'TIMEOUT')
    _status(expected, DeckTone.warning);
  if (actual == 'TIMEOUT') _status(expected, DeckTone.unknown);
  expect(counts.total, 0);
  if (capture)
    await _capture(tester, scenario, frame, dark, counts, [
      'Legal typed $actual reason and symbol in actual shared owner status',
      'No automatic retry/confirm/connect callback',
    ]);
  if (category == DesignStateCategory.unknown) {
    // Read timeout and the revoke handler's pre-read failure cannot establish
    // write uncertainty. ACK-followed-by-readback failure is distinct too.
    for (final context in [
      ServerPresentationOperation.read,
      ServerPresentationOperation.trustRevoke,
    ]) {
      await _mount(
        tester,
        _connection(counts, error: 'TIMEOUT', operation: context),
        frame,
        dark,
      );
      expect(find.text('Исход не подтверждён'), findsNothing);
      expect(
        find.text(
          'Время ожидания истекло. Проверьте состояние перед повторной попыткой.',
        ),
        findsOneWidget,
      );
    }
    await _mount(
      tester,
      _connection(
        counts,
        error: 'TIMEOUT',
        operation: ServerPresentationOperation.trustConfirm,
        trustWriteAcknowledged: true,
      ),
      frame,
      dark,
    );
    expect(find.text('Исход не подтверждён'), findsNothing);
    _status(
      'Ответ на запись получен; состояние не перечитано.',
      DeckTone.warning,
    );
    expect(counts.total, 0);
    await _mount(
      tester,
      _connection(
        counts,
        error: 'FORBIDDEN',
        operation: ServerPresentationOperation.trustConfirm,
        trustWriteAcknowledged: true,
      ),
      frame,
      dark,
    );
    _status(
      'Ответ на запись получен; состояние не перечитано.',
      DeckTone.warning,
    );
    expect(find.text('Исход не подтверждён'), findsNothing);
  }
}

Future<void> _overview(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
  _Counts counts,
) async {
  final cat = scenario.category;
  if (cat == DesignStateCategory.loading) {
    await _pending(
      tester,
      scenario,
      frame,
      dark,
      counts,
      ServerOverviewSection(
        connection: _connection(counts, busy: true),
        state: _state(),
      ),
    );
    return;
  }
  if (cat == DesignStateCategory.validation ||
      cat == DesignStateCategory.unknown) {
    await _ownerError(tester, scenario, frame, dark, counts);
    if (cat == DesignStateCategory.validation) {
      await _ownerError(
        tester,
        scenario,
        frame,
        dark,
        counts,
        code: 'TRUST_CHANGED',
        capture: false,
      );
      await _ownerError(
        tester,
        scenario,
        frame,
        dark,
        counts,
        code: 'STORAGE_BLOCKED',
        capture: false,
      );
      await _ownerError(
        tester,
        scenario,
        frame,
        dark,
        counts,
        code: 'REVISION_CONFLICT',
        capture: false,
      );
    }
    return;
  }
  final state = switch (cat) {
    DesignStateCategory.successfulEmpty => _state(empty: true),
    DesignStateCategory.denied => _state(
      quality: 'denied',
      absent: true,
      empty: true,
    ),
    DesignStateCategory.unsupported => _state(
      quality: 'unsupported',
      absent: true,
      empty: true,
    ),
    DesignStateCategory.stale => _state(stale: true),
    DesignStateCategory.dropped => _state(
      quality: 'unknown',
      absent: true,
      empty: true,
      cacheDropped: true,
    ),
    DesignStateCategory.incomplete => _state(truncated: true, parseErrors: 2),
    _ => _state(),
  };
  await _mount(
    tester,
    ServerOverviewSection(
      connection: _connection(
        counts,
        offline: cat == DesignStateCategory.sshUnavailable,
      ),
      state: state,
    ),
    frame,
    dark,
  );
  switch (cat) {
    case DesignStateCategory.successfulEmpty:
      expect(find.text('Истории пока нет.'), findsOneWidget);
      expect(
        tester.widget<MetricsHistory>(find.byType(MetricsHistory)).points,
        isEmpty,
      );
    case DesignStateCategory.data:
      expect(find.text('CPU: 25% · RAM: 50% · Диск /: 75%'), findsOneWidget);
      _context();
    case DesignStateCategory.denied:
      _status('Недостаточно прав', DeckTone.warning);
      expect(find.text('CPU: —% · RAM: —% · Диск /: —%'), findsOneWidget);
      _context(observation: false);
    case DesignStateCategory.unsupported:
      _status('Источник не поддерживается', DeckTone.warning);
      expect(find.text('CPU: —% · RAM: —% · Диск /: —%'), findsOneWidget);
      _context(observation: false);
    case DesignStateCategory.stale:
      _status('Устаревшие данные', DeckTone.warning);
      final graph = tester.widget<MetricsHistory>(find.byType(MetricsHistory));
      expect(graph.stale, isTrue);
      expect(graph.quality, 'known');
      _context();
    case DesignStateCategory.dropped:
      expect(
        find.text(
          'Кэш наблюдений удалён из-за ограничения ресурсов. Ранее полученная история недоступна.',
        ),
        findsOneWidget,
      );
      expect(find.text('Истории пока нет.'), findsNothing);
    case DesignStateCategory.incomplete:
      _status('Получены неполные данные', DeckTone.warning);
      expect(find.text('Ошибок разбора: 2'), findsWidgets);
      expect(find.text('Источник вернул ограниченные данные.'), findsWidgets);
      _context();
    case DesignStateCategory.sshUnavailable:
      _status('Подключение не установлено', DeckTone.unavailable);
    default:
      throw StateError('Unhandled overview category $cat');
  }
  expect(counts.total, 0);
  await _capture(tester, scenario, frame, dark, counts, [
    'Typed actual overview ${cat.name}; source/time/quality not synthesized',
    'Passive UI owner actions0; no implicit connect/recovery',
  ]);
  if (cat == DesignStateCategory.data) {
    await _mount(
      tester,
      ServerOverviewSection(
        connection: _connection(counts),
        state: _state(quality: 'unknown', absent: true, empty: true),
      ),
      frame,
      dark,
    );
    _status('Данных пока нет', DeckTone.unknown);
    expect(find.text('CPU: —% · RAM: —% · Диск /: —%'), findsOneWidget);
    expect(find.text('Исход не подтверждён'), findsNothing);
    expect(find.textContaining('Наблюдение:'), findsNothing);
  }
  if (cat == DesignStateCategory.denied ||
      cat == DesignStateCategory.unsupported) {
    await _ownerError(tester, scenario, frame, dark, counts, capture: false);
  }
  if (cat == DesignStateCategory.incomplete) {
    for (final partial in [
      _state(quality: 'incomplete'),
      _state(parseErrors: 2),
      _state(truncated: true),
    ]) {
      await _mount(
        tester,
        ServerOverviewSection(connection: _connection(counts), state: partial),
        frame,
        dark,
      );
      _status('Получены неполные данные', DeckTone.warning);
    }
    await _mount(
      tester,
      ServerOverviewSection(
        connection: _connection(counts),
        state: _state(stale: true, truncated: true, parseErrors: 2),
      ),
      frame,
      dark,
    );
    _status('Устаревшие данные', DeckTone.warning);
    expect(find.text('Ошибок разбора: 2'), findsWidgets);
  }
  if (cat == DesignStateCategory.dropped) {
    await _mount(
      tester,
      ServerOverviewSection(
        connection: _connection(counts),
        state: DesignServerFixtures.state(
          points: DesignServerFixtures.history(count: 120),
        ),
      ),
      frame,
      dark,
    );
    expect(
      find.text(
        'Кэш наблюдений удалён из-за ограничения ресурсов. Ранее полученная история недоступна.',
      ),
      findsNothing,
    );
    expect(
      tester.widget<MetricsHistory>(find.byType(MetricsHistory)).points,
      hasLength(120),
    );
  }
}

Widget _logsSection(
  _Counts counts,
  Map<String, Object?>? logs,
  TextEditingController filter, {
  bool busy = false,
  ValueChanged<Map<String, Object?>>? open,
}) => ServerLogsSection(
  logs: logs,
  filterController: filter,
  busy: busy,
  onLoad: () => counts.hit('load'),
  onPrevious: () => counts.hit('previous'),
  onOpenRecord: open ?? (_) => counts.hit('open'),
);

Future<void> _logs(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
  _Counts counts,
) async {
  final filter = TextEditingController(text: 'Unicode 例');
  addTearDown(filter.dispose);
  final cat = scenario.category;
  if (cat == DesignStateCategory.loading) {
    await _pending(
      tester,
      scenario,
      frame,
      dark,
      counts,
      Column(
        children: [
          _connection(counts, busy: true),
          _logsSection(
            counts,
            DesignServerFixtures.logs(nextCursor: 'next-page'),
            filter,
            busy: true,
          ),
        ],
      ),
    );
    return;
  }
  if (cat == DesignStateCategory.validation) {
    await _ownerError(tester, scenario, frame, dark, counts);
    await _ownerError(
      tester,
      scenario,
      frame,
      dark,
      counts,
      code: 'CURSOR_EXPIRED',
      capture: false,
    );
    return;
  }
  final data = switch (cat) {
    DesignStateCategory.successfulEmpty => DesignServerFixtures.logs(
      records: [],
    ),
    DesignStateCategory.denied => DesignServerFixtures.logs(
      quality: 'denied',
      records: [],
    ),
    DesignStateCategory.unsupported => DesignServerFixtures.logs(
      quality: 'unsupported',
      records: [],
    ),
    DesignStateCategory.stale => DesignServerFixtures.logs(quality: 'stale'),
    DesignStateCategory.dropped => DesignServerFixtures.logs(dropped: 3),
    DesignStateCategory.incomplete => DesignServerFixtures.logs(
      parseErrors: 2,
      records: [],
    ),
    _ => DesignServerFixtures.logs(nextCursor: 'next-page'),
  };
  await _mount(
    tester,
    Column(
      children: [
        _connection(counts, offline: cat == DesignStateCategory.sshUnavailable),
        _logsSection(counts, data, filter),
      ],
    ),
    frame,
    dark,
  );
  _context(received: false);
  expect(filter.text, 'Unicode 例');
  switch (cat) {
    case DesignStateCategory.successfulEmpty:
      expect(find.text('Записей по выбранному фильтру нет.'), findsOneWidget);
      _status('Данные получены · записей: 0', DeckTone.available);
    case DesignStateCategory.data:
      expect(
        find.text(DesignServerFixtures.record()['message']! as String),
        findsOneWidget,
      );
      _status('Данные получены · записей: 1', DeckTone.available);
    case DesignStateCategory.denied:
      _status('Недостаточно прав', DeckTone.warning);
      expect(
        find.text('Подтверждённые записи журнала не получены.'),
        findsOneWidget,
      );
    case DesignStateCategory.unsupported:
      _status('Не поддерживается', DeckTone.warning);
      expect(
        find.text('Подтверждённые записи журнала не получены.'),
        findsOneWidget,
      );
    case DesignStateCategory.stale:
      _status('Данные устарели', DeckTone.warning);
    case DesignStateCategory.dropped:
      expect(find.text('Пропущено: 3'), findsOneWidget);
      expect(
        find.text('Журнал неполный: часть записей пропущена или ограничена.'),
        findsOneWidget,
      );
      _status('Неполные данные', DeckTone.warning);
    case DesignStateCategory.incomplete:
      expect(find.text('Ошибок разбора: 2'), findsOneWidget);
      expect(
        find.text('Журнал неполный: часть записей пропущена или ограничена.'),
        findsOneWidget,
      );
      expect(find.text('Записей по выбранному фильтру нет.'), findsNothing);
      _status('Неполные данные', DeckTone.warning);
    case DesignStateCategory.sshUnavailable:
      _status('Подключение не установлено', DeckTone.unavailable);
    default:
      throw StateError('Unhandled logs category $cat');
  }
  expect(counts.total, 0);
  await _capture(tester, scenario, frame, dark, counts, [
    'Actual typed journald ${cat.name}, supplied UTC/source and filter retained',
    'No automatic refresh/recovery/connect; partial is not successful empty',
  ]);
  if (cat == DesignStateCategory.data) {
    await _click(tester, 'Предыдущие записи');
    expect(counts.value('previous'), 1);
    expect(counts.value('load'), 0);
    await _mount(
      tester,
      _logsSection(
        counts,
        DesignServerFixtures.logs(quality: 'unknown', records: []),
        filter,
      ),
      frame,
      dark,
    );
    _status('Данных пока нет', DeckTone.unknown);
    expect(find.text('Записей по выбранному фильтру нет.'), findsNothing);
    expect(find.textContaining('Получено:'), findsNothing);
  }
  if (cat == DesignStateCategory.denied ||
      cat == DesignStateCategory.unsupported)
    await _ownerError(tester, scenario, frame, dark, counts, capture: false);
  if (cat == DesignStateCategory.incomplete ||
      cat == DesignStateCategory.successfulEmpty) {
    for (final partial in [
      DesignServerFixtures.logs(gaps: true, records: []),
      DesignServerFixtures.logs(truncated: true, records: []),
      DesignServerFixtures.logs(dropped: 1, records: []),
      DesignServerFixtures.logs(parseErrors: 1, records: []),
      DesignServerFixtures.logs(quality: 'stale', records: []),
      DesignServerFixtures.logs(quality: 'incomplete', records: []),
    ]) {
      await _mount(tester, _logsSection(counts, partial, filter), frame, dark);
      expect(find.text('Записей по выбранному фильтру нет.'), findsNothing);
      expect(
        find.text('Подтверждённые записи журнала не получены.'),
        findsOneWidget,
      );
    }
    await _mount(tester, _logsSection(counts, null, filter), frame, dark);
    expect(find.text('Записей по выбранному фильтру нет.'), findsNothing);
  }
  if (cat == DesignStateCategory.dropped) {
    await _mount(
      tester,
      _logsSection(
        counts,
        DesignServerFixtures.logs(nextCursor: 'page-only', duplicates: 2),
        filter,
      ),
      frame,
      dark,
    );
    expect(find.text('Дубликатов: 2'), findsOneWidget);
    expect(
      find.text('Журнал неполный: часть записей пропущена или ограничена.'),
      findsNothing,
    );
    _status('Данные получены', DeckTone.available);
  }
}

Future<void> _record(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
  _Counts counts,
) async {
  final filter = TextEditingController();
  addTearDown(filter.dispose);
  final message = List.filled(
    12,
    'Полная Unicode запись 例 · точный текст без нового чтения.',
  ).join('\n');
  final logs = DesignServerFixtures.logs(
    records: [
      DesignServerFixtures.record(
        timestamp: '2026-10-24T07:08:09.000Z',
        message: message,
      ),
    ],
  );
  final profile = DesignServerFixtures.profile(address: '2001:db8::44');
  final selected = (logs['records'] as List).single as Map<String, Object?>;
  final recordContext = ServerLogRecordContext.capture(profile, logs);
  await _mount(
    tester,
    Builder(
      builder: (context) => _logsSection(
        counts,
        logs,
        filter,
        open: (row) {
          counts.hit('open');
          expect(row, same(selected));
          showMotionDialog<void>(
            context: context,
            builder: (context) => ServerLogRecordDialog(
              recordContext: recordContext,
              record: row,
              onClose: () {
                counts.hit('close');
                Navigator.pop(context);
              },
            ),
          );
        },
      ),
    ),
    frame,
    dark,
  );
  final tile = find.byType(ListTile);
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
  expect(find.byType(ServerLogRecordDialog), findsOneWidget);
  expect(find.text('Запись журнала'), findsOneWidget);
  final semantics = tester.ensureSemantics();
  final contextText = [
    profile.name,
    '[2001:db8::44]:2222',
    'Источник: ${logs['source']}',
    'Время записи: ${selected['timestamp']} UTC',
    'Наблюдение: ${logs['observedAt']} UTC',
  ];
  for (final text in contextText) {
    final label = find.descendant(
      of: find.byType(ServerLogRecordDialog),
      matching: find.text(text),
    );
    expect(label, findsOneWidget);
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(text), findsOneWidget);
  }
  semantics.dispose();
  expect(
    find.byWidgetPredicate(
      (widget) => widget is SelectableText && widget.data == message,
    ),
    findsOneWidget,
  );
  expect(counts.value('open'), 1);
  expect(counts.value('load'), 0);
  await _capture(tester, scenario, frame, dark, counts, [
    'Actual logs-selected record identity, matching target/source, exact full selectable text and distinct labelled record/observation UTC in modal semantics',
    'Open1, no record reread; close tested separately once',
  ]);
  await _click(tester, 'Закрыть');
  expect(counts.value('close'), 1);
  expect(counts.value('load'), 0);
}

Future<void> _recordIdentity(
  WidgetTester tester,
  _Frame frame,
  bool dark,
) async {
  final filter = TextEditingController();
  final counts = _Counts();
  final profileA = DesignServerFixtures.profile(address: '2001:db8::44');
  final profileB = DesignServerFixtures.profile(
    address: '2001:db8::55',
    connectionRevision: '2',
  );
  final logsA = DesignServerFixtures.logs(
    records: [
      DesignServerFixtures.record(
        timestamp: '2026-10-24T07:08:09.000Z',
        message:
            'T102 exact record A · 例\n${List.filled(32, 'Raw selected record A, unchanged.').join('\n')}\nT102-END-RECORD-A-Я',
      ),
    ],
  );
  final inputs = ValueNotifier<(ProfileView, Map<String, Object?>)>((
    profileA,
    logsA,
  ));
  final representative =
      frame.size.width == 1100 && frame.scale == 1 ||
      frame.size.width == 360 && frame.scale == 2;
  Future<ServerLogRecordDialog> open() async {
    final tile = find.byType(ListTile);
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    return tester.widget<ServerLogRecordDialog>(
      find.byType(ServerLogRecordDialog),
    );
  }

  Future<void> assertContext(
    ServerLogRecordDialog dialog,
    Map<String, Object?> logs,
    ProfileView? profile,
  ) async {
    final row = (logs['records'] as List).single as Map<String, Object?>;
    expect(dialog.record, same(row));
    expect(dialog.recordContext.profile, same(profile));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == row['message'],
      ),
      findsOneWidget,
    );
    final labels = [
      if (profile == null) ...[
        logs['serverId'] == null
            ? 'Цель записи не указана'
            : 'Цель записи: ${logs['serverId']}',
        'Параметры цели записи не подтверждены текущими сведениями',
        'Закройте окно и получите журнал для текущих параметров.',
      ] else ...[
        profile.name,
        '[${profile.address}]:${profile.port}',
      ],
      'Источник: ${logs['source']}',
      'Время записи: ${row['timestamp']} UTC',
      'Наблюдение: ${logs['observedAt']} UTC',
    ];
    final semantics = tester.ensureSemantics();
    try {
      for (final label in labels) {
        final text = find.descendant(
          of: find.byType(ServerLogRecordDialog),
          matching: find.text(label),
        );
        expect(text, findsOneWidget);
        await tester.ensureVisible(text);
        await tester.pumpAndSettle();
        expectDesignVisible(tester, text);
        expect(tester.widget<Text>(text).maxLines, isNull);
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(label))),
          findsWidgets,
        );
      }
    } finally {
      semantics.dispose();
    }
  }

  Future<void> checkpoint(
    String phase, {
    Future<void> Function()? reveal,
  }) async {
    await _passive(tester, frame, dark, counts);
    if (reveal != null) await reveal();
    await captureDesignState(
      tester,
      family: 'server',
      caseIds: const ['state-23-log-record-data'],
      phase: phase,
      theme: dark ? 'dark' : 'light',
      scale: frame.scale,
      counters: {
        ...counts.snapshot,
        'additionalUiInitiatedOwnerActions': counts.passiveDelta,
        'recordReadRequests': counts.value('load'),
      },
      assertions: const [
        'Actual production capture factory and modal before-open identity mismatch or explicit new matching result',
        'Exact source, distinct record/observation UTC and selected message; wrapping modal semantics after outer reveal',
        'No read/retry/recreation callback; old open projection retained across parent result/theme/resize',
      ],
      scope: 'productionPresentation',
      limitations: const [
        'Authorized synthetic read projections; no genuine TrustedApiClient, RPC, SSH or native authority.',
        'Supplemental journey of existing origin23 data; no new applicability case or product state.',
      ],
    );
  }

  try {
    await _mount(
      tester,
      ValueListenableBuilder<(ProfileView, Map<String, Object?>)>(
        valueListenable: inputs,
        builder: (context, input, _) {
          final (profile, logs) = input;
          final projection = ServerLogRecordContext.capture(profile, logs);
          return _logsSection(
            counts,
            logs,
            filter,
            open: (row) {
              counts.hit('open');
              showMotionDialog<void>(
                context: context,
                barrierDismissible: true,
                builder: (context) => ServerLogRecordDialog(
                  recordContext: projection,
                  record: row,
                  onClose: () {
                    counts.hit('close');
                    Navigator.pop(context);
                  },
                ),
              );
            },
          );
        },
      ),
      frame,
      dark,
    );
    inputs.value = (profileB, logsA);
    await tester.pumpAndSettle();
    final oldDialog = await open();
    await assertContext(oldDialog, logsA, null);
    expect(
      find.descendant(
        of: find.byType(ServerLogRecordDialog),
        matching: find.text('[2001:db8::55]:2222'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(ServerLogRecordDialog),
        matching: find.text('[2001:db8::44]:2222'),
      ),
      findsNothing,
    );
    await checkpoint('t102-server-23-target-unresolved');
    if (representative) {
      await checkpoint(
        't102-server-23-unresolved-message-end',
        reveal: () async {
          final message =
              ((logsA['records'] as List).single
                      as Map<String, Object?>)['message']
                  as String;
          final editor = find.byWidgetPredicate(
            (widget) =>
                widget is EditableText && widget.controller.text == message,
          );
          final raw = find
              .ancestor(
                of: editor,
                matching: find.byType(SingleChildScrollView),
              )
              .first;
          await tester.ensureVisible(raw);
          await tester.pumpAndSettle();
          final position = tester
              .state<ScrollableState>(
                find
                    .descendant(of: raw, matching: find.byType(Scrollable))
                    .first,
              )
              .position;
          expect(position.maxScrollExtent, greaterThan(0));
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          final close = find.widgetWithText(TextButton, 'Закрыть');
          await tester.ensureVisible(close);
          await tester.pumpAndSettle();
          expect(close.hitTestable(), findsOneWidget);
          expect(tester.getSize(close).shortestSide, greaterThanOrEqualTo(44));
          expect(position.pixels, closeTo(position.maxScrollExtent, .01));
          final render = tester.state<EditableTextState>(editor).renderEditable;
          final last = render
              .getBoxesForSelection(
                TextSelection(
                  baseOffset: message.length - 1,
                  extentOffset: message.length,
                ),
              )
              .single
              .toRect()
              .shift(render.localToGlobal(Offset.zero));
          final viewport = tester.getRect(raw);
          expect(last.top, greaterThanOrEqualTo(viewport.top - .5));
          expect(last.bottom, lessThanOrEqualTo(viewport.bottom + .5));
          expect(last.top, greaterThanOrEqualTo(0));
          expect(last.bottom, lessThanOrEqualTo(frame.size.height));
          expect(counts.value('close'), 0);
        },
      );
    }
    final logsB = <String, Object?>{
      ...logsA,
      'identity': {
        ...(logsA['identity'] as Map<String, Object?>),
        'connectionRevision': profileB.connectionRevision,
      },
      'source': 'journal-B',
      'observedAt': '2026-10-26T09:00:00.000Z',
      'records': [
        DesignServerFixtures.record(
          timestamp: '2026-10-26T08:00:00.000Z',
          message: 'T102 exact record B · 例',
        ),
      ],
    };
    inputs.value = (profileB, logsB);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ServerLogRecordDialog>(find.byType(ServerLogRecordDialog))
          .recordContext,
      same(oldDialog.recordContext),
    );
    await assertContext(oldDialog, logsA, null);
    await _click(tester, 'Закрыть');
    if (representative) {
      final unspecified = <String, Object?>{
        ...logsA,
        'serverId': null,
        'identity': null,
      };
      inputs.value = (profileB, unspecified);
      await tester.pumpAndSettle();
      await assertContext(await open(), unspecified, null);
      await checkpoint('t102-server-23-target-unspecified');
      await _click(tester, 'Закрыть');
    }
    inputs.value = (profileB, logsB);
    await tester.pumpAndSettle();
    await assertContext(await open(), logsB, profileB);
    if (representative) await checkpoint('t102-server-23-new-matching-result');
    await _click(tester, 'Закрыть');
    expect(counts.value('open'), representative ? 3 : 2);
    expect(counts.value('close'), counts.value('open'));
    expect(counts.value('load'), 0);
    expect(counts.value('previous'), 0);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    inputs.dispose();
    filter.dispose();
  }
}

class _ReviewState extends ChangeNotifier {
  ProfileView? profile = DesignServerFixtures.profile(
    address: '2001:db8::44',
    port: 22,
  );
  HostTrustChallenge? challenge = DesignServerFixtures.challenge();
  Map<String, Object?>? inspection = DesignServerFixtures.executorInspection();
  void changed() => notifyListeners();
}

Future<void> _review(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
  _Counts counts,
) async {
  final cat = scenario.category;
  final executor = scenario.originId == '40-executor-binding';
  if (cat == DesignStateCategory.loading) {
    await _pending(
      tester,
      scenario,
      frame,
      dark,
      counts,
      Column(
        children: [
          _connection(counts, busy: true),
          if (executor)
            ServerExecutorSection(
              executor: DesignServerFixtures.executor(),
              hasInspection: true,
              busy: true,
              onRefreshState: () => counts.hit('read'),
              onInspect: () => counts.hit('inspect'),
              onConfirm: () => counts.hit('confirm'),
              onRevoke: () => counts.hit('revoke'),
            ),
        ],
      ),
    );
    return;
  }
  if (cat == DesignStateCategory.denied ||
      cat == DesignStateCategory.unsupported ||
      cat == DesignStateCategory.unknown) {
    await _ownerError(tester, scenario, frame, dark, counts);
    if (cat == DesignStateCategory.denied)
      await _ownerError(
        tester,
        scenario,
        frame,
        dark,
        counts,
        code: 'UNAUTHORIZED',
        capture: false,
      );
    return;
  }
  if (cat == DesignStateCategory.sshUnavailable) {
    await _mount(tester, _connection(counts, offline: true), frame, dark);
    _status('Подключение не установлено', DeckTone.unavailable);
    expect(counts.total, 0);
    await _capture(tester, scenario, frame, dark, counts, [
      'Actual disconnected connection cross, not locald failure',
      'Automatic connect/consent0',
    ]);
    return;
  }
  final state = _ReviewState();
  addTearDown(state.dispose);
  final capturedProfile = state.profile!;
  final capturedChallenge = state.challenge!;
  final capturedInspection = state.inspection!;
  Widget review({ProfileView? profile}) => executor
      ? ServerExecutorConfirmation(
          inspection: capturedInspection,
          profile: profile ?? capturedProfile,
          changes: state,
          currentProfile: () => state.profile,
          currentInspection: () => state.inspection,
          onCancel: () => counts.hit('cancel'),
          onConfirm: () => counts.hit('confirm'),
        )
      : ServerTrustConfirmation(
          challenge: capturedChallenge,
          profile: profile ?? capturedProfile,
          changes: state,
          currentProfile: () => state.profile,
          currentChallenge: () => state.challenge,
          onCancel: () => counts.hit('cancel'),
          onConfirm: () => counts.hit('confirm'),
        );
  await _mount(tester, review(), frame, dark);
  final confirm = executor ? 'Привязать' : 'Подтвердить';
  if (cat == DesignStateCategory.validation) {
    state.profile = DesignServerFixtures.profile(address: '192.0.2.99');
    state.changed();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_button(confirm)).onPressed, isNull);
    expect(
      find.textContaining(
        executor
            ? 'Профиль или проверка исполнителя изменились.'
            : 'Профиль или SSH-ключ изменился.',
      ),
      findsOneWidget,
    );
    state.profile = capturedProfile;
    state.changed();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_button(confirm)).onPressed, isNull);
    expect(counts.value('confirm'), 0);
    if (!executor) expect(find.text('[2001:db8::44]:22'), findsOneWidget);
    await _capture(tester, scenario, frame, dark, counts, [
      'Actual review context change then restore permanently retires consent',
      'Frozen valid original trust target is not silently retargeted; no invalid confirm',
    ]);
    await _click(tester, 'Отмена');
    expect(counts.value('cancel'), 1);
    expect(counts.value('confirm'), 0);
    for (final mismatch in [
      DesignServerFixtures.profile(id: '00000000-0000-4000-8000-000000000099'),
      if (!executor) DesignServerFixtures.profile(revision: '3'),
      DesignServerFixtures.profile(connectionRevision: '3'),
      DesignServerFixtures.profile(credentialRevision: '3'),
      DesignServerFixtures.profile(trustRevision: '3'),
    ]) {
      state.profile = mismatch;
      await _mount(tester, review(profile: mismatch), frame, dark);
      expect(tester.widget<FilledButton>(_button(confirm)).onPressed, isNull);
      expect(find.text(mismatch.name), findsNothing);
      expect(find.text('192.0.2.44:2222'), findsNothing);
      expect(counts.value('confirm'), 0);
    }
    state.profile = capturedProfile;
    await _mount(tester, review(), frame, dark);
    if (executor) {
      state.inspection = DesignServerFixtures.executorInspection();
    } else {
      state.challenge = DesignServerFixtures.challenge();
    }
    state.changed();
    await tester.pumpAndSettle();
    state.inspection = capturedInspection;
    state.challenge = capturedChallenge;
    state.changed();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_button(confirm)).onPressed, isNull);
    await _mount(tester, review(), frame, dark);
    state.profile = DesignServerFixtures.profile(address: '192.0.2.99');
    await _click(tester, confirm); // Handler rechecks before any notification.
    expect(counts.value('confirm'), 0);
    expect(tester.widget<FilledButton>(_button(confirm)).onPressed, isNull);
  } else {
    expect(find.text('[2001:db8::44]:22'), findsOneWidget);
    expect(find.text(capturedProfile.name), findsOneWidget);
    expect(find.text(DesignServerFixtures.key.fingerprint), findsOneWidget);
    expect(find.textContaining('UTC'), findsOneWidget);
    expect(tester.widget<FilledButton>(_button(confirm)).onPressed, isNotNull);
    expect(counts.total, 0);
    await _capture(tester, scenario, frame, dark, counts, [
      'Actual typed review target/IPv6/fingerprint/expiry before consent',
      'Passive callbacks0, exact valid explicit confirm tested separately',
    ]);
    await _click(tester, confirm);
    expect(counts.value('confirm'), 1);
    expect(counts.value('cancel'), 0);
    await _mount(tester, review(), frame, dark);
    await _click(tester, 'Отмена');
    expect(counts.value('cancel'), 1);
    expect(counts.value('confirm'), 1);
  }
}
