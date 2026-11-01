/// A false result or exception cannot establish that native ownership ended.
Future<bool> confirmNativeClose(Future<bool> Function() close) async {
  try {
    return await close();
  } catch (_) {
    return false;
  }
}
