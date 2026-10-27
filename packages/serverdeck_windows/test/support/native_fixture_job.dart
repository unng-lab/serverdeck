import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:win32/win32.dart';

HANDLE? _job;

/// Fixture-only containment. No name, breakaway flag, external PID or elevated
/// access. The handle is deliberately retained until this process exits so even
/// a hard-killed scenario owner cannot leave its subsequently spawned children.
void containCurrentFixtureTree() {
  if (_job != null || Abi.current() != Abi.windowsX64)
    throw StateError('FIXTURE_JOB');
  final job = CreateJobObject(null, null).value;
  if (!job.isValid) throw StateError('FIXTURE_JOB');
  // Windows x64 JOBOBJECT_EXTENDED_LIMIT_INFORMATION: 64-byte basic limits,
  // 48-byte IO_COUNTERS, four SIZE_T fields. LimitFlags is DWORD at offset16.
  final limits = calloc<Uint8>(144);
  try {
    (limits + 16).cast<Uint32>().value = 0x2000; // KILL_ON_JOB_CLOSE
    if (!SetInformationJobObject(
          job,
          JobObjectExtendedLimitInformation,
          limits,
          144,
        ).value ||
        !AssignProcessToJobObject(job, GetCurrentProcess()).value) {
      CloseHandle(job);
      throw StateError('FIXTURE_JOB');
    }
    _job = job;
  } finally {
    calloc.free(limits);
  }
}

bool fixtureProcessExited(RetainedProcessIdentity identity) {
  final code = calloc<Uint32>();
  try {
    if (!GetExitCodeProcess(identity.handle, code).value)
      throw StateError('FIXTURE_JOB');
    return code.value != 259;
  } finally {
    calloc.free(code);
  }
}
