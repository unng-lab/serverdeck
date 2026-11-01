import 'dart:async';
import 'dart:typed_data';

import 'workspace_rows.dart';

enum WorkspaceCollection {
  workspace('StoredWorkspace', singleton: true),
  settings('StoredSettings', singleton: true),
  profiles('StoredProfile'),
  credentials('StoredCredential'),
  receipts('StoredReceipt'),
  hostTrust('StoredHostTrust'),
  grants('StoredMcpGrant'),
  delegations('StoredDelegation'),
  automationProfiles('StoredAutomationProfile'),
  revisions('StoredAutomationRevision'),
  plans('StoredAutomationPlan'),
  approvals('StoredAutomationApproval'),
  jobs('StoredAutomationJob'),
  desired('StoredDesiredState'),
  events('StoredAutomationEvent'),
  automationReceipts('StoredAutomationReceipt');

  const WorkspaceCollection(this.persistedName, {this.singleton = false});
  final String persistedName;
  final bool singleton;

  static WorkspaceCollection fromName(String name) => values.firstWhere(
    (value) => value.persistedName == name,
    orElse: () => throw StateError('STORAGE_BLOCKED'),
  );
}

/// Trusted composition dependency, never selected from a request or preference.
abstract interface class WorkspaceStorageProvider {
  bool get hasOpenInstance;
  WorkspaceRowSource preflightRows(
    Uint8List bytes, {
    required String directory,
  });
  WorkspaceStorageOpen createOpenAttempt({required String directory});
}

abstract interface class WorkspaceStorageOpen {
  Future<WorkspaceStorage> open();

  /// True only before an owning open or after positive attributable closure.
  Future<bool> cleanupAfterFailedOpen();
}

abstract interface class WorkspaceStorage implements WorkspaceRowSource {
  Future<T> writeTransaction<T>(
    Future<T> Function(WorkspaceWriteTransaction transaction) write,
  );
  bool isCapacityFailure(Object error);
  Future<bool> close();
}

abstract interface class WorkspaceWriteTransaction {
  Future<StoredRow?> get(WorkspaceCollection collection, int id);
  Future<StoredRow?> getByEntityId(
    WorkspaceCollection collection,
    String entityId,
  );
  Future<int> put(WorkspaceCollection collection, StoredRow row);
  Future<bool> delete(WorkspaceCollection collection, int id);
}

final class _TransactionContext {
  _TransactionContext(this.storage);
  final TransactionalWorkspaceStorage storage;
  _OperationScope work = _OperationScope();
}

/// Shared transaction lifetime/close mechanics. Backends supply only row I/O;
/// no domain state, receipt, permission or successful service DTO enters here.
abstract base class TransactionalWorkspaceStorage implements WorkspaceStorage {
  static final _transactionZone = Object();
  final _admitted = <Future<void>>{};
  bool _closing = false;
  Future<bool>? _closeOperation;

  Future<T> backendRead<T>(Future<T> Function() read);
  Future<T> backendWrite<T>(Future<T> Function() write);
  Future<int> backendCount(WorkspaceCollection collection);
  Future<List<StoredRow>> backendRows(
    WorkspaceCollection collection,
    int limit,
  );
  Future<StoredRow?> backendGet(WorkspaceCollection collection, int id);
  Future<StoredRow?> backendGetByEntityId(
    WorkspaceCollection collection,
    String entityId,
  );
  Future<int> backendPut(WorkspaceCollection collection, StoredRow row);
  Future<bool> backendDelete(WorkspaceCollection collection, int id);
  Future<bool> backendClose();

  Future<T> _admit<T>(Future<T> Function() action) async {
    if (_closing || Zone.current[_transactionZone] != null) {
      throw StateError('STORAGE_BLOCKED');
    }
    final settled = Completer<void>();
    _admitted.add(settled.future);
    final context = _TransactionContext(this);
    try {
      return await runZoned(action, zoneValues: {_transactionZone: context});
    } finally {
      context.work._active = false;
      _admitted.remove(settled.future);
      settled.complete();
    }
  }

  @override
  Future<T> readTransaction<T>(Future<T> Function() read) =>
      _admit(() => backendRead(() => _context().work.run(read)));

  @override
  Future<T> writeTransaction<T>(
    Future<T> Function(WorkspaceWriteTransaction transaction) write,
  ) => _admit(
    () => backendWrite(() {
      final context = _context();
      final scope = _WriteScope(this);
      context.work = scope;
      return scope.runWrite(write);
    }),
  );

  _TransactionContext _context() {
    final context = Zone.current[_transactionZone];
    if (context is! _TransactionContext ||
        !context.work._active ||
        !identical(context.storage, this)) {
      throw StateError('STORAGE_BLOCKED');
    }
    return context;
  }

  @override
  Future<int> count(String collection) {
    return _context().work._operation(
      () => backendCount(WorkspaceCollection.fromName(collection)),
    );
  }

  @override
  Future<List<StoredRow>> read(String collection, {required int limit}) {
    return _context().work._operation(() async {
      if (limit < 1 || limit > 51251) throw StateError('STORAGE_BLOCKED');
      return List.unmodifiable(
        await backendRows(WorkspaceCollection.fromName(collection), limit),
      );
    });
  }

  @override
  Future<bool> close() => _closeOperation ??= _close();

  Future<bool> _close() async {
    _closing = true;
    await Future.wait(_admitted.toList());
    return backendClose();
  }
}

class _OperationScope {
  bool _active = true;
  final _pending = <Future<void>>{};
  Object? _failure;
  StackTrace? _failureStack;

  Future<T> run<T>(Future<T> Function() action) async {
    T? result;
    Object? callbackError;
    StackTrace? callbackStack;
    try {
      result = await action();
    } catch (error, stack) {
      callbackError = error;
      callbackStack = stack;
    }
    _active = false;
    if (_pending.isNotEmpty) {
      _failure ??= StateError('STORAGE_BLOCKED');
      _failureStack ??= StackTrace.current;
      await Future.wait(_pending.toList());
    }
    if (callbackError != null) {
      Error.throwWithStackTrace(callbackError, callbackStack!);
    }
    if (_failure != null) Error.throwWithStackTrace(_failure!, _failureStack!);
    return result as T;
  }

  Future<T> _operation<T>(Future<T> Function() action) {
    if (!_active) return Future.error(StateError('STORAGE_BLOCKED'));
    final settled = Completer<void>();
    _pending.add(settled.future);
    void finish() {
      _pending.remove(settled.future);
      settled.complete();
    }

    final result = Future<T>.sync(action).then<T>(
      (value) {
        finish();
        return value;
      },
      onError: (Object error, StackTrace stack) {
        _failure ??= error;
        _failureStack ??= stack;
        finish();
        Error.throwWithStackTrace(error, stack);
      },
    );
    // Observe an abandoned operation as well as retaining its abort evidence.
    unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    return result;
  }
}

final class _WriteScope extends _OperationScope
    implements WorkspaceWriteTransaction {
  _WriteScope(this.storage) : context = storage._context();
  final TransactionalWorkspaceStorage storage;
  final _TransactionContext context;

  Future<T> runWrite<T>(
    Future<T> Function(WorkspaceWriteTransaction transaction) action,
  ) => run(() => action(this));

  @override
  Future<T> _operation<T>(Future<T> Function() action) => super._operation(() {
    if (!identical(storage._context(), context)) {
      throw StateError('STORAGE_BLOCKED');
    }
    return action();
  });

  void _id(int id) {
    if (id < 1 || id > 9223372036854775807) {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  @override
  Future<StoredRow?> get(WorkspaceCollection collection, int id) =>
      _operation(() {
        _id(id);
        return storage.backendGet(collection, id);
      });

  @override
  Future<StoredRow?> getByEntityId(
    WorkspaceCollection collection,
    String entityId,
  ) => _operation(() {
    if (collection.singleton) throw StateError('STORAGE_BLOCKED');
    return storage.backendGetByEntityId(collection, entityId);
  });

  @override
  Future<int> put(WorkspaceCollection collection, StoredRow row) =>
      _operation(() async {
        _id(row.nativeId);
        if (collection.singleton
            ? row.nativeId != 1 || row.entityId != null
            : row.entityId == null) {
          throw StateError('STORAGE_BLOCKED');
        }
        final id = await storage.backendPut(collection, row);
        if (id != row.nativeId) throw StateError('STORAGE_BLOCKED');
        return id;
      });

  @override
  Future<bool> delete(WorkspaceCollection collection, int id) => _operation(() {
    _id(id);
    return storage.backendDelete(collection, id);
  });
}
