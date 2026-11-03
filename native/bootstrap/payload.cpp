#include "payload.h"
#include "security.h"
#include <windows.h>
#include <algorithm>
#include <cstring>
#include <fstream>
#include <set>
#include <sstream>
#include <stdexcept>

namespace sd {
namespace {
[[noreturn]] void Invalid() { throw std::runtime_error("INVALID_PAYLOAD"); }
uint64_t Number(const std::string& value) {
  if (value.empty() || value.size() > 20 ||
      value.find_first_not_of("0123456789") != std::string::npos) Invalid();
  size_t consumed = 0;
  const auto number = std::stoull(value, &consumed);
  if (consumed != value.size()) Invalid();
  return number;
}
std::wstring Fold(std::wstring value) {
  for (auto& c : value) c = static_cast<wchar_t>(towupper(c));
  return value;
}
bool Verify(const Payload& payload, const std::filesystem::path& path) {
  try {
    RejectReparse(path);
    for (const auto& file : payload.files) {
      auto actual = ExtendedPath(path / file.path);
      RejectReparse(actual);
      if (!std::filesystem::is_regular_file(actual) ||
          std::filesystem::file_size(actual) != file.size) return false;
      std::ifstream stream(actual, std::ios::binary);
      std::vector<uint8_t> bytes(static_cast<size_t>(file.size));
      if (!stream.read(reinterpret_cast<char*>(bytes.data()),
                       static_cast<std::streamsize>(bytes.size())) && !bytes.empty()) return false;
      if (Sha256(bytes.data(), bytes.size()) != file.hash) return false;
    }
    // Extra DLLs/assets are not permitted in a verified runtime tree.
    size_t count = 0;
    for (const auto& entry : std::filesystem::recursive_directory_iterator(path)) {
      RejectReparse(entry.path());
      if (entry.is_regular_file()) ++count;
    }
    return count == payload.files.size();
  } catch (...) { return false; }
}
}
bool SafePayloadPath(const std::wstring& path) {
  if (path.empty() || path.size() > 180 || path.front() == L'/' ||
      path.find_first_of(L"\\:\t\r\n") != std::wstring::npos ||
      path.find(L'\0') != std::wstring::npos) return false;
  std::wistringstream parts(path);
  std::wstring part;
  while (std::getline(parts, part, L'/')) {
    if (part.empty() || part == L"." || part == L".." ||
        part.back() == L'.' || part.back() == L' ' ||
        part.find_first_of(L"<>\"|?*") != std::wstring::npos) return false;
    for (auto c : part) if (c < 32) return false;
    const auto base = Fold(part.substr(0, part.find(L'.')));
    if (base == L"CON" || base == L"PRN" || base == L"AUX" || base == L"NUL" ||
        (base.size() == 4 && (base.substr(0, 3) == L"COM" || base.substr(0, 3) == L"LPT") &&
         ((base[3] >= L'1' && base[3] <= L'9') || base[3] == L'\u00b9' ||
           base[3] == L'\u00b2' || base[3] == L'\u00b3'))) return false;
  }
  return path.back() != L'/';
}
Payload ParsePayload(const uint8_t* bytes, size_t length) {
  if (length < 28 || std::memcmp(bytes, "SDPKG001", 8) != 0) Invalid();
  uint32_t format;
  uint64_t manifestLength, payloadLength;
  std::memcpy(&format, bytes + 8, 4);
  std::memcpy(&manifestLength, bytes + 12, 8);
  std::memcpy(&payloadLength, bytes + 20, 8);
  if (format != 1 || manifestLength > 4 * 1024 * 1024 ||
      payloadLength > 2ull * 1024 * 1024 * 1024 ||
      manifestLength > length - 28 || payloadLength != length - 28 - manifestLength) Invalid();
  std::string manifest(reinterpret_cast<const char*>(bytes + 28), static_cast<size_t>(manifestLength));
  if (manifest.empty() || manifest.back() != '\n') Invalid();
  std::istringstream lines(manifest);
  std::string line;
  for (const auto* expected : {"SDMF001", "hostAbi=1", "platform=windows-x64"}) {
    if (!std::getline(lines, line) || line != expected) Invalid();
  }
  if (!std::getline(lines, line) || line.rfind("build=", 0) != 0 || line.size() <= 6) Invalid();
  Payload result{Sha256(bytes + 28, static_cast<size_t>(manifestLength)), {},
                 bytes + 28 + manifestLength, static_cast<size_t>(payloadLength)};
  std::set<std::wstring> paths;
  uint64_t offset = 0;
  std::wstring previous;
  while (std::getline(lines, line)) {
    std::istringstream fields(line);
    std::string type, size, position, hash, path, extra;
    if (!std::getline(fields, type, '\t') || type != "file" ||
        !std::getline(fields, size, '\t') || !std::getline(fields, position, '\t') ||
        !std::getline(fields, hash, '\t') || !std::getline(fields, path, '\t') ||
        std::getline(fields, extra, '\t')) Invalid();
    PayloadFile file{Wide(path), Number(size), Number(position), hash};
    if (!SafePayloadPath(file.path) || file.offset != offset ||
        file.size > payloadLength - offset || hash.size() != 64 ||
        hash.find_first_not_of("0123456789abcdef") != std::string::npos ||
        !paths.insert(Fold(file.path)).second ||
        (!previous.empty() && previous >= file.path)) Invalid();
    previous = file.path;
    offset += file.size;
    if (Sha256(result.data + file.offset, static_cast<size_t>(file.size)) != hash) Invalid();
    result.files.push_back(std::move(file));
    if (result.files.size() > 10000) Invalid();
  }
  if (offset != payloadLength || result.files.empty() ||
      !paths.count(L"SERVERDECK_HOST.DLL") || !paths.count(L"FLUTTER_WINDOWS.DLL") ||
      !paths.count(L"LIBISAR.DLL") || !paths.count(L"DATA/APP.SO") ||
      !paths.count(L"DATA/ICUDTL.DAT")) Invalid();
  return result;
}
std::filesystem::path ExtractPayload(const Payload& payload,
                                   const std::filesystem::path& root) {
  const auto runtime = ExtendedPath(root) / L"runtime";
  SecureDirectory(runtime);
  const auto directory = runtime / Wide(payload.id);
  const auto lockPath = runtime / (Wide(payload.id) + L".lock");
  RejectReparse(lockPath);
  Handle lock(CreateFileW(lockPath.c_str(), GENERIC_READ | GENERIC_WRITE,
                         0, nullptr, OPEN_ALWAYS, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  if (!lock.valid()) throw std::runtime_error("PAYLOAD_LOCKED");
  if (std::filesystem::exists(directory)) {
    if (Verify(payload, directory)) return directory;
    RejectReparse(directory);
    const auto quarantine = directory.wstring() + L".quarantine-" + Uuid();
    if (!MoveFileExW(directory.c_str(), quarantine.c_str(), MOVEFILE_WRITE_THROUGH))
      throw std::runtime_error("PAYLOAD_QUARANTINE_FAILED");
  }
  ULARGE_INTEGER available{};
  if (!GetDiskFreeSpaceExW(runtime.c_str(), &available, nullptr, nullptr) ||
      available.QuadPart < payload.length + 64ull * 1024 * 1024)
    throw std::runtime_error("INSUFFICIENT_DISK_SPACE");
  const auto staging = directory.wstring() + L".staging-" + Uuid();
  SecureDirectory(staging);
  for (const auto& file : payload.files) {
    const auto destination = ExtendedPath(std::filesystem::path(staging) / file.path);
    auto parent = destination.parent_path();
    std::vector<std::filesystem::path> missing;
    while (!std::filesystem::exists(parent)) {
      missing.push_back(parent); parent = parent.parent_path();
    }
    for (auto item = missing.rbegin(); item != missing.rend(); ++item) SecureDirectory(*item);
    RejectReparse(destination);
    Handle output(CreateFileW(destination.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                              FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
    if (!output.valid()) throw std::runtime_error("EXTRACTION_FAILED");
    for (uint64_t offset = 0; offset < file.size;) {
      DWORD size = static_cast<DWORD>(std::min<uint64_t>(file.size - offset, 1024 * 1024));
      DWORD written = 0;
      if (!WriteFile(output.get(), payload.data + file.offset + offset, size, &written, nullptr) ||
          written != size) throw std::runtime_error("EXTRACTION_FAILED");
      offset += size;
    }
    if (!FlushFileBuffers(output.get())) throw std::runtime_error("EXTRACTION_FAILED");
  }
  if (!Verify(payload, staging) ||
      !MoveFileExW(staging.c_str(), directory.c_str(), MOVEFILE_WRITE_THROUGH))
    throw std::runtime_error("PAYLOAD_PUBLICATION_FAILED");
  return directory;
}
}
