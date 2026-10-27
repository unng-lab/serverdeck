import 'dart:convert';
import 'dart:io';

import 'package:unorm_dart/unorm_dart.dart' as unicode;

import 'validation.dart';

String normalizeText(
  Object? value, {
  bool trim = false,
  bool pem = false,
  bool preserve = false,
}) {
  if (value is! String) throw const FormatException('VALIDATION');
  for (var i = 0; i < value.codeUnits.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= value.length ||
          value.codeUnitAt(i) < 0xdc00 ||
          value.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('VALIDATION');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('VALIDATION');
    }
  }
  if (value.runes.any(
    (c) => (c < 32 && !(pem && (c == 10 || c == 13))) || (c >= 127 && c <= 159),
  )) {
    throw const FormatException('VALIDATION');
  }
  final text = trim ? value.trim() : value;
  return preserve ? text : unicode.nfc(text);
}

String _boundedText(Object? input, int min, int max, {bool noSpace = false}) {
  final text = normalizeText(input, trim: true);
  if (text.runes.length < min ||
      text.runes.length > max ||
      (noSpace && RegExp(r'\s').hasMatch(text))) {
    throw const FormatException('VALIDATION');
  }
  return text;
}

Map<String, Object?> normalizeProfileFields(Map<String, Object?> input) {
  final name = _boundedText(input['name'], 1, 128);
  final address = _boundedText(input['address'], 1, 253, noSpace: true);
  final user = _boundedText(input['sshUser'], 1, 64, noSpace: true);
  if (address.contains('[') ||
      address.contains(']') ||
      address.contains('/') ||
      address.contains('%')) {
    throw const FormatException('VALIDATION');
  }
  final ip = InternetAddress.tryParse(address);
  if (ip == null) {
    final host = address.endsWith('.')
        ? address.substring(0, address.length - 1)
        : address;
    final labels = host.split('.');
    if (RegExp(r'^[0-9.]+$').hasMatch(host) ||
        labels.any(
          (label) =>
              label.length > 63 ||
              !RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$')
                  .hasMatch(label),
        )) {
      throw const FormatException('VALIDATION');
    }
  }
  final port = input.containsKey('port') ? input['port'] : 22;
  if (port is! int || port < 1 || port > 65535)
    throw const FormatException('VALIDATION');
  final rawTags = input.containsKey('tags') ? input['tags'] : <String>[];
  if (rawTags is! List || rawTags.length > 16)
    throw const FormatException('VALIDATION');
  final tags = rawTags.map((v) => _boundedText(v, 1, 64)).toList();
  if (tags.toSet().length != tags.length)
    throw const FormatException('VALIDATION');
  final fields = <String, Object?>{
    'name': name,
    'address': address,
    'port': port,
    'sshUser': user,
    'tags': tags,
  };
  if (utf8.encode(jsonEncode(fields)).length > 16 * 1024)
    throw const FormatException('VALIDATION');
  return fields;
}

Map<String, Object?> normalizeCredential(
  Map<String, Object?> input, {
  bool creating = false,
}) {
  switch (input['action']) {
    case 'keep':
      requireFields(input, {'action'});
      if (creating) throw const FormatException('VALIDATION');
      return {'action': 'keep'};
    case 'remove':
      requireFields(input, {'action'});
      return {'action': 'remove'};
    case 'replace':
      if (input['kind'] == 'password') {
        requireFields(input, {'action', 'kind', 'password'});
        final password = normalizeText(input['password'], preserve: true);
        if (password.isEmpty || utf8.encode(password).length > 4096)
          throw const FormatException('VALIDATION');
        return {'action': 'replace', 'kind': 'password', 'password': password};
      }
      if (input['kind'] == 'privateKey') {
        requireFields(input, {'action', 'kind', 'privateKey', 'passphrase'});
        final key = normalizeText(
          input['privateKey'],
          pem: true,
          preserve: true,
        );
        if (utf8.encode(key).length > 65536)
          throw const FormatException('VALIDATION');
        final envelope = RegExp(
          r'^-----BEGIN ([A-Z0-9 ]*PRIVATE KEY)-----\r?\n([\s\S]+?)\r?\n-----END \1-----(?:\r?\n)?$',
        ).firstMatch(key);
        if (envelope == null) throw const FormatException('VALIDATION');
        var body = envelope.group(2)!;
        // Traditional PEM headers precede the base64 payload. Usability and
        // decryption remain SSH-stage concerns, not save-time key parsing.
        final headers = RegExp(
          r'^Proc-Type: 4,ENCRYPTED\r?\nDEK-Info: [A-Za-z0-9-]+,[A-Fa-f0-9]+\r?\n\r?\n',
        ).firstMatch(body);
        if (headers != null) body = body.substring(headers.end);
        if (!RegExp(r'^[A-Za-z0-9+/=\r\n]+$').hasMatch(body))
          throw const FormatException('VALIDATION');
        List<int>? decoded;
        try {
          decoded = base64.decode(body.replaceAll(RegExp(r'[\r\n]'), ''));
          if (decoded.isEmpty) throw const FormatException('VALIDATION');
        } on FormatException {
          throw const FormatException('VALIDATION');
        } finally {
          decoded?.fillRange(0, decoded.length, 0);
        }
        final passphrase = input['passphrase'] == null
            ? null
            : normalizeText(input['passphrase'], preserve: true);
        if (passphrase != null && utf8.encode(passphrase).length > 4096)
          throw const FormatException('VALIDATION');
        return {
          'action': 'replace',
          'kind': 'privateKey',
          'privateKey': key,
          'passphrase': passphrase,
        };
      }
  }
  throw const FormatException('VALIDATION');
}
