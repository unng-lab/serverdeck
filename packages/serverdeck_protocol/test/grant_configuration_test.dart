import 'package:serverdeck_protocol/grant_owner.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:test/test.dart';

const grant = '12345678-1234-4234-9234-123456789abc';
Map<String, Object?> config(String command) => {
  'command': command,
  'args': ['--mcp-stdio', '--grant-id', grant],
};

void main() {
  test('current owner configuration accepts only same-executable stdio shape and captures immutable bytes', () {
    for (final command in [
      r'C:\ServerDeck\serverdeck.exe',
      r'\\host\share\ServerDeck\serverdeck.exe',
      'C:/ServerDeck/serverdeck.exe',
    ]) {
      final input = config(command);
      final result = captureGrantOwnerResult('grants.configuration', input);
      expect(result, input);
      (input['args'] as List)[2] = 'changed';
      expect(result['args'], ['--mcp-stdio', '--grant-id', grant]);
      expect(
        () => (result['args'] as List)[0] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        captureTrustedMethodResult('grants.configuration', config(command)),
        config(command),
      );
    }
  });
  test('removed executable/root mode, extra authority arguments and malformed commands are rejected', () {
    for (final input in <Map<String, Object?>>[
      {
        'command': r'C:\ServerDeck\mcp.exe',
        'args': ['--app-root', r'C:\ServerDeck', '--grant-id', grant],
      },
      config(r'C:\ServerDeck\mcp.exe'),
      config('serverdeck.exe'),
      config(r'C:serverdeck.exe'),
      config(r'\serverdeck.exe'),
      config(r'\\host\serverdeck.exe'),
      config(r'C:\ServerDeck\..\serverdeck.exe'),
      config('C:\\bad\n\\serverdeck.exe'),
      config(r'C:\ServerDeck\other-serverdeck.exe'),
      {...config(r'C:\ServerDeck\serverdeck.exe'), 'owner': true},
      {
        ...config(r'C:\ServerDeck\serverdeck.exe'),
        'args': ['--mcp-stdio', '--grant-id', grant, '--owner'],
      },
      {
        ...config(r'C:\ServerDeck\serverdeck.exe'),
        'args': ['--mcp-stdio', '--grant-id', 'not-a-uuid'],
      },
      {
        ...config(r'C:\ServerDeck\serverdeck.exe'),
        'args': ['--mcp-stdio'],
      },
    ]) {
      expect(
        () => captureGrantOwnerResult('grants.configuration', input),
        throwsFormatException,
      );
    }
  });
}
