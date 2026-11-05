#include "build_identity.h"
#include "github_releases.h"
#include <cstring>

namespace sd::install {
namespace {
[[noreturn]] void Invalid() { throw updates::Failure("INVALID_ARTIFACT"); }
std::optional<std::string> Resource(HMODULE module, const wchar_t* name, size_t limit) {
  const auto resource = FindResourceW(module, name, RT_RCDATA);
  if (!resource) {
    const auto error = GetLastError();
    if (error == ERROR_RESOURCE_NAME_NOT_FOUND || error == ERROR_RESOURCE_TYPE_NOT_FOUND || error == ERROR_RESOURCE_DATA_NOT_FOUND) return {};
    Invalid();
  }
  const auto size = SizeofResource(module, resource);
  const auto loaded = LoadResource(module, resource);
  const auto* bytes = static_cast<const char*>(LockResource(loaded));
  if (!bytes || !size || size > limit) Invalid(); return std::string(bytes, size);
}
struct RawImage {
  const uint8_t* bytes; size_t size; IMAGE_OPTIONAL_HEADER64 optional{};
  std::vector<IMAGE_SECTION_HEADER> sections;
  template<class T> T Read(size_t offset) const {
    if (offset > size || sizeof(T) > size - offset) Invalid(); T value{}; std::memcpy(&value, bytes + offset, sizeof(T)); return value;
  }
  RawImage(const uint8_t* data, size_t length) : bytes(data), size(length) {
    if (!bytes || size < sizeof(IMAGE_DOS_HEADER) || size > updates::kArtifactLimit) Invalid();
    const auto dos = Read<IMAGE_DOS_HEADER>(0); if (dos.e_magic != IMAGE_DOS_SIGNATURE || dos.e_lfanew < 0) Invalid();
    const size_t nt = static_cast<size_t>(dos.e_lfanew); if (Read<DWORD>(nt) != IMAGE_NT_SIGNATURE) Invalid();
    const auto header = Read<IMAGE_FILE_HEADER>(nt + sizeof(DWORD));
    if (header.Machine != IMAGE_FILE_MACHINE_AMD64 || !header.NumberOfSections || header.NumberOfSections > 96 || header.SizeOfOptionalHeader < sizeof(optional)) Invalid();
    const auto start = nt + sizeof(DWORD) + sizeof(header); optional = Read<IMAGE_OPTIONAL_HEADER64>(start);
    if (optional.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC || !optional.SizeOfHeaders || optional.SizeOfHeaders > size || optional.NumberOfRvaAndSizes > IMAGE_NUMBEROF_DIRECTORY_ENTRIES) Invalid();
    for (size_t i = 0; i < header.NumberOfSections; ++i) sections.push_back(Read<IMAGE_SECTION_HEADER>(start + header.SizeOfOptionalHeader + i * sizeof(IMAGE_SECTION_HEADER)));
  }
  size_t Rva(uint32_t address, size_t count) const {
    std::optional<size_t> found;
    if (address < optional.SizeOfHeaders && count <= optional.SizeOfHeaders - address) found = address;
    for (const auto& section : sections) if (address >= section.VirtualAddress) {
      const auto delta = static_cast<uint64_t>(address) - section.VirtualAddress;
      if (delta <= section.SizeOfRawData && count <= section.SizeOfRawData - delta) {
        const auto offset = static_cast<uint64_t>(section.PointerToRawData) + delta;
        if (found || offset > size || count > size - offset) Invalid(); found = static_cast<size_t>(offset);
      }
    }
    if (!found || *found > size || count > size - *found) Invalid(); return *found;
  }
};
struct ResourceTree {
  const RawImage& image; size_t base, length;
  template<class T> T Read(size_t relative) const {
    if (relative > length || sizeof(T) > length - relative) Invalid(); return image.Read<T>(base + relative);
  }
  std::vector<IMAGE_RESOURCE_DIRECTORY_ENTRY> Entries(uint32_t relative) const {
    const auto directory = Read<IMAGE_RESOURCE_DIRECTORY>(relative);
    const auto count = static_cast<size_t>(directory.NumberOfIdEntries) + directory.NumberOfNamedEntries;
    if (!count || count > 256) Invalid(); std::vector<IMAGE_RESOURCE_DIRECTORY_ENTRY> result;
    for (size_t i = 0; i < count; ++i) result.push_back(Read<IMAGE_RESOURCE_DIRECTORY_ENTRY>(static_cast<size_t>(relative) + sizeof(directory) + i * sizeof(IMAGE_RESOURCE_DIRECTORY_ENTRY)));
    return result;
  }
  bool Named(const IMAGE_RESOURCE_DIRECTORY_ENTRY& entry, const std::wstring& wanted) const {
    if (!entry.NameIsString) return false;
    const size_t offset = entry.NameOffset; const auto count = Read<WORD>(offset); if (count > 128) Invalid();
    std::wstring text; for (size_t i = 0; i < count; ++i) text += Read<wchar_t>(offset + sizeof(WORD) + i * sizeof(wchar_t));
    return text == wanted;
  }
};
struct MappedFile {
  std::unique_ptr<Handle> file, mapping; const uint8_t* view = nullptr; size_t size = 0;
  explicit MappedFile(const std::filesystem::path& path) {
    RejectReparse(path);
    file = std::make_unique<Handle>(CreateFileW(ExtendedPath(path).c_str(), GENERIC_READ, FILE_SHARE_READ,
      nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
    BY_HANDLE_FILE_INFORMATION info{}; LARGE_INTEGER length{};
    if (!file->valid() || !GetFileInformationByHandle(file->get(), &info) || (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) ||
        !GetFileSizeEx(file->get(), &length) || length.QuadPart <= 0 || static_cast<uint64_t>(length.QuadPart) > updates::kArtifactLimit) Invalid();
    size = static_cast<size_t>(length.QuadPart);
    mapping = std::make_unique<Handle>(CreateFileMappingW(file->get(), nullptr, PAGE_READONLY, 0, 0, nullptr)); if (!mapping->valid()) Invalid();
    view = static_cast<const uint8_t*>(MapViewOfFile(mapping->get(), FILE_MAP_READ, 0, 0, 0)); if (!view) Invalid();
  }
  ~MappedFile() { if (view) UnmapViewOfFile(view); }
};
}
std::optional<std::string> ParseRawResource(const uint8_t* bytes, size_t size, const std::wstring& name, size_t limit) {
  if (name.empty() || name.size() > 128 || !limit || limit > kRecordLimit) Invalid();
  const RawImage image(bytes, size);
  if (image.optional.NumberOfRvaAndSizes <= IMAGE_DIRECTORY_ENTRY_RESOURCE) return {};
  const auto directory = image.optional.DataDirectory[IMAGE_DIRECTORY_ENTRY_RESOURCE];
  if (!directory.VirtualAddress && !directory.Size) return {};
  if (!directory.VirtualAddress || !directory.Size) Invalid();
  const ResourceTree tree{image, image.Rva(directory.VirtualAddress, directory.Size), directory.Size};
  std::optional<IMAGE_RESOURCE_DIRECTORY_ENTRY> type, resource;
  for (const auto& entry : tree.Entries(0)) if (!entry.NameIsString && entry.Name == 10) {
    if (type || !entry.DataIsDirectory) Invalid(); type = entry;
  }
  if (!type) return {};
  if (!type->OffsetToDirectory) Invalid();
  for (const auto& entry : tree.Entries(type->OffsetToDirectory)) if (tree.Named(entry, name)) {
    if (resource || !entry.DataIsDirectory) Invalid(); resource = entry;
  }
  if (!resource) return {};
  if (!resource->OffsetToDirectory || resource->OffsetToDirectory == type->OffsetToDirectory) Invalid();
  const auto languages = tree.Entries(resource->OffsetToDirectory);
  if (languages.size() != 1 || languages[0].NameIsString || languages[0].Name > 65535 || languages[0].DataIsDirectory) Invalid();
  const auto data = tree.Read<IMAGE_RESOURCE_DATA_ENTRY>(languages[0].OffsetToData);
  if (!data.Size || data.Size > limit || data.Reserved) Invalid();
  const auto offset = image.Rva(data.OffsetToData, data.Size);
  return std::string(reinterpret_cast<const char*>(bytes + offset), data.Size);
}
updates::Version DecodeBuildVersion(const std::string& bytes) {
  const std::string prefix = "SDBUILD001\n";
  if (bytes.size() > 128 || bytes.size() <= prefix.size() || bytes.rfind(prefix, 0) || bytes.back() != '\n') Invalid();
  try { return updates::ParseVersion(bytes.substr(prefix.size(), bytes.size() - prefix.size() - 1)); } catch (...) { Invalid(); }
}
updates::Version ReadBuildVersion(HMODULE module) {
  const auto text = Resource(module, L"SERVERDECK_BUILD_V1", 128); if (!text) Invalid(); return DecodeBuildVersion(*text);
}
updates::Version ReadFileBuildVersion(const std::filesystem::path& image) {
  const MappedFile file(image); const auto text = ParseRawResource(file.view, file.size, L"SERVERDECK_BUILD_V1", 128);
  if (!text) Invalid(); return DecodeBuildVersion(*text);
}
std::optional<updates::Policy> ReadEmbeddedPolicy(HMODULE module) {
  const auto text = Resource(module, L"SERVERDECK_TRUST_V1", kRecordLimit); if (!text) return {};
  auto policy = updates::ParsePolicy(*text); updates::ValidateGitHubPolicy(policy); return policy;
}
std::optional<updates::Policy> ReadFilePolicy(const std::filesystem::path& image) {
  const MappedFile file(image); const auto text = ParseRawResource(file.view, file.size, L"SERVERDECK_TRUST_V1", kRecordLimit);
  if (!text) return {}; auto policy = updates::ParsePolicy(*text); updates::ValidateGitHubPolicy(policy); return policy;
}
bool SameInstallPath(const std::filesystem::path& a, const std::filesystem::path& b) {
  const auto first = ExtendedPath(a).lexically_normal().wstring(), second = ExtendedPath(b).lexically_normal().wstring();
  return CompareStringOrdinal(first.c_str(), -1, second.c_str(), -1, TRUE) == CSTR_EQUAL;
}
}
