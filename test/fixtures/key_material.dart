import 'dart:io';
import 'dart:typed_data';

import 'package:serverdeck/profiles/key_envelope.dart';

/// Independent expected identity for synthetic adapter inputs. Deliberately
/// malformed-file boundary cases still receive a valid, separate identity.
Uint8List fixturePublicBytes(Uint8List file) {
  OpenSshEnvelope? envelope;
  try {
    envelope = OpenSshEnvelope.read(file);
  } catch (_) {
    envelope = OpenSshEnvelope.read(
      File('test/fixtures/ssh/ed25519.txt').readAsBytesSync(),
    );
  }
  try {
    return Uint8List.fromList(envelope.hint.encoded);
  } finally {
    envelope.dispose();
  }
}
