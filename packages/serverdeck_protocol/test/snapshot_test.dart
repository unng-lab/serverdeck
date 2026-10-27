import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_protocol/wire.dart';
import 'package:test/test.dart';

const id = '12345678-1234-4234-8234-123456789abc';
const queryId = '12345678-1234-4234-8234-123456789abd';

void main() {
  test('snapshot/status/receipt DTOs conform to the complete wire schemas', () {
    validateMethodResult(
      'profiles.list',
      const ProfilesSnapshot('0', []).toJson(),
    );
    validateMethodResult(
      'settings.get',
      const SettingsSnapshot('0', SettingsView()).toJson(),
    );
    const mutation = MutationResult(
      entityId: null,
      entityRevision: '2',
      storeRevision: '1',
      deleted: false,
    );
    for (final result in [
      const MutationStatusResult.queued(),
      const MutationStatusResult.running(),
      const MutationStatusResult.notFound(),
      const MutationStatusResult.committed(mutation),
    ]) {
      validateMethodResult('mutations.get', result.toJson());
    }
    validateMethodResult(
      'mutations.recent',
      const RecentMutationsView([
        MutationReceiptView(
          requestId: id,
          operation: 'settings.update',
          profileId: null,
          result: mutation,
          committedAt: '2026-10-11T00:00:00.000Z',
        ),
      ], truncated: false).toJson(),
    );
  });
  test(
    'status read has its own query correlation and original mutation in params',
    () {
      final request = ApiRequest.mutationStatus(
        queryId: queryId,
        sessionId: 'A' * 43,
        mutationRequestId: id,
      );
      validateRequestEnvelope(request.toJson());
      validateMethodShape(request.method, request.params);
      expect(request.id, queryId);
      expect(request.params['requestId'], id);
      expect(
        () => ApiRequest.mutationStatus(
          queryId: id,
          sessionId: 'A' * 43,
          mutationRequestId: id,
        ),
        throwsArgumentError,
      );
    },
  );
}
