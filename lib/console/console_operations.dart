import '../domain/models.dart';
import 'console_models.dart';

abstract interface class ConsoleOperations {
  Future<OperationResult<ConsoleValue>> consoleProfiles(ConsoleCaller caller);
  Future<OperationResult<ConsoleValue>> listConsoles(
    ConsoleCaller caller,
    String profileId,
  );
  Future<OperationResult<ConsoleValue>> openConsole(
    ConsoleCaller caller,
    String profileId, {
    String? shellProfileId,
    String? ownerEpoch,
    int? operationSequence,
  });
  Future<OperationResult<ConsoleValue>> readConsole(
    ConsoleCaller caller,
    String profileId,
    String sessionId, {
    required int generation,
    String? cursor,
    int limit = 1000,
  });
  Future<OperationResult<ConsoleValue>> acquireConsole(
    ConsoleCaller caller,
    String profileId,
    String sessionId, {
    required int generation,
    String? ownerEpoch,
    int? operationSequence,
  });
  Future<OperationResult<ConsoleValue>> releaseConsole(
    ConsoleCaller caller,
    String profileId,
    String sessionId, {
    required int generation,
    required String leaseToken,
    String? ownerEpoch,
    int? operationSequence,
  });
  Future<OperationResult<ConsoleValue>> writeConsole(
    ConsoleCaller caller,
    String profileId,
    String sessionId, {
    required int generation,
    String? leaseToken,
    String? text,
    String? key,
    bool confirmedMultiline = false,
    String? ownerEpoch,
    int? operationSequence,
  });
  Future<OperationResult<ConsoleValue>> closeConsole(
    ConsoleCaller caller,
    String profileId,
    String sessionId, {
    required int generation,
    bool confirmed = false,
    String? leaseToken,
    String? ownerEpoch,
    int? operationSequence,
  });
  void disconnectBinding(ConsoleMcpBinding binding);
  void invalidateClient(String clientId);
}
