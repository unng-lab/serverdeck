import 'package:cryptography/dart.dart';

import 'codec.dart';
import 'validation.dart';

/// Structural build descriptor. Trust comes from the native bundle verifier,
/// not this parser or a digest that happens to recompute correctly.
final class ExecutorRelease {
  factory ExecutorRelease.fromJson(Map<String, Object?> value) {
    StrictCodec().encode(value, maxBytes: 64 * 1024);
    requireFields(value, {
      'format',
      'runtimeVersion',
      'lockDigest',
      'bridgeDigest',
      'compilerDigest',
      'files',
    });
    if (value['format'] is! int || value['format'] != 1) _bad();
    const names = {
      '__init__.py',
      'codec.py',
      'compiler.py',
      'journal.py',
      'probes.py',
      'runner.py',
      'jobs.py',
      'preflight.py',
      'bridge.py',
      'supervisor.py',
      'qualification.py',
      'apt.py',
      'apt_gate.py',
    };
    final files = value['files'];
    if (files is! Map<String, Object?>) _bad();
    requireFields(files, names);
    for (final hash in [
      value['lockDigest'],
      value['bridgeDigest'],
      value['compilerDigest'],
      ...files.values,
    ]) {
      if (hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) _bad();
    }
    final version = value['runtimeVersion'];
    if (version is! String ||
        version.length > 100 ||
        !RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+\+[a-f0-9]{64}$').hasMatch(version))
      _bad();
    final base = version.split('+').first;
    final hash = _digest({
      'baseVersion': base,
      'lockDigest': value['lockDigest'],
      'bridgeDigest': value['bridgeDigest'],
      'files': files,
    });
    if (version != '$base+$hash' ||
        value['compilerDigest'] !=
            _digest({
              'codec.py': files['codec.py'],
              'compiler.py': files['compiler.py'],
            }))
      _bad();
    return ExecutorRelease._(
      Map.unmodifiable({
        ...value,
        'files': Map<String, Object?>.unmodifiable(files),
      }),
    );
  }
  const ExecutorRelease._(this._json);
  final Map<String, Object?> _json;
  String get runtimeVersion => _json['runtimeVersion'] as String;
  String get lockDigest => _json['lockDigest'] as String;
  String get bridgeDigest => _json['bridgeDigest'] as String;
  String get compilerDigest => _json['compilerDigest'] as String;
  Map<String, Object?> toJson() => _json;
  bool matches(Map<String, Object?> hello) => [
    'runtimeVersion',
    'lockDigest',
    'bridgeDigest',
    'compilerDigest',
  ].every((field) => hello[field] == _json[field]);
}

Never _bad() => throw const FormatException('VALIDATION');
String _digest(Map<String, Object?> value) => const DartSha256()
    .hashSync(StrictCodec().canonical(value))
    .bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();
