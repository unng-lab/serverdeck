import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/shell/readiness_view.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck_protocol/models.dart' show ErrorCode, ReadinessState;

Widget app(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light
          ? BrandTheme.light
          : BrandTheme.dark,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets(
    'unavailable is a local service failure, not a remote health claim',
    (tester) async {
      await tester.pumpWidget(
        app(const ReadinessView(state: ReadinessState.unavailable)),
      );
      expect(find.text('Локальная служба недоступна'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    },
  );

  testWidgets('all non-ready states stay distinct and ready is rejected', (
    tester,
  ) async {
    final titles = {
      ReadinessState.starting: 'Запуск локальной службы',
      ReadinessState.recovering: 'Восстановление локального пространства',
      ReadinessState.storageBlocked: 'Локальное хранилище заблокировано',
      ReadinessState.incompatible: 'Несовместимая версия локальной службы',
      ReadinessState.stopping: 'Завершение работы локальной службы',
      ReadinessState.unavailable: 'Локальная служба недоступна',
    };
    for (final entry in titles.entries) {
      await tester.pumpWidget(
        app(ReadinessView(state: entry.key, onRetry: () {})),
      );
      expect(find.text(entry.value), findsOneWidget);
      final status = tester.widget<DeckStatus>(find.byType(DeckStatus));
      expect(status.tone, switch (entry.key) {
        ReadinessState.storageBlocked => DeckTone.error,
        ReadinessState.incompatible => DeckTone.warning,
        ReadinessState.unavailable => DeckTone.unavailable,
        _ => DeckTone.running,
      });
      expect(
        find.byType(FilledButton),
        {
              ReadinessState.starting,
              ReadinessState.recovering,
              ReadinessState.stopping,
            }.contains(entry.key)
            ? findsNothing
            : findsOneWidget,
      );
    }
    await tester.pumpWidget(
      app(const ReadinessView(state: ReadinessState.ready)),
    );
    expect(tester.takeException(), isA<StateError>());
  });

  testWidgets('safe typed reasons are localized, never raw protocol codes', (
    tester,
  ) async {
    for (final reason in ErrorCode.values) {
      await tester.pumpWidget(
        app(ReadinessView(state: ReadinessState.unavailable, reason: reason)),
      );
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data!)
          .toList();
      expect(texts.length, greaterThanOrEqualTo(3));
      expect(texts.last, isNotEmpty);
      expect(texts.any((text) => text.contains(reason.wireName)), isFalse);
      expect(texts.any((text) => text.contains('Сервер выключен')), isFalse);
    }
    await tester.pumpWidget(
      app(
        const ReadinessView(
          state: ReadinessState.unavailable,
          reason: ErrorCode.timeout,
        ),
      ),
    );
    expect(
      find.text('Время ожидания ответа локальной службы истекло.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'retry is explicit, pending disables it, keyboard activates with visible focus',
    (tester) async {
      var retries = 0;
      void retry() {
        retries++;
      }

      await tester.pumpWidget(
        app(ReadinessView(state: ReadinessState.unavailable, onRetry: retry)),
      );
      await tester.pump(const Duration(seconds: 40));
      expect(retries, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final context = tester.element(find.text('Повторить запуск'));
      expect(Focus.of(context).hasFocus, isTrue);
      // The shared brand button painter supplies the visible focus ring.
      expect(FilledButtonTheme.of(context).style!.backgroundBuilder, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(retries, 1);
      await tester.pumpWidget(
        app(
          ReadinessView(
            state: ReadinessState.unavailable,
            onRetry: retry,
            retryInProgress: true,
          ),
        ),
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('Ожидаем результат текущей попытки.'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(seconds: 40));
      expect(retries, 1);
      await tester.pumpWidget(
        app(
          const ReadinessView(
            state: ReadinessState.unavailable,
            retryInProgress: true,
          ),
        ),
      );
      expect(find.byType(FilledButton), findsNothing);
    },
  );

  testWidgets(
    'both themes and four 200-percent viewports keep status and retry reachable',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final brightness in Brightness.values) {
        for (final size in [
          const Size(1100, 760),
          const Size(800, 600),
          const Size(360, 800),
          const Size(390, 800),
        ]) {
          await tester.binding.setSurfaceSize(size);
          for (final state in ReadinessState.values.where(
            (state) => state != ReadinessState.ready,
          )) {
            var retries = 0;
            await tester.pumpWidget(
              app(
                MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: const TextScaler.linear(2),
                  ),
                  child: ReadinessView(
                    state: state,
                    reason: ErrorCode.storageBlocked,
                    onRetry: () {
                      retries++;
                    },
                  ),
                ),
                brightness: brightness,
              ),
            );
            await tester.pump();
            expect(
              tester.takeException(),
              isNull,
              reason: '$brightness/$size/$state',
            );
            final title = find.byWidgetPredicate(
              (widget) => widget is Text && widget.style?.fontSize == 24,
            );
            await tester.ensureVisible(title);
            expect(title.hitTestable(), findsOneWidget);
            if (find.byType(FilledButton).evaluate().isNotEmpty) {
              await tester.ensureVisible(find.byType(FilledButton));
              final rect = tester.getRect(find.byType(FilledButton));
              expect(rect.width, greaterThanOrEqualTo(48));
              expect(rect.height, greaterThanOrEqualTo(48));
              await tester.tap(find.byType(FilledButton));
              expect(retries, 1);
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );
}
