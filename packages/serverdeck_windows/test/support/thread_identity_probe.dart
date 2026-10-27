import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:win32/win32.dart';

// Windows x64 TOKEN_STATISTICS layout, winnt.h:
// https://learn.microsoft.com/windows/win32/api/winnt/ns-winnt-token_statistics
final class _Statistics extends Struct {
  @Uint64()
  external int tokenId;
  @Uint64()
  external int authenticationId;
  @Int64()
  external int expiration;
  @Uint32()
  external int type;
  @Uint32()
  external int impersonation;
  @Uint32()
  external int charged;
  @Uint32()
  external int available;
  @Uint32()
  external int groups;
  @Uint32()
  external int privileges;
  @Uint64()
  external int modifiedId;
}

String? _threadToken() {
  final handle = calloc<Pointer>();
  final length = calloc<Uint32>();
  final statistics = calloc<_Statistics>();
  try {
    final opened = OpenThreadToken(
      GetCurrentThread(),
      TOKEN_QUERY,
      true,
      handle,
    );
    if (!opened.value) {
      if (opened.error == ERROR_NO_TOKEN) return null;
      throw StateError('THREAD_TOKEN_QUERY_UNAVAILABLE');
    }
    if (sizeOf<_Statistics>() != 56 ||
        !GetTokenInformation(
          HANDLE(handle.value),
          TokenStatistics,
          statistics.cast(),
          sizeOf<_Statistics>(),
          length,
        ).value ||
        length.value != sizeOf<_Statistics>()) {
      throw StateError('THREAD_TOKEN_QUERY_UNAVAILABLE');
    }
    final value = statistics.ref;
    return '${value.tokenId}/${value.authenticationId}/${value.type}/'
        '${value.type == 2 ? value.impersonation : 0}/${value.modifiedId}';
  } finally {
    var confirmed = true;
    if (handle.value != nullptr) {
      confirmed = CloseHandle(HANDLE(handle.value)).value;
    }
    calloc.free(statistics);
    calloc.free(length);
    calloc.free(handle);
    if (!confirmed) throw StateError('THREAD_TOKEN_CLOSE_UNCONFIRMED');
  }
}

/// Test-only, synchronous observation; never impersonates or changes a token.
T observeThreadIdentity<T>(
  T Function() operation, {
  String Function()? processSidQuery,
}) {
  // Test-only fault injection never changes OS privileges or tokens.
  String sidSnapshot() {
    try {
      return (processSidQuery ?? currentUserSid)();
    } catch (_) {
      throw StateError('THREAD_PROCESS_SID_QUERY_UNAVAILABLE');
    }
  }

  final thread = GetCurrentThreadId();
  final sid = sidSnapshot();
  final before = _threadToken();
  try {
    return operation();
  } finally {
    if (GetCurrentThreadId() != thread ||
        sidSnapshot() != sid ||
        _threadToken() != before ||
        GetCurrentThreadId() != thread) {
      throw StateError('THREAD_IDENTITY_CHANGED');
    }
  }
}
