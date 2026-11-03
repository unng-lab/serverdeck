/// Owned by the GUI runtime; registered before startup completes.
/// Each cleanup operation must tolerate a retry after a failed attempt.
abstract interface class RuntimeCapability {
  String get id;
  Future<void> stopAdmission();
  Future<void> cancelPending();
  Future<void> closeSessions();
  Future<void> drain();
  Future<void> dispose();
}

abstract interface class RuntimeStore {
  String get theme;
  Future<void> open();
  void stopAdmission();
  Future<void> finishWrites();
  Future<void> close();
}
