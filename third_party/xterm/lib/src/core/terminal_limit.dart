class TerminalLimitException implements Exception {
  const TerminalLimitException();
  @override
  String toString() => 'Terminal output limit';
}
