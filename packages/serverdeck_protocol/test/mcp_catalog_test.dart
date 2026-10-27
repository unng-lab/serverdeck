import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:test/test.dart';

void main() {
  test(
    'complete public catalog has no SSH, shell, trust or owner management tool',
    () {
      expect(mcpTools.length, 24);
      expect(mcpTools.map((t) => t.name).toSet().length, 24);
      for (final forbidden in [
        'ssh',
        'shell',
        'exec',
        'grants_create',
        'approve',
        'trust_accept',
      ]) {
        expect(mcpTool('serverdeck_$forbidden'), isNull);
      }
      expect(mcpTool('serverdeck_profiles_create')!.requiredScopes, {
        McpScope.author,
      });
      expect(mcpTool('serverdeck_apply')!.requiredScopes, {
        McpScope.plan,
        McpScope.apply,
      });
      expect(mcpTool('serverdeck_logs_read')!.requiredScopes, {McpScope.logs});
    },
  );

  test('author-only discovery has no implicit server capability', () {
    final policy = GrantScopePolicy.fromJson({
      'scopes': ['author'],
      'serverIds': <String>[],
    });
    final names = mcpToolsFor(policy).map((t) => t.name).toSet();
    expect(
      names,
      containsAll([
        'serverdeck_profiles_create',
        'serverdeck_profiles_update',
        'serverdeck_profiles_validate',
      ]),
    );
    expect(names, isNot(contains('serverdeck_servers_list')));
    expect(names, isNot(contains('serverdeck_apply')));
    expect(
      mcpToolsFor(
        GrantScopePolicy.fromJson({
          'scopes': <String>[],
          'serverIds': <String>[],
        }),
      ),
      isEmpty,
    );
  });

  test(
    'input shapes close unknown fields and expose distinct list/log limits',
    () {
      for (final tool in mcpTools) {
        final schema = tool.inputSchema;
        expect(schema['type'], 'object');
        expect(schema['additionalProperties'], isFalse);
        final required = schema['required'] as List;
        final properties = schema['properties'] as Map;
        expect(properties.keys.toSet().containsAll(required), isTrue);
      }
      Map limit(String name) =>
          (mcpTool(name)!.inputSchema['properties'] as Map)['limit'] as Map;
      expect(limit('serverdeck_servers_list')['default'], 50);
      expect(limit('serverdeck_servers_list')['maximum'], 100);
      expect(limit('serverdeck_logs_read')['default'], 100);
      expect(limit('serverdeck_logs_read')['maximum'], 1000);
      expect(limit('serverdeck_jobs_events')['maximum'], 100);
    },
  );

  test(
    'catalog snapshots cannot broaden input schemas or scope requirements',
    () {
      final apply = mcpTool('serverdeck_apply')!;
      final first = apply.toJson();
      (first['inputSchema'] as Map)['additionalProperties'] = true;
      (first['inputSchema'] as Map)['required'] = <String>[];
      expect(apply.inputSchema['additionalProperties'], isFalse);
      expect(apply.inputSchema['required'], contains('requestId'));
      expect(
        () => apply.requiredScopes.add(McpScope.author),
        throwsUnsupportedError,
      );
      expect(() => mcpTools.clear(), throwsUnsupportedError);
    },
  );

  test(
    'profile authoring schema exposes only the supported declarative AST',
    () {
      final schema = mcpTool('serverdeck_profiles_create')!.inputSchema;
      Object? expand(Object? value) {
        if (value is Map) {
          if (value[r'$ref'] case final String ref) {
            return expand((schema[r'$defs'] as Map)[ref.split('/').last]);
          }
          return value.map((key, value) => MapEntry(key, expand(value)));
        }
        if (value is List) return value.map(expand).toList();
        return value;
      }

      final body = (expand(schema['properties']) as Map)['body'] as Map;
      expect(body['additionalProperties'], isFalse);
      expect((body['properties'] as Map)['format'], {'const': 1});
      final steps =
          ((body['properties'] as Map)['steps'] as Map)['items'] as Map;
      final variants = steps['oneOf'] as List;
      expect(
        variants.map((v) => ((v as Map)['properties'] as Map)['kind']).toList(),
        [
          {'const': 'service'},
          {'const': 'config_file'},
          {'const': 'install_recipe'},
        ],
      );
    },
  );
}
