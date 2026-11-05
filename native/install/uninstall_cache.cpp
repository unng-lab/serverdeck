#include "uninstall.h"
#include "build_identity.h"
#include "mcp_json.h"
#include <algorithm>

namespace sd::install {
namespace {
[[noreturn]] void Invalid() { throw updates::Failure("RECOVERY_REQUIRED"); }
[[noreturn]] void Io() { throw updates::Failure("STORAGE_IO"); }
bool Hash(const std::string& hash) { return hash.size() == 64 && hash.find_first_not_of("0123456789abcdef") == std::string::npos; }
std::string ReadMarker(const std::filesystem::path& path) {
  RejectReparse(path); Handle file(CreateFileW(ExtendedPath(path).c_str(), GENERIC_READ, FILE_SHARE_READ,
    nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  BY_HANDLE_FILE_INFORMATION info{}; LARGE_INTEGER size{};
  if (!file.valid() || !GetFileInformationByHandle(file.get(), &info) || (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) ||
      !GetFileSizeEx(file.get(), &size) || size.QuadPart <= 0 || size.QuadPart > kRecordLimit) Invalid();
  std::string bytes(static_cast<size_t>(size.QuadPart), '\0'); DWORD read = 0;
  if (!ReadFile(file.get(), bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr) || read != bytes.size()) Io(); return bytes;
}
}
std::string EncodeRemovalTicket(const RemovalTicket& ticket) {
  if (!mcp::CanonicalUuid(ticket.id) || !Hash(ticket.commitHash)) Invalid();
  const auto bytes = std::string("SDREMOVE001\n") + mcp::Encode(mcp::Json::Object{
    {"commitHash", ticket.commitHash}, {"id", ticket.id}, {"installation", EncodeInstallation(ticket.target)}}) + '\n';
  if (bytes.size() > kRecordLimit) Invalid(); return bytes;
}
RemovalTicket DecodeRemovalTicket(const std::string& bytes) {
  try {
    const std::string prefix = "SDREMOVE001\n";
    if (bytes.size() > kRecordLimit || bytes.size() <= prefix.size() || bytes.rfind(prefix, 0) || bytes.back() != '\n') Invalid();
    const auto body = mcp::Decode(bytes.substr(prefix.size(), bytes.size() - prefix.size() - 1));
    if (body.object().size() != 3) Invalid();
    RemovalTicket ticket{body.at("id").string(), body.at("commitHash").string(), DecodeInstallation(body.at("installation").string())};
    if (EncodeRemovalTicket(ticket) != bytes) Invalid(); return ticket;
  } catch (...) { Invalid(); }
}
std::filesystem::path RemovalCacheRoot(const Paths& paths) {
  paths.Validate(); return paths.data.parent_path() / L"Temp" / L"ServerDeck-maintenance";
}
std::filesystem::path PrepareRemovalCache(Files& files, Lease& lease, const Installation& current, Bytes setup) {
  if (!lease.Owns(files.roots(), true)) throw updates::Failure("OWNER_RUNNING");
  if (current.sid != Utf8(files.roots().sid) || !setup.data || setup.size != current.setup.size ||
      Sha256(setup.data, setup.size) != current.setup.hash || !files.Exists(L"commit.v1") ||
      !files.Exists(L"installation.v1") || files.ReadRecord(L"installation.v1") != EncodeInstallation(current)) Invalid();
  const auto proof = files.ReadRecord(L"commit.v1");
  const RemovalTicket ticket{Utf8(Uuid()), Sha256(reinterpret_cast<const uint8_t*>(proof.data()), proof.size()), current};
  const auto root = RemovalCacheRoot(files.roots());
  if (!std::filesystem::exists(root.parent_path())) SecureDirectory(root.parent_path());
  SecureDirectory(root); const auto directory = root / Wide(ticket.id);
  // UUID collision is never permission to overwrite an existing helper/cache.
  if (std::filesystem::exists(directory)) Invalid(); SecureDirectory(directory);
  const auto image = directory / L"ServerDeckSetup.exe";
  Handle output(CreateFileW(ExtendedPath(image).c_str(), GENERIC_WRITE | WRITE_DAC, 0, nullptr, CREATE_NEW, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  if (!output.valid()) Io(); SecureFileHandle(output.get());
  for (size_t offset = 0; offset < setup.size;) {
    const auto count = static_cast<DWORD>(std::min<size_t>(65536, setup.size - offset)); DWORD written = 0;
    if (!WriteFile(output.get(), setup.data + offset, count, &written, nullptr) || written != count) Io(); offset += count;
  }
  if (!FlushFileBuffers(output.get())) Io();
  const auto marker = EncodeRemovalTicket(ticket);
  AtomicFile(directory / L"removal.v1", std::vector<uint8_t>(marker.begin(), marker.end()));
  return image;
}
RemovalTicket ReadRemovalTicket(const Paths& paths, const std::filesystem::path& image) {
  const auto directory = image.parent_path();
  if (!SameInstallPath(directory.parent_path(), RemovalCacheRoot(paths)) || image.filename() != L"ServerDeckSetup.exe" ||
      !mcp::CanonicalUuid(Utf8(directory.filename().wstring()))) Invalid();
  RejectReparse(image); const auto ticket = DecodeRemovalTicket(ReadMarker(directory / L"removal.v1"));
  if (ticket.id != Utf8(directory.filename().wstring()) || ticket.target.sid != Utf8(paths.sid)) Invalid(); return ticket;
}
RemovalTicket ReadRemovalCache(const Paths& paths, const std::filesystem::path& image, const Package& package) {
  const auto ticket = ReadRemovalTicket(paths, image);
  if (!(ticket.target.version == package.version) ||
      package.setup.size != ticket.target.setup.size || !package.setup.data || Sha256(package.setup.data, package.setup.size) != ticket.target.setup.hash ||
      package.app.size != ticket.target.app.size || !package.app.data || Sha256(package.app.data, package.app.size) != ticket.target.app.hash) Invalid();
  return ticket;
}
std::optional<std::filesystem::path> FindInterruptedRemoval(Files& files, Lease& lease, SetupValidator validator) {
  if (!lease.Owns(files.roots(), true)) throw updates::Failure("OWNER_RUNNING");
  if (!files.Exists(L"journal.v1")) return {};
  const auto journal = DecodeJournal(files.ReadRecord(L"journal.v1")); if (journal.kind != Operation::remove) return {};
  const auto image = RemovalCacheRoot(files.roots()) / Wide(journal.id) / L"ServerDeckSetup.exe";
  const auto ticket = ReadRemovalTicket(files.roots(), image);
  if (!validator || journal.target.sid != Utf8(files.roots().sid) || EncodeInstallation(ticket.target) != EncodeInstallation(journal.target)) Invalid();
  RejectReparse(image);
  Handle file(CreateFileW(ExtendedPath(image).c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  BY_HANDLE_FILE_INFORMATION info{}; LARGE_INTEGER size{};
  if (!file.valid() || !GetFileInformationByHandle(file.get(), &info) || (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) ||
      !GetFileSizeEx(file.get(), &size) || size.QuadPart <= 0 || static_cast<uint64_t>(size.QuadPart) != ticket.target.setup.size) Invalid();
  Handle mapping(CreateFileMappingW(file.get(), nullptr, PAGE_READONLY, 0, 0, nullptr)); if (!mapping.valid()) Io();
  struct View { const uint8_t* bytes; ~View() { if (bytes) UnmapViewOfFile(bytes); } } view{
    static_cast<const uint8_t*>(MapViewOfFile(mapping.get(), FILE_MAP_READ, 0, 0, 0))};
  if (!view.bytes || Sha256(view.bytes, static_cast<size_t>(size.QuadPart)) != ticket.target.setup.hash) Invalid();
  validator(image, ticket.target.version, ticket.target.app); return image;
}
void LaunchRemovalRetry(const Paths& paths, const std::filesystem::path& image) {
  ReadRemovalTicket(paths, image);
  std::wstring command = L"\"" + image.wstring() + L"\" --uninstall-retry";
  if (command.size() >= 32767) Invalid();
  STARTUPINFOW startup{}; startup.cb = sizeof(startup); PROCESS_INFORMATION process{};
  if (!CreateProcessW(ExtendedPath(image).c_str(), command.data(), nullptr, nullptr, FALSE, CREATE_UNICODE_ENVIRONMENT,
      nullptr, nullptr, &startup, &process)) Io();
  Handle thread(process.hThread), child(process.hProcess);
}
}
