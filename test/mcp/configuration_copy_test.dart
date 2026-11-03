import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/mcp/configuration_view.dart';
import 'package:serverdeck/mcp/grant_owner.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

void main() {
  for (final failed in [false, true]) {
    testWidgets(
      'public MCP configuration C18 copy ${failed ? 'failure' : 'success'}',
      (tester) async {
        const configuration = McpConfiguration(
          r'C:\fixture\ServerDeck.exe',
          '00000001-0000-4000-8000-000000000000',
        );
        String? copied;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                if (failed)
                  throw PlatformException(
                    code: 'UNAVAILABLE',
                    message: 'synthetic-sensitive-detail',
                  );
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.dark,
            home: const Scaffold(
              body: McpConfigurationView(configuration: configuration),
            ),
          ),
        );
        final value = const JsonEncoder.withIndent('  ')
            .convert(configuration.toJson());
        expect(
          tester.widget<DeckCopyButton>(find.byType(DeckCopyButton)).value,
          value,
        );
        expect(
          tester.widget<DeckKeyValue>(find.byType(DeckKeyValue)).selectable,
          isTrue,
        );
        await tester.tap(find.text('Копировать конфигурацию'));
        await tester.pumpAndSettle();
        if (failed) {
          expect(copied, isNull);
          expect(find.text('Не удалось скопировать'), findsOneWidget);
        } else {
          expect(copied, value);
          expect(jsonDecode(copied!), configuration.toJson());
          expect(find.text('Скопировано'), findsOneWidget);
        }
        expect(find.textContaining('synthetic-sensitive-detail'), findsNothing);
        expect((configuration.toJson()['mcpServers'] as Map)['serverdeck'], {
          'command': configuration.command,
          'args': ['--mcp-stdio', '--client', configuration.clientId],
        });
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
