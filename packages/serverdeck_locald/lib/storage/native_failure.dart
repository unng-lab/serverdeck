import 'package:isar_community/isar.dart';

/// Exact Isar3.3.2 messages qualify only for a subsequent rollback proof.
/// FFI exposes error text, not stable typed native error codes.
bool isNativeCapacityFailure(Object error) =>
    error is IsarError &&
    (error.message == 'The database is full.' ||
        error.message ==
            'Auto increment id cannot be generated because the limit is reached.');
