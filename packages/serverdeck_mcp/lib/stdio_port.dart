/// Owned byte carrier for the same executable's MCP mode. This port has no
/// application/domain authority and never starts the desktop application.
abstract interface class McpStdioPort {
  Future<void> get ready;
  Stream<List<int>> get input;

  /// Completes only after the actual write, never after merely queueing bytes.
  Future<void> write(List<int> bytes);

  /// Best-effort fixed code on the separate inherited diagnostic handle.
  void diagnostic(String code);
  Future<void> flushDiagnostics();

  /// Acknowledges physical carrier shutdown, including outstanding I/O.
  /// Failure is sticky; the owned connector process must exit on uncertainty.
  Future<void> close();
}
