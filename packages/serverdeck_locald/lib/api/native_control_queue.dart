import 'dart:async';
import 'dart:collection';

/// Scheduling only: these callbacks cannot create a native peer or a session.
typedef NativeProofDelegate = Future<void> Function({
  void Function(Future<void>)? observeNativeCompletion,
});

/// A rejected logical interest, rather than a failed native identity proof.
final class NativeControlLocalFailure implements Exception {
  NativeControlLocalFailure(this.cause, this.stackTrace);

  final Object cause;
  final StackTrace stackTrace;

  Never rethrowCause() => Error.throwWithStackTrace(cause, stackTrace);

  @override
  String toString() => 'NativeControlLocalFailure';
}

/// Detachable lifetime bookkeeping. A scope supplies no native authority.
final class NativeControlScope {
  final _tickets = <_Ticket>{};
  Object? _reason;

  bool get isRetired => _reason != null;

  void retire([Object? reason]) {
    if (isRetired) return;
    _reason = reason ?? StateError('UNAUTHORIZED');
    for (final ticket in _tickets.toList()) {
      ticket._withdraw(_reason!, StackTrace.current);
    }
    _tickets.clear();
  }
}

/// [result] ends logical interest; [settled] also owns already issued work.
final class NativeControlTicket<T> extends _Ticket {
  NativeControlTicket._(super.queue) {
    result.ignore();
    // One logical completer per ticket. This continuation relinquishes its
    // ticket before forwarding the fixed issued job's physical completion.
    settled = result.then<void>(
      (_) => _afterLogical(),
      onError: (Object _, StackTrace __) => _afterLogical(),
    );
    settled.ignore();
  }

  final _result = Completer<T>();

  Future<T> get result => _result.future;
  late final Future<void> settled;

  void withdraw([Object? reason]) =>
      _withdraw(reason ?? StateError('UNAUTHORIZED'), StackTrace.current);

  Future<void> _afterLogical() {
    final physical = _physical;
    _physical = null;
    return physical?._settled.future ?? Future<void>.value();
  }

  void _succeed([T? value]) {
    if (_done) return;
    _queue._detach(this);
    _result.complete(value);
  }

  @override
  void _fail(Object error, StackTrace stackTrace) {
    if (_done) return;
    _queue._detach(this);
    _result.completeError(error, stackTrace);
  }
}

/// One accepted peer's bounded FIFO of fresh proof cohorts and metadata reads.
///
/// Production must capture genuine epoch-bound delegates in its private peer
/// adapter. Neither this class nor its test callbacks grant native authority.
final class NativeControlQueue {
  NativeControlQueue({
    required NativeProofDelegate revalidate,
    required Future<String> Function() verifiedBundleRoot,
  }) : _revalidate = revalidate,
       _verifiedBundleRoot = verifiedBundleRoot;

  static const maximumTickets = 1024;
  static const maximumAttempt = Duration(seconds: 5);

  final NativeProofDelegate _revalidate;
  final Future<String> Function() _verifiedBundleRoot;
  final _jobs = LinkedList<_Job>();
  final _tickets = <_Ticket>{};
  _ProofJob? _pendingProof;
  _Job? _active;
  bool _pumpScheduled = false;
  bool _retired = false;
  Object? _retirementReason;
  bool _failed = false;
  bool _failureBound = false;
  bool _failureNotified = false;
  void Function()? _failureHandler;

  NativeControlTicket<void> proof({
    required Duration Function() remaining,
    List<NativeControlScope> scopes = const [],
    void Function(Future<void>)? observeNativeCompletion,
  }) {
    final ticket = NativeControlTicket<void>._(this);
    if (!_admit(ticket, remaining, scopes)) return ticket;
    ticket._observer = observeNativeCompletion;
    final job = _pendingProof ??= _ProofJob();
    if (job.list == null) _jobs.add(job);
    job._members.add(ticket);
    ticket._job = job;
    _schedulePump();
    return ticket;
  }

  NativeControlTicket<String> bundleRoot({
    required Duration Function() remaining,
    List<NativeControlScope> scopes = const [],
  }) {
    final ticket = NativeControlTicket<String>._(this);
    if (!_admit(ticket, remaining, scopes)) return ticket;
    final job = _MetadataJob(ticket);
    job._members.add(ticket);
    ticket._job = job;
    _jobs.add(job);
    _schedulePump();
    return ticket;
  }

  /// Bind once to the exact registered session. Explicit retirement is not a
  /// native failure, while a late native error still invokes this hook once.
  void bindFailureHandler(void Function() handler) {
    if (_failureBound) throw StateError('NATIVE_FAILURE_HANDLER_ALREADY_BOUND');
    _failureBound = true;
    _failureHandler = handler;
    _notifyFailure();
  }

  void retire([Object? reason]) {
    if (_retired) return;
    _retired = true;
    _retirementReason = reason ?? StateError('UNAUTHORIZED');
    final stackTrace = StackTrace.current;
    for (final ticket in _tickets.toList()) {
      ticket._withdraw(_retirementReason!, stackTrace);
    }
  }

  /// Retire first when draining a connection: pending jobs are logical only.
  Future<void> get settled => _active?._settled.future ?? Future<void>.value();

  bool _admit(
    _Ticket ticket,
    Duration Function() remaining,
    List<NativeControlScope> scopes,
  ) {
    final stackTrace = StackTrace.current;
    if (_retired) {
      ticket._local(
        _retirementReason ?? StateError('UNAUTHORIZED'),
        stackTrace,
      );
      return false;
    }
    if (_tickets.length >= maximumTickets) {
      ticket._local(StateError('RESOURCE_LIMIT'), stackTrace);
      return false;
    }
    // Reserve before calling any supplied getter: it may reenter the queue.
    _tickets.add(ticket);
    ticket._remaining = remaining;
    for (final scope in scopes.toSet()) {
      if (scope.isRetired) {
        ticket._local(scope._reason!, stackTrace);
        return false;
      }
      ticket._scopes.add(scope);
      scope._tickets.add(ticket);
    }
    try {
      final left = remaining();
      if (ticket._done) return false;
      if (_expired(left)) {
        ticket._timeout();
        return false;
      }
      ticket._budget = left < maximumAttempt ? left : maximumAttempt;
      ticket._watch = Stopwatch()..start();
      ticket._timer = Timer(ticket._budget!, ticket._timeout);
      return true;
    } catch (error, stackTrace) {
      ticket._local(error, stackTrace);
      return false;
    }
  }

  void _detach(_Ticket ticket) {
    ticket._done = true;
    ticket._timer?.cancel();
    ticket._timer = null;
    ticket._watch?.stop();
    ticket._watch = null;
    ticket._budget = null;
    ticket._remaining = null;
    ticket._observer = null;
    for (final scope in ticket._scopes) {
      scope._tickets.remove(ticket);
    }
    ticket._scopes.clear();
    _tickets.remove(ticket);
    final job = ticket._job;
    ticket._job = null;
    if (job != null) {
      job._members.remove(ticket);
      if (!identical(job, _active) && job._members.isEmpty) {
        if (identical(job, _pendingProof)) _pendingProof = null;
        job.unlink();
        job._settled.complete();
      }
    }
    _schedulePump();
  }

  void _schedulePump() {
    if (_retired || _active != null || _pumpScheduled || _jobs.isEmpty) return;
    _pumpScheduled = true;
    scheduleMicrotask(_pump);
  }

  void _pump() {
    _pumpScheduled = false;
    if (_retired || _active != null || _jobs.isEmpty) return;
    final job = _jobs.first;
    job.unlink();
    _active = job; // Reserve and seal before getters or native observers run.
    if (identical(job, _pendingProof)) _pendingProof = null;
    final frontier = <_Ticket>[];
    for (final ticket in job._members.toList()) {
      if (ticket._done) continue;
      try {
        final left = ticket._remaining!();
        if (ticket._done) continue;
        if (_expired(left) || ticket._attemptExpired) {
          ticket._timeout();
        } else {
          frontier.add(ticket);
        }
      } catch (error, stackTrace) {
        ticket._local(error, stackTrace);
      }
    }
    frontier.removeWhere((ticket) => ticket._done);
    if (frontier.isEmpty || _retired) {
      _finishJob(job);
      return;
    }
    // Every issued member owns physical settlement before any observer can
    // reentrantly withdraw another scope or snapshot an owner's drain.
    for (final ticket in frontier) {
      ticket._physical = job;
    }
    if (job is _ProofJob) {
      _issueProof(job, frontier);
    } else {
      _issueMetadata(job as _MetadataJob);
    }
  }

  void _issueProof(_ProofJob job, List<_Ticket> frontier) {
    // Keep the issue-frontier observer snapshot only for this synchronous call.
    final observers = <(_Ticket, void Function(Future<void>))>[
      for (final ticket in frontier)
        if (ticket._observer case final observer?) (ticket, observer),
    ];
    void observe(Future<void> actual) {
      if (job._actual != null) {
        // A captured native delegate supplies exactly one actual future. Keep
        // any invalid duplicate error observed without replacing that proof.
        actual.ignore();
        job._protocolError = StateError('SERVICE_UNAVAILABLE');
        job._protocolStack = StackTrace.current;
        _poison();
        return;
      }
      job._actual = actual;
      actual
          .then<void>(
            (_) {
              job._actualDone = true;
              _finishProofIfReady(job);
            },
            onError: (Object error, StackTrace stackTrace) {
              job._actualDone = true;
              job._actualError = error;
              job._actualStack = stackTrace;
              _poison();
              _finishProofIfReady(job);
            },
          )
          .ignore();
      for (final (ticket, observer) in observers) {
        try {
          observer(actual);
        } catch (_) {
          ticket._observerFailed = true;
        }
      }
    }

    try {
      final raw = _revalidate(observeNativeCompletion: observe);
      raw
          .then<void>(
            (_) {
              job._rawDone = true;
              _finishProofIfReady(job);
            },
            onError: (Object error, StackTrace stackTrace) {
              job._rawDone = true;
              job._rawError = error;
              job._rawStack = stackTrace;
              _finishProofIfReady(job);
            },
          )
          .ignore();
    } catch (error, stackTrace) {
      job._rawDone = true;
      job._rawError = error;
      job._rawStack = stackTrace;
      _finishProofIfReady(job);
    } finally {
      observers.clear();
    }
  }

  void _finishProofIfReady(_ProofJob job) {
    if (!job._rawDone) return;
    final admitted = job._actual != null;
    if (job._rawError != null &&
        (admitted || !_resourceLimit(job._rawError!))) {
      _poison();
    } else if (!admitted && job._rawError == null) {
      job._protocolError = StateError('SERVICE_UNAVAILABLE');
      job._protocolStack = StackTrace.current;
      _poison();
    }
    if (admitted && !job._actualDone) return;
    final error = job._rawError ?? job._actualError ?? job._protocolError;
    final stackTrace =
        job._rawStack ??
        job._actualStack ??
        job._protocolStack ??
        StackTrace.current;
    for (final member in job._members.toList()) {
      final ticket = member as NativeControlTicket<void>;
      if (ticket._attemptExpired) {
        ticket._timeout();
      } else if (ticket._observerFailed) {
        ticket._local(StateError('SERVICE_UNAVAILABLE'), StackTrace.current);
      } else if (error != null) {
        if (!admitted && _resourceLimit(error)) {
          ticket._local(error, stackTrace);
        } else {
          ticket._fail(error, stackTrace);
        }
      } else {
        ticket._succeed();
      }
    }
    _finishJob(job);
  }

  void _issueMetadata(_MetadataJob job) {
    try {
      final raw = _verifiedBundleRoot();
      raw
          .then<void>(
            (root) {
              if (job._ticket._attemptExpired) {
                job._ticket._timeout();
              } else {
                job._ticket._succeed(root);
              }
              _finishJob(job);
            },
            onError: (Object error, StackTrace stackTrace) {
              _finishMetadataError(job, error, stackTrace);
            },
          )
          .ignore();
    } catch (error, stackTrace) {
      _finishMetadataError(job, error, stackTrace);
    }
  }

  void _finishMetadataError(
    _MetadataJob job,
    Object error,
    StackTrace stackTrace,
  ) {
    if (_resourceLimit(error)) {
      job._ticket._local(error, stackTrace);
    } else {
      _poison();
      job._ticket._fail(error, stackTrace);
    }
    _finishJob(job);
  }

  void _poison() {
    _failed = true;
    _retired = true;
    _retirementReason = StateError('UNAUTHORIZED');
    final stackTrace = StackTrace.current;
    for (final ticket in _tickets.toList()) {
      if (!identical(ticket._job, _active)) {
        ticket._fail(StateError('UNAUTHORIZED'), stackTrace);
      }
    }
    _notifyFailure();
  }

  void _notifyFailure() {
    final handler = _failureHandler;
    if (!_failed || _failureNotified || handler == null) return;
    _failureNotified = true;
    _failureHandler = null;
    try {
      handler();
    } catch (_) {
      // Failure hooks cannot replace native outcomes or interrupt ownership.
    }
  }

  void _finishJob(_Job job) {
    if (job._settled.isCompleted) return;
    job._settled.complete();
    if (identical(_active, job)) _active = null;
    _schedulePump();
  }
}

bool _expired(Duration value) => value <= Duration.zero;

bool _resourceLimit(Object error) =>
    error is StateError && error.message == 'RESOURCE_LIMIT';

abstract class _Ticket {
  _Ticket(this._queue);

  final NativeControlQueue _queue;
  final _scopes = <NativeControlScope>{};
  _Job? _job;
  _Job? _physical;
  Duration Function()? _remaining;
  void Function(Future<void>)? _observer;
  Timer? _timer;
  Stopwatch? _watch;
  Duration? _budget;
  bool _done = false;
  bool _observerFailed = false;

  bool get _attemptExpired =>
      _budget != null && _watch != null && _watch!.elapsed >= _budget!;

  void _timeout() => _fail(
    TimeoutException('Native control attempt expired'),
    StackTrace.current,
  );

  void _local(Object error, StackTrace stackTrace) {
    if (error is TimeoutException ||
        error is StateError && error.message == 'TIMEOUT') {
      _timeout();
    } else {
      _fail(NativeControlLocalFailure(error, stackTrace), stackTrace);
    }
  }

  void _withdraw(Object reason, StackTrace stackTrace) =>
      _local(reason, stackTrace);

  void _fail(Object error, StackTrace stackTrace);
}

sealed class _Job extends LinkedListEntry<_Job> {
  final _members = <_Ticket>{};
  final _settled = Completer<void>();
}

final class _ProofJob extends _Job {
  Future<void>? _actual;
  bool _actualDone = false;
  bool _rawDone = false;
  Object? _actualError;
  StackTrace? _actualStack;
  Object? _rawError;
  StackTrace? _rawStack;
  Object? _protocolError;
  StackTrace? _protocolStack;
}

final class _MetadataJob extends _Job {
  _MetadataJob(this._ticket);

  final NativeControlTicket<String> _ticket;
}
