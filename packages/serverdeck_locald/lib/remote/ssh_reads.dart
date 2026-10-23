part of 'ssh_transport.dart';

enum SshReadSource { system, metrics, packages, units, journal }

/// Closed read operations. Callers cannot submit a command, script or path.
final class SshReadRequest {
  const SshReadRequest.system()
    : source = SshReadSource.system,
      unit = null,
      since = null,
      until = null,
      priority = null,
      cursor = null,
      limit = 0;
  const SshReadRequest.metrics()
    : source = SshReadSource.metrics,
      unit = null,
      since = null,
      until = null,
      priority = null,
      cursor = null,
      limit = 0;
  const SshReadRequest.packages()
    : source = SshReadSource.packages,
      unit = null,
      since = null,
      until = null,
      priority = null,
      cursor = null,
      limit = 0;
  const SshReadRequest.units()
    : source = SshReadSource.units,
      unit = null,
      since = null,
      until = null,
      priority = null,
      cursor = null,
      limit = 0;
  factory SshReadRequest.journal({
    String? unit,
    DateTime? since,
    DateTime? until,
    int? priority,
    String? cursor,
    int limit = 100,
  }) {
    if (limit < 1 ||
        limit > 1000 ||
        priority != null && (priority < 0 || priority > 7) ||
        unit != null &&
            !RegExp(r'^[A-Za-z0-9_.@:-]{1,240}\.service$').hasMatch(unit) ||
        since != null && !since.isUtc ||
        until != null && !until.isUtc ||
        since != null && until != null && since.isAfter(until) ||
        cursor != null &&
            (cursor.isEmpty ||
                utf8.encode(cursor).length > 4096 ||
                cursor.codeUnits.any((c) => c < 32 || c == 127)))
      _invalid();
    return SshReadRequest._journal(unit, since, until, priority, cursor, limit);
  }
  const SshReadRequest._journal(
    this.unit,
    this.since,
    this.until,
    this.priority,
    this.cursor,
    this.limit,
  ) : source = SshReadSource.journal;
  final SshReadSource source;
  final String? unit, cursor;
  final DateTime? since, until;
  final int? priority;
  final int limit;
  int get _maximum => switch (source) {
    SshReadSource.system || SshReadSource.metrics => 256 * 1024,
    SshReadSource.packages => 4 * 1024 * 1024,
    SshReadSource.units => 2 * 1024 * 1024,
    SshReadSource.journal => 8 * 1024 * 1024,
  };
  String get _command => switch (source) {
    SshReadSource.system => _readSystem,
    SshReadSource.metrics => _readMetrics,
    SshReadSource.packages => r'''LC_ALL=C dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' ''',
    SshReadSource.units => 'LC_ALL=C SYSTEMD_PAGER=cat systemctl list-units --all --type=service --plain --no-legend --no-pager',
    SshReadSource.journal => [
      'LC_ALL=C SYSTEMD_PAGER=cat journalctl --output=json --all --no-pager --quiet --reverse --lines=${limit + (cursor == null ? 0 : 1)}',
      if (unit != null) '--unit=${_shellQuote(unit!)}',
      if (since != null) '--since=${_shellQuote(since!.toIso8601String())}',
      if (until != null) '--until=${_shellQuote(until!.toIso8601String())}',
      if (priority != null) '--priority=$priority',
      if (cursor != null) '--cursor=${_shellQuote(cursor!)}',
    ].join(' '),
  };
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

// Base64 section envelopes keep arbitrary remote text out of local syntax.
// No remote temporary file, installation, sudo or state mutation is performed.
const _readSystem = r'''LC_ALL=C /bin/sh -c '
read_source() { label=$1; shift; value=$("$@" 2>/dev/null); status=$?; printf "%s\t%s\t" "$label" "$status"; printf "%s" "$value" | base64 -w0; printf "\n"; }
read_source osRelease cat /etc/os-release
read_source kernel uname -r
read_source architecture uname -m
read_source hostname hostname
read_source uptime cat /proc/uptime
read_source bootId cat /proc/sys/kernel/random/boot_id
read_source observedAt date -u +%Y-%m-%dT%H:%M:%S.%3NZ
' ''';
const _readMetrics = r'''LC_ALL=C /bin/sh -c '
read_source() { label=$1; shift; value=$("$@" 2>/dev/null); status=$?; printf "%s\t%s\t" "$label" "$status"; printf "%s" "$value" | base64 -w0; printf "\n"; }
read_source cpu cat /proc/stat
read_source memory cat /proc/meminfo
read_source disk df -P -B1 /
read_source network cat /proc/net/dev
read_source diskIo cat /proc/diskstats
read_source observedAt date -u +%Y-%m-%dT%H:%M:%S.%3NZ
' ''';

final class SshReadOutput {
  SshReadOutput._(
    Uint8List bytes,
    this.exitCode,
    this.truncated,
    this.permissionDenied,
    this.unavailable,
  ) : bytes = bytes.asUnmodifiableView();
  final Uint8List bytes;
  final int? exitCode;
  final bool truncated;
  final bool permissionDenied, unavailable;
}

final class _SshReadOperation {
  _SshReadOperation(this.owner, this.request, this.budget) {
    _result.future.ignore();
  }
  final _SshOperation owner;
  final SshReadRequest request;
  final Duration budget;
  final _result = Completer<SshReadOutput>(), _done = Completer<void>();
  final _output = BytesBuilder(copy: false);
  final _errorPrefix = BytesBuilder(copy: false);
  SSHSession? _session;
  bool _stopped = false;
  Future<SshReadOutput> get result => _result.future;
  Future<void> get done => _done.future;
  void stop(SshTransportCode code) {
    _stopped = true;
    if (!_result.isCompleted) _result.completeError(SshTransportFailure(code));
    _session?.close();
  }

  Future<void> run() async {
    final timer = Timer(budget, () => stop(SshTransportCode.TIMEOUT));
    StreamSubscription<Uint8List>? output, errors;
    final outDone = Completer<void>(), errDone = Completer<void>();
    var truncated = false;
    try {
      final session = _session = await owner._client!.execute(request._command);
      if (_stopped || owner._stopped) session.close();
      output = session.stdout.listen(
        (chunk) {
          final left = request._maximum - _output.length;
          if (left > 0)
            _output.add(
              chunk.length > left
                  ? Uint8List.sublistView(chunk, 0, left)
                  : chunk,
            );
          if (chunk.length > left) {
            truncated = true;
            session.close();
          }
        },
        onError: (Object _) {
          if (!outDone.isCompleted) outDone.complete();
          stop(SshTransportCode.CONNECTION_FAILED);
        },
        onDone: () {
          if (!outDone.isCompleted) outDone.complete();
        },
      );
      errors = session.stderr.listen(
        (chunk) {
          final left = 4096 - _errorPrefix.length;
          if (left > 0)
            _errorPrefix.add(
              chunk.length > left
                  ? Uint8List.sublistView(chunk, 0, left)
                  : chunk,
            );
        },
        onError: (Object _) {
          if (!errDone.isCompleted) errDone.complete();
        },
        onDone: () {
          if (!errDone.isCompleted) errDone.complete();
        },
      );
      await session.stdin.close();
      await session.done;
      await Future.wait([outDone.future, errDone.future]);
      if (!_result.isCompleted) {
        final errorBytes = _errorPrefix.takeBytes();
        final category = utf8
            .decode(errorBytes, allowMalformed: true)
            .toLowerCase();
        errorBytes.fillRange(0, errorBytes.length, 0);
        _result.complete(
          SshReadOutput._(
            _output.takeBytes(),
            session.exitCode,
            truncated,
            category.contains('permission denied') ||
                category.contains('insufficient permissions') ||
                category.contains('not seeing messages from other users'),
            category.contains('command not found') ||
                category.contains('not been booted with systemd') ||
                session.exitCode == 127,
          ),
        );
      }
    } catch (_) {
      if (!_result.isCompleted)
        _result.completeError(
          const SshTransportFailure(SshTransportCode.CONNECTION_FAILED),
        );
    } finally {
      timer.cancel();
      _session?.close();
      await output?.cancel();
      await errors?.cancel();
      if (_session != null) {
        try {
          await _session!.done;
        } catch (_) {}
      }
      owner._reads.remove(this);
      _done.complete();
    }
  }
}
