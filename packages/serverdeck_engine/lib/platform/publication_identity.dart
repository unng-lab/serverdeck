import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/validation.dart';

/// Kernel synchronization naming only; no process, role or permission proof.
/// The native root separately verifies canonical app root and actual OS owner.
final class PublicationIdentity {
  PublicationIdentity({
    required String ownerIdentity,
    required String appRoot,
    required String generation,
  }) {
    try {
      requireUuid(generation);
      if (ownerIdentity.isEmpty ||
          ownerIdentity.length > 4096 ||
          RegExp(r'[\x00\r\n]').hasMatch(ownerIdentity) ||
          appRoot.isEmpty ||
          appRoot.length > 32767 ||
          RegExp(r'[\x00\r\n]').hasMatch(appRoot) ||
          utf8.decode(utf8.encode(ownerIdentity)) != ownerIdentity ||
          utf8.decode(utf8.encode(appRoot)) != appRoot) {
        throw StateError('UNAUTHORIZED');
      }
      final digest = const DartSha256()
          .hashSync(
            utf8.encode(
              'serverdeck-next-publication-v1\n$ownerIdentity\n$appRoot\n$generation',
            ),
          )
          .bytes
          .map((v) => v.toRadixString(16).padLeft(2, '0'))
          .join();
      _mutexName = 'Global\\ServerDeckNext.v1.$digest';
    } catch (_) {
      throw StateError('UNAUTHORIZED');
    }
  }
  late final String _mutexName;
  String get mutexName => _mutexName;
  String get poisonName => '$mutexName.poison';
}
