#include "setup_package.h"
#include <cstring>
#include <sstream>

namespace sd::install {
namespace {
[[noreturn]] void Invalid() { throw updates::Failure("INVALID_ARTIFACT"); }
Bytes Resource(HMODULE module, const wchar_t* name, size_t maximum, bool required = true) {
  const auto info = FindResourceW(module, name, RT_RCDATA);
  if (!info) { if (!required) return {}; Invalid(); }
  const auto size = SizeofResource(module, info);
  const auto loaded = LoadResource(module, info);
  const auto* pointer = static_cast<const uint8_t*>(LockResource(loaded));
  if (!pointer || !size || size > maximum) Invalid(); return {pointer, size};
}
SetupManifest ValidateResources(HMODULE module) {
  const auto manifest = Resource(module, L"SERVERDECK_SETUP_V1", kRecordLimit);
  const auto result = DecodeSetupManifest(std::string(reinterpret_cast<const char*>(manifest.data), manifest.size));
  const auto app = Resource(module, L"SERVERDECK_APPLICATION_V1", updates::kArtifactLimit);
  if (app.size != result.app.size || Sha256(app.data, app.size) != result.app.hash) Invalid();
  ValidateApplicationImage(app);
  const auto policy = Resource(module, L"SERVERDECK_TRUST_V1", kRecordLimit, false);
  if (policy.data) updates::ParsePolicy(std::string(reinterpret_cast<const char*>(policy.data), policy.size));
  return result;
}
}
SetupManifest DecodeSetupManifest(const std::string& text) {
  try {
    if (text.empty() || text.size() > kRecordLimit || text.back() != '\n' || text.find('\r') != std::string::npos || text.find('\0') != std::string::npos) Invalid();
    std::istringstream input(text); std::string header, version, size, hash, extra;
    if (!std::getline(input, header) || header != "SDSETUP001" || !std::getline(input, version) ||
        !std::getline(input, size) || !std::getline(input, hash) || std::getline(input, extra) || size.empty() ||
        (size.size() > 1 && size[0] == '0') || size.find_first_not_of("0123456789") != std::string::npos ||
        hash.size() != 64 || hash.find_first_not_of("0123456789abcdef") != std::string::npos) Invalid();
    const auto count = std::stoull(size); if (!count || count > updates::kArtifactLimit) Invalid();
    return {updates::ParseVersion(version), {count, hash}};
  } catch (...) { Invalid(); }
}
void ValidateApplicationImage(Bytes bytes) {
  if (!bytes.data || bytes.size < 64 || bytes.size > updates::kArtifactLimit || bytes.data[0] != 'M' || bytes.data[1] != 'Z') Invalid();
  uint32_t pe = 0; std::memcpy(&pe, bytes.data + 0x3c, 4);
  if (pe > bytes.size - 26 || std::memcmp(bytes.data + pe, "PE\0\0", 4)) Invalid();
  uint16_t machine = 0, magic = 0;
  std::memcpy(&machine, bytes.data + pe + 4, 2); std::memcpy(&magic, bytes.data + pe + 24, 2);
  if (machine != 0x8664 || magic != 0x20b) Invalid();
}
LoadedSetup::LoadedSetup(HMODULE module, const std::filesystem::path& ownFile) {
  manifest_ = ValidateResources(module);
  app_ = Resource(module, L"SERVERDECK_APPLICATION_V1", updates::kArtifactLimit);
  RejectReparse(ownFile);
  file_ = std::make_unique<Handle>(CreateFileW(ExtendedPath(ownFile).c_str(), GENERIC_READ, FILE_SHARE_READ,
    nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  LARGE_INTEGER size{}; BY_HANDLE_FILE_INFORMATION info{};
  if (!file_->valid() || !GetFileSizeEx(file_->get(), &size) || size.QuadPart <= 0 ||
      static_cast<uint64_t>(size.QuadPart) > updates::kArtifactLimit || !GetFileInformationByHandle(file_->get(), &info) ||
      (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY))) Invalid();
  mapping_ = std::make_unique<Handle>(CreateFileMappingW(file_->get(), nullptr, PAGE_READONLY, 0, 0, nullptr));
  if (!mapping_->valid()) Invalid();
  view_ = MapViewOfFile(mapping_->get(), FILE_MAP_READ, 0, 0, 0); if (!view_) Invalid();
  setup_ = {static_cast<const uint8_t*>(view_), static_cast<size_t>(size.QuadPart)};
}
LoadedSetup::~LoadedSetup() { if (view_) UnmapViewOfFile(view_); }
Package LoadedSetup::package() const { return {manifest_.version, app_, setup_}; }
bool LoadedSetup::IsFile(const std::filesystem::path& path) const {
  RejectReparse(path); if (!std::filesystem::exists(path)) return false;
  Handle expected(CreateFileW(ExtendedPath(path).c_str(), FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  BY_HANDLE_FILE_INFORMATION a{}, b{};
  if (!expected.valid() || !GetFileInformationByHandle(file_->get(), &a) || !GetFileInformationByHandle(expected.get(), &b)) Invalid();
  return a.dwVolumeSerialNumber == b.dwVolumeSerialNumber && a.nFileIndexHigh == b.nFileIndexHigh && a.nFileIndexLow == b.nFileIndexLow;
}
void ValidateEmbeddedSetup(const std::filesystem::path& path, const updates::Version& version, const Identity& app) {
  RejectReparse(path);
  HMODULE module = LoadLibraryExW(ExtendedPath(path).c_str(), nullptr, LOAD_LIBRARY_AS_DATAFILE_EXCLUSIVE | LOAD_LIBRARY_AS_IMAGE_RESOURCE);
  if (!module) Invalid();
  try {
    const auto manifest = ValidateResources(module);
    if (!(manifest.version == version) || (app.size && !(manifest.app == app)) || (!app.size && !app.hash.empty())) Invalid();
  } catch (...) { FreeLibrary(module); throw; }
  FreeLibrary(module);
}
std::filesystem::path ModuleFile() {
  std::wstring path(32768, L'\0'); const auto size = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!size || size >= path.size()) Invalid(); path.resize(size); return path;
}
}  // namespace sd::install
