#pragma once
#include <cstdint>

namespace sd {
enum class KeyFileAdmission { ready, readFailed, invalidSize };
// Shared native decision, exercised without opening a picker or a user file.
inline KeyFileAdmission AdmitKeyFile(bool opened, bool sizeRead, int64_t bytes) {
  if (!opened || !sizeRead) return KeyFileAdmission::readFailed;
  if (bytes < 1 || bytes > 1024 * 1024) return KeyFileAdmission::invalidSize;
  return KeyFileAdmission::ready;
}
}
