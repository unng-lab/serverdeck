#pragma once
#include "security.h"
#include <functional>
#include <optional>
#include <stdexcept>

namespace sd::monitoring {
inline const std::string running = "{\"version\":1,\"state\":\"running\"}";
inline const std::string clean = "{\"version\":1,\"state\":\"clean\"}";

inline bool SafeAttributes(DWORD attributes) {
  return attributes != INVALID_FILE_ATTRIBUTES &&
      !(attributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY));
}

// A dedicated fixed-path boundary, never a general file read/write API.
inline std::optional<std::string> Read(const std::filesystem::path& root) {
  const auto path = ExtendedPath(root / L"data/monitoring-run-v1.json");
  RejectReparse(path);
  Handle file(CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
      OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  if (!file.valid()) {
    if (GetLastError() == ERROR_FILE_NOT_FOUND) return std::nullopt;
    throw std::runtime_error("STORAGE_IO");
  }
  FILE_ATTRIBUTE_TAG_INFO info{};
  LARGE_INTEGER size{};
  if (!GetFileInformationByHandleEx(file.get(), FileAttributeTagInfo, &info, sizeof(info)) ||
      !SafeAttributes(info.FileAttributes) || !GetFileSizeEx(file.get(), &size) ||
      size.QuadPart < 0 || size.QuadPart > 128) throw std::runtime_error("STORAGE_IO");
  std::string bytes(static_cast<size_t>(size.QuadPart), '\0');
  DWORD count = 0;
  if (!ReadFile(file.get(), bytes.data(), static_cast<DWORD>(bytes.size()), &count, nullptr) ||
      count != bytes.size()) throw std::runtime_error("STORAGE_IO");
  return bytes;
}

inline void Write(const std::filesystem::path& root, const std::string& bytes) {
  SecureDirectory(root / L"data");
  AtomicFile(root / L"data/monitoring-run-v1.json",
      std::vector<uint8_t>(bytes.begin(), bytes.end()));
}

/// Cache the PREVIOUS run once, including after a failed running publication.
/// Until Begin succeeds callers must not admit any automatic monitoring work.
class RunState {
 public:
  bool Begin(const std::function<std::optional<std::string>()>& read,
             const std::function<void(const std::string&)>& write) {
    if (!classified_) {
      try {
        const auto previous = read();
        autoAllowed_ = !previous || *previous == clean;
      } catch (...) { autoAllowed_ = false; }
      classified_ = true;
    }
    if (!published_) {
      write(running);
      published_ = true;
    }
    return autoAllowed_;
  }
  void Finish(const std::function<void(const std::string&)>& write) {
    if (published_ && !finished_) {
      write(clean);
      finished_ = true;
    }
  }
 private:
  bool classified_ = false, autoAllowed_ = false, published_ = false, finished_ = false;
};
}
