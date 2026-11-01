import 'package:serverdeck_protocol/validation.dart';

enum ServerDeckMode { application, mcpStdio }

/// Null keeps the application event loop alive; an integer exits only the owned
/// invocation. Parsing precedes either side effect and never echoes argv.
Future<int?> dispatchServerDeck(
  List<String> arguments, {
  required void Function() application,
  required Future<int> Function(String? grantId) stdio,
}) async {
  final ServerDeckLaunch launch;
  try {
    launch = ServerDeckLaunch.parse(arguments);
  } on FormatException {
    return 64;
  }
  if (launch.mode == ServerDeckMode.application) {
    application();
    return null;
  }
  return stdio(launch.grantId);
}

/// One executable, with no legacy command-line or caller-selected app root.
final class ServerDeckLaunch {
  const ServerDeckLaunch._(this.mode, this.grantId);
  factory ServerDeckLaunch.parse(List<String> arguments) {
    if (arguments.isEmpty) {
      return const ServerDeckLaunch._(ServerDeckMode.application, null);
    }
    if (arguments.first != '--mcp-stdio' ||
        arguments.length != 1 && arguments.length != 3) {
      throw const FormatException('ARGUMENTS');
    }
    if (arguments.length == 1) {
      return const ServerDeckLaunch._(ServerDeckMode.mcpStdio, null);
    }
    if (arguments[1] != '--grant-id') {
      throw const FormatException('ARGUMENTS');
    }
    try {
      final grantId = requireUuid(arguments[2]);
      return ServerDeckLaunch._(ServerDeckMode.mcpStdio, grantId);
    } on FormatException {
      throw const FormatException('ARGUMENTS');
    }
  }
  final ServerDeckMode mode;
  final String? grantId;
}
