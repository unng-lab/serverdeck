import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/software/software_analysis.dart';

void main() {
  const profile = ProfileView(
    profileId: '00000001-0000-4000-8000-000000000000',
    revision: 1,
    connectionRevision: 1,
    displayName: 'Synthetic',
    host: 'server.invalid',
    port: 2222,
    username: 'admin',
    authKind: AuthKind.password,
    hasCredential: true,
    endpointId: 'public-endpoint',
  );
  test(
    'analysis prompt contains public target and requested products only',
    () {
      final text = softwareAnalysisPrompt(profile, 'PostgreSQL, Redis');
      expect(text, contains(profile.profileId));
      expect(text, contains('server.invalid:2222'));
      expect(text, contains('PostgreSQL, Redis'));
      expect(text, contains('software.save'));
      expect(text, contains('console.'));
      expect(text, contains('согласования'));
      expect(text, isNot(contains('password')));
      expect(text, isNot(contains('hasCredential')));
    },
  );
  test('empty request leaves discovery choices to external AI', () {
    expect(softwareAnalysisPrompt(profile, ''), contains('установленное ПО'));
  });
}
