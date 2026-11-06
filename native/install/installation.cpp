#include "installation.h"
#include "mcp_json.h"
#include "maintenance_handoff.h"
#include <bcrypt.h>
#include <sddl.h>
#include <shlobj.h>
#include <algorithm>
#include <array>
#include <sstream>

namespace sd::install {
namespace {
using Json = sd::mcp::Json;
[[noreturn]] void Invalid() { throw updates::Failure("RECOVERY_REQUIRED"); }
[[noreturn]] void Io() { throw updates::Failure("STORAGE_IO"); }
bool Hash(const std::string& value) {
  return value.size() == 64 && value.find_first_not_of("0123456789abcdef") == std::string::npos;
}
bool Sid(const std::string& text) {
  if (text.empty() || text.size() > 256 || text.find('\0') != std::string::npos) return false;
  PSID sid = nullptr;
  if (!ConvertStringSidToSidW(Wide(text).c_str(), &sid)) return false;
  LPWSTR canonical = nullptr;
  const bool valid = IsValidSid(sid) && ConvertSidToStringSidW(sid, &canonical);
  const bool equal = valid && Utf8(canonical) == text;
  if (canonical) LocalFree(canonical);
  LocalFree(sid); return equal;
}
void Validate(const Identity& value) {
  if (!value.size || value.size > updates::kArtifactLimit || !Hash(value.hash)) Invalid();
}
void Validate(const Installation& value) {
  if (!Sid(value.sid) || !(updates::ParseVersion(value.version.text) == value.version)) Invalid();
  Validate(value.app); Validate(value.setup);
  if (value.consumedVersion.empty()) { if (!value.consumedSetupHash.empty()) Invalid(); }
  else if (!Hash(value.consumedSetupHash) || value.version < updates::ParseVersion(value.consumedVersion)) Invalid();
  if (value.consumedVersion == value.version.text && value.consumedSetupHash != value.setup.hash) Invalid();
}
void Bound(const std::string& value) {
  if (value.empty() || value.size() > kRecordLimit || value.back() != '\n' ||
      value.find('\0') != std::string::npos || value.find('\r') != std::string::npos) Invalid();
}
Json Body(const std::string& text, const char* header) {
  Bound(text); const auto prefix = std::string(header) + '\n';
  if (text.rfind(prefix, 0) != 0) Invalid();
  return mcp::Decode(text.substr(prefix.size(), text.size() - prefix.size() - 1));
}
std::string Envelope(const char* header, const Json& body) {
  auto text = std::string(header) + '\n' + mcp::Encode(body) + '\n'; Bound(text); return text;
}
Identity IdentityFrom(const Json& body, const char* sizeKey, const char* hashKey) {
  const auto size = body.at(sizeKey).integer();
  if (size <= 0 || static_cast<uint64_t>(size) > updates::kArtifactLimit) Invalid();
  Identity identity{static_cast<uint64_t>(size), body.at(hashKey).string()}; Validate(identity); return identity;
}
const char* Kind(Operation kind) {
  switch (kind) { case Operation::install: return "install"; case Operation::update: return "update";
    case Operation::remove: return "remove"; } Invalid();
}
const char* StageName(Stage stage) {
  switch (stage) { case Stage::prepared: return "prepared"; case Stage::files: return "files";
    case Stage::registered: return "registered"; } Invalid();
}
void Validate(const Journal& value) {
  if (!mcp::CanonicalUuid(value.id)) Invalid();
  Validate(value.target); Kind(value.kind); StageName(value.stage);
  if (value.previous) {
    Validate(*value.previous);
    if (value.previous->sid != value.target.sid || value.target.version < value.previous->version) Invalid();
    if (value.kind == Operation::install) Invalid();
    if ((value.kind == Operation::remove || value.previous->version == value.target.version) &&
        (!(value.previous->version == value.target.version) ||
         !(value.previous->app == value.target.app) || !(value.previous->setup == value.target.setup))) Invalid();
  } else if (value.kind != Operation::install) Invalid();
}
bool Match(const std::optional<Identity>& actual, const Identity& expected) {
  return actual && *actual == expected;
}
bool Within(const std::filesystem::path& child, const std::filesystem::path& parent) {
  const auto c = child.lexically_normal().wstring(), p = parent.lexically_normal().wstring();
  return c.size() >= p.size() && CompareStringOrdinal(c.data(), static_cast<int>(p.size()),
    p.data(), static_cast<int>(p.size()), TRUE) == CSTR_EQUAL &&
    (c.size() == p.size() || c[p.size()] == L'\\' || c[p.size()] == L'/');
}
std::filesystem::path Folder(REFKNOWNFOLDERID id) {
  PWSTR folder = nullptr;
  if (FAILED(SHGetKnownFolderPath(id, 0, nullptr, &folder))) Io();
  const std::filesystem::path result(folder); CoTaskMemFree(folder); return result;
}
std::unique_ptr<Handle> Acquire(const std::filesystem::path& path, DWORD timeout, const char* busy) {
  const auto start = GetTickCount64();
  for (;;) {
    RejectReparse(path);
    auto file = std::make_unique<Handle>(CreateFileW(ExtendedPath(path).c_str(),
      GENERIC_READ | GENERIC_WRITE | WRITE_DAC, 0, nullptr, OPEN_ALWAYS, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
    if (file->valid()) {
      BY_HANDLE_FILE_INFORMATION info{};
      if (!GetFileInformationByHandle(file->get(), &info) ||
          (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))) Io();
      SecureFileHandle(file->get()); return file;
    }
    if (GetLastError() != ERROR_SHARING_VIOLATION) Io();
    if (GetTickCount64() - start >= timeout) throw updates::Failure(busy);
    Sleep(10);
  }
}
bool Artifact(const std::wstring& path) {
  for (const auto* allowed : {L"ServerDeck.exe", L"ServerDeck.new", L"ServerDeck.previous",
      L"ServerDeckSetup.exe", L"ServerDeckSetup.new", L"ServerDeckSetup.previous",
      L"recovery/ServerDeckSetup.exe", L"pending/slot0/ServerDeckSetup.exe", L"pending/slot1/ServerDeckSetup.exe"}) if (path == allowed) return true;
  return false;
}
size_t RecordLimit(const std::wstring& path) {
  if (path == L"pending/slot0/catalog.v1" || path == L"pending/slot1/catalog.v1") return updates::kCatalogLimit;
  for (const auto* allowed : {L"installation.v1", L"journal.v1", L"commit.v1", L"recovery/recovery.v1",
      L"pending/consent.v1", L"pending/slot0/owner.v1", L"pending/slot1/owner.v1",
      L"pending/tombstone.v1", L"pending/defer-once.v1", L"data/update-preferences.v1"}) if (path == allowed) return kRecordLimit;
  return 0;
}
Handle* OpenRead(const std::filesystem::path& path, std::unique_ptr<Handle>& holder, uint64_t maximum) {
  RejectReparse(path);
  holder = std::make_unique<Handle>(CreateFileW(ExtendedPath(path).c_str(), GENERIC_READ, FILE_SHARE_READ,
    nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN, nullptr));
  BY_HANDLE_FILE_INFORMATION info{};
  if (!holder->valid() || !GetFileInformationByHandle(holder->get(), &info) ||
      (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) ||
      ((static_cast<uint64_t>(info.nFileSizeHigh) << 32) | info.nFileSizeLow) > maximum) Io();
  return holder.get();
}
bool StagingObject(const std::filesystem::path& path, uint64_t maximum) {
  bool exists = false;
  auto normalized = std::filesystem::absolute(path).wstring();
  if (normalized.rfind(L"\\\\?\\UNC\\", 0) == 0) normalized = L"\\\\" + normalized.substr(8);
  else if (normalized.rfind(L"\\\\?\\", 0) == 0) normalized = normalized.substr(4);
  const auto leaf = std::filesystem::path(normalized);
  auto current = leaf;
  for (;;) {
    const DWORD attributes = GetFileAttributesW(ExtendedPath(current).c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) {
      const auto error = GetLastError();
      if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) Io();
    } else {
      if (attributes & FILE_ATTRIBUTE_REPARSE_POINT) Invalid();
      if (current == leaf) { if (attributes & FILE_ATTRIBUTE_DIRECTORY) Invalid(); exists = true; }
    }
    const auto parent = current.parent_path(); if (parent == current || parent.empty()) break; current = parent;
  }
  if (exists) {
    WIN32_FILE_ATTRIBUTE_DATA info{};
    if (!GetFileAttributesExW(ExtendedPath(path).c_str(), GetFileExInfoStandard, &info)) Io();
    if (((static_cast<uint64_t>(info.nFileSizeHigh) << 32) | info.nFileSizeLow) > maximum) Invalid();
  }
  return exists;
}
struct Digest {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  Digest() {
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) Io();
    if (BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) < 0) {
      BCryptCloseAlgorithmProvider(algorithm, 0); algorithm = nullptr; Io();
    }
  }
  ~Digest() { if (hash) BCryptDestroyHash(hash); if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0); }
  void Add(uint8_t* data, ULONG size) { if (BCryptHashData(hash, data, size, 0) < 0) Io(); }
  std::string Finish() {
    uint8_t bytes[32]{}; if (BCryptFinishHash(hash, bytes, 32, 0) < 0) Io();
    constexpr char digits[] = "0123456789abcdef"; std::string text;
    for (const auto c : bytes) { text += digits[c >> 4]; text += digits[c & 15]; } return text;
  }
};
}  // namespace

std::string EncodeInstallation(const Installation& value) {
  Validate(value);
  Json::Object body{{"sid", value.sid}, {"version", value.version.text},
    {"appSize", static_cast<int64_t>(value.app.size)}, {"appHash", value.app.hash},
    {"setupSize", static_cast<int64_t>(value.setup.size)}, {"setupHash", value.setup.hash}};
  if (!value.consumedVersion.empty()) {
    body.emplace("consumedVersion", value.consumedVersion); body.emplace("consumedSetupHash", value.consumedSetupHash);
  }
  return Envelope("SDINSTALL001", body);
}
Installation DecodeInstallation(const std::string& value) {
  try {
    const auto body = Body(value, "SDINSTALL001");
    if (body.object().size() != 6 && body.object().size() != 8) Invalid();
    Installation record{body.at("sid").string(), updates::ParseVersion(body.at("version").string()),
      IdentityFrom(body, "appSize", "appHash"), IdentityFrom(body, "setupSize", "setupHash"), {}, {}};
    if (body.object().size() == 8) {
      record.consumedVersion = body.at("consumedVersion").string();
      record.consumedSetupHash = body.at("consumedSetupHash").string();
      if (record.consumedVersion.empty()) Invalid();
    }
    Validate(record); return record;
  } catch (...) { Invalid(); }
}
std::string EncodeJournal(const Journal& value) {
  Validate(value);
  return Envelope("SDJOURNAL001", Json::Object{{"id", value.id}, {"kind", Kind(value.kind)},
    {"stage", StageName(value.stage)}, {"previous", value.previous ? Json(EncodeInstallation(*value.previous)) : Json(nullptr)},
    {"target", EncodeInstallation(value.target)}});
}
Journal DecodeJournal(const std::string& value) {
  try {
    const auto body = Body(value, "SDJOURNAL001"); if (body.object().size() != 5) Invalid();
    const auto& kind = body.at("kind").string(); const auto& stage = body.at("stage").string();
    Journal journal; journal.id = body.at("id").string();
    if (kind == "install") journal.kind = Operation::install;
    else if (kind == "update") journal.kind = Operation::update;
    else if (kind == "remove") journal.kind = Operation::remove; else Invalid();
    if (stage == "prepared") journal.stage = Stage::prepared;
    else if (stage == "files") journal.stage = Stage::files;
    else if (stage == "registered") journal.stage = Stage::registered; else Invalid();
    if (!std::holds_alternative<std::nullptr_t>(body.at("previous").value))
      journal.previous = DecodeInstallation(body.at("previous").string());
    journal.target = DecodeInstallation(body.at("target").string()); Validate(journal); return journal;
  } catch (...) { Invalid(); }
}
std::string EncodeRecovery(const Recovery& value) {
  if (!Sid(value.sid) || !(updates::ParseVersion(value.version.text) == value.version)) Invalid();
  Validate(value.setup);
  auto text = "SDRECOVERY001\n" + value.sid + '\n' + value.version.text + '\n' +
    std::to_string(value.setup.size) + '\n' + value.setup.hash + '\n'; Bound(text); return text;
}
Recovery DecodeRecovery(const std::string& value) {
  try {
    Bound(value); std::istringstream stream(value); std::array<std::string, 5> fields;
    for (auto& field : fields) if (!std::getline(stream, field)) Invalid();
    std::string extra; if (std::getline(stream, extra) || fields[0] != "SDRECOVERY001" ||
        fields[3].empty() || (fields[3].size() > 1 && fields[3][0] == '0') ||
        fields[3].find_first_not_of("0123456789") != std::string::npos) Invalid();
    const auto size = std::stoull(fields[3]);
    Recovery record{fields[1], updates::ParseVersion(fields[2]), {size, fields[4]}};
    EncodeRecovery(record); return record;
  } catch (...) { Invalid(); }
}
RecoveryPlan PlanRecovery(const Journal& journal, const Observation& files) {
  Validate(journal);
  if (journal.kind == Operation::remove) return {RecoveryAction::resumeRemoval, {}, {}};
  if (Match(files.app, journal.target.app) && Match(files.setup, journal.target.setup) && files.registrationMatchesTarget)
    return {RecoveryAction::commit, L"ServerDeck.exe", L"ServerDeckSetup.exe"};
  if (journal.previous) {
    RecoveryPlan plan{RecoveryAction::rollback, {}, {}};
    const auto& old = *journal.previous;
    if (Match(files.app, old.app)) plan.appSource = L"ServerDeck.exe";
    else if (Match(files.backupApp, old.app)) plan.appSource = L"ServerDeck.previous";
    if (Match(files.setup, old.setup)) plan.setupSource = L"ServerDeckSetup.exe";
    else if (Match(files.backupSetup, old.setup)) plan.setupSource = L"ServerDeckSetup.previous";
    if (!plan.appSource.empty() && !plan.setupSource.empty()) return plan;
  } else if ((!files.app || Match(files.app, journal.target.app)) &&
             (!files.setup || Match(files.setup, journal.target.setup)))
    return {RecoveryAction::discardFresh, {}, {}};
  return {};
}

Paths Paths::CurrentUser() {
  const auto local = Folder(FOLDERID_LocalAppData);
  Paths paths{local / L"Programs" / L"ServerDeck", local / L"ServerDeck", Folder(FOLDERID_Programs), UserSid()};
  paths.Validate(); return paths;
}
void Paths::Validate() const {
  if (!install.is_absolute() || !data.is_absolute() || !programs.is_absolute() || sid != UserSid() ||
      Within(install, data) || Within(data, install) ||
      install.wstring().size() > 32000 || data.wstring().size() > 32000 || programs.wstring().size() > 32000)
    throw updates::Failure("STORAGE_IO");
  RejectReparse(install); RejectReparse(data); RejectReparse(programs);
}
Lease::Lease(const Paths& paths, bool vacantOwner, DWORD timeoutMs) : paths_(paths) {
  paths.Validate(); SecureDirectory(paths.data);
  maintenance_ = Acquire(paths.data / L"maintenance.lock", timeoutMs, "BUSY");
  if (vacantOwner) owner_ = Acquire(paths.data / L"owner.lock", 0, "OWNER_RUNNING");
}
std::unique_ptr<Lease> Lease::Resume(const Paths& paths, std::unique_ptr<Handle>& owner, DWORD timeoutMs) {
  auto lease = std::make_unique<Lease>(paths, false, timeoutMs);
  if (!owner) throw updates::Failure("RECOVERY_REQUIRED");
  ValidateLeaseHandle(owner->get(), paths.data / L"owner.lock");
  lease->owner_ = std::move(owner); return lease;
}
bool Lease::Owns(const Paths& paths, bool vacantOwner) const {
  const auto equal = [](const std::filesystem::path& a, const std::filesystem::path& b) { return Within(a, b) && Within(b, a); };
  return maintenance_ && maintenance_->valid() && (!vacantOwner || (owner_ && owner_->valid())) &&
    paths.sid == paths_.sid && equal(paths.install, paths_.install) && equal(paths.data, paths_.data) && equal(paths.programs, paths_.programs);
}
Lease::Lease(Paths paths, std::unique_ptr<Handle> maintenance, std::unique_ptr<Handle> owner)
    : paths_(std::move(paths)), maintenance_(std::move(maintenance)), owner_(std::move(owner)) {}
std::unique_ptr<Lease> Lease::Adopt(const Paths& paths, std::unique_ptr<Handle> maintenance, std::unique_ptr<Handle> owner) {
  paths.Validate(); if (!maintenance || !owner) throw updates::Failure("RECOVERY_REQUIRED");
  ValidateLeaseHandle(maintenance->get(), paths.data / L"maintenance.lock");
  ValidateLeaseHandle(owner->get(), paths.data / L"owner.lock");
  return std::unique_ptr<Lease>(new Lease(paths, std::move(maintenance), std::move(owner)));
}
Files::Files(Paths paths) : paths_(std::move(paths)) { paths_.Validate(); }
std::filesystem::path Files::Path(const std::wstring& relative) const {
  if (!Artifact(relative) && !RecordLimit(relative)) throw updates::Failure("STORAGE_IO");
  const auto path = relative == L"data/update-preferences.v1" ? paths_.data / L"update-preferences.v1" : paths_.install / relative;
  RejectReparse(path); return path;
}
bool Files::Exists(const std::wstring& relative) const {
  const auto path = Path(relative); const DWORD attrs = GetFileAttributesW(ExtendedPath(path).c_str());
  if (attrs == INVALID_FILE_ATTRIBUTES) {
    if (GetLastError() == ERROR_FILE_NOT_FOUND || GetLastError() == ERROR_PATH_NOT_FOUND) return false;
    Io();
  }
  if (attrs & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) Io();
  return true;
}
std::string Files::ReadRecord(const std::wstring& relative) const {
  const auto maximum = RecordLimit(relative); if (!maximum) Io();
  std::unique_ptr<Handle> holder; auto* file = OpenRead(Path(relative), holder, maximum);
  LARGE_INTEGER length{}; if (!GetFileSizeEx(file->get(), &length)) Io();
  std::string value(static_cast<size_t>(length.QuadPart), '\0'); DWORD read = 0;
  if (!ReadFile(file->get(), value.data(), static_cast<DWORD>(value.size()), &read, nullptr) || read != value.size()) Io();
  return value;
}
void Files::EnsureParent(const std::wstring& relative) {
  Path(relative);
  const auto parent = paths_.install.parent_path();
  if (!std::filesystem::exists(parent)) SecureDirectory(parent);
  SecureDirectory(paths_.install);
  if (relative == L"data/update-preferences.v1") SecureDirectory(paths_.data);
  else {
    auto nested = paths_.install;
    for (const auto& component : std::filesystem::path(relative).parent_path()) {
      nested /= component; SecureDirectory(nested);
    }
  }
}
void Files::Write(const std::wstring& relative, const uint8_t* bytes, size_t length) {
  Stage(relative, length, [&](HANDLE file) {
    for (size_t offset = 0; offset < length;) {
      const auto chunk = static_cast<DWORD>(std::min<size_t>(65536, length - offset)); DWORD written = 0;
      if (!WriteFile(file, bytes + offset, chunk, &written, nullptr) || written != chunk) Io();
      offset += written;
    }
  });
}
void Files::CleanupStagingHeld(bool download) {
  const auto owner = ExtendedPath(paths_.install / (download ? L".download-owner.v1" : L".stage-owner.v1"));
  const auto payload = ExtendedPath(paths_.install / (download ? L".download.bin" : L".stage.bin"));
  const bool ownerExists = StagingObject(owner, kRecordLimit);
  const bool payloadExists = StagingObject(payload, updates::kArtifactLimit);
  if (!ownerExists) { if (payloadExists) Invalid(); return; }
  std::string text;
  {
    std::unique_ptr<Handle> holder; const auto* file = OpenRead(owner, holder, kRecordLimit);
    LARGE_INTEGER length{}; if (!GetFileSizeEx(file->get(), &length)) Io();
    text.resize(static_cast<size_t>(length.QuadPart)); DWORD read = 0;
    if (!ReadFile(file->get(), text.data(), static_cast<DWORD>(text.size()), &read, nullptr) || read != text.size()) Io();
  }
  uint64_t expectedSize = 0;
  try {
    const auto body = Body(text, "SDSTAGE001");
    if (body.object().size() != 4 || !mcp::CanonicalUuid(body.at("id").string()) ||
        body.at("sid").string() != Utf8(paths_.sid)) Invalid();
    const auto target = Wide(body.at("target").string());
    if (download && target != L"pending/slot0/ServerDeckSetup.exe" && target != L"pending/slot1/ServerDeckSetup.exe") Invalid();
    const auto maximum = Artifact(target) ? updates::kArtifactLimit : RecordLimit(target);
    const auto size = body.at("size").integer();
    if (!maximum || size < 0 || static_cast<uint64_t>(size) > maximum) Invalid();
    expectedSize = static_cast<uint64_t>(size);
  } catch (...) { Invalid(); }
  if (payloadExists) {
    StagingObject(payload, expectedSize);
    { std::unique_ptr<Handle> holder; OpenRead(payload, holder, expectedSize); }
    if (!DeleteFileW(payload.c_str())) Io();
  }
  if (!DeleteFileW(owner.c_str())) Io();
}
void Files::CleanupStaging(bool removeLockForUninstall) {
  if (!std::filesystem::exists(paths_.install)) return;
  for (const bool download : {false, true}) {
    const auto lockPath = paths_.install / (download ? L".download.lock" : L".stage.lock");
    StagingObject(lockPath, 0);
    { auto slot = Acquire(lockPath, 0, "BUSY"); CleanupStagingHeld(download); }
    if (removeLockForUninstall && !DeleteFileW(ExtendedPath(lockPath).c_str())) Io();
  }
}
void Files::Stage(const std::wstring& relative, uint64_t length, const std::function<void(HANDLE)>& writer, bool download,
    const std::function<void()>& published) {
  EnsureParent(relative);
  const auto maximum = Artifact(relative) ? updates::kArtifactLimit : RecordLimit(relative);
  if (!maximum || length > maximum) Io();
  const auto lockPath = paths_.install / (download ? L".download.lock" : L".stage.lock");
  StagingObject(lockPath, 0);
  auto slot = Acquire(lockPath, 0, "BUSY");
  CleanupStagingHeld(download);
  const auto target = ExtendedPath(Path(relative));
  const auto temp = ExtendedPath(paths_.install / (download ? L".download.bin" : L".stage.bin"));
  const auto owner = ExtendedPath(paths_.install / (download ? L".download-owner.v1" : L".stage-owner.v1"));
  const auto ownership = Envelope("SDSTAGE001", Json::Object{{"id", Utf8(Uuid())},
    {"sid", Utf8(paths_.sid)}, {"target", Utf8(relative)}, {"size", static_cast<int64_t>(length)}});
  bool ownerCreated = false, payloadCreated = false;
  try {
    {
      Handle file(CreateFileW(owner.c_str(), GENERIC_WRITE | WRITE_DAC, 0, nullptr, CREATE_NEW, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
      if (!file.valid()) Io(); ownerCreated = true; SecureFileHandle(file.get()); DWORD written = 0;
      if (!WriteFile(file.get(), ownership.data(), static_cast<DWORD>(ownership.size()), &written, nullptr) ||
          written != ownership.size() || !FlushFileBuffers(file.get())) Io();
    }
    {
      Handle file(CreateFileW(temp.c_str(), GENERIC_WRITE | WRITE_DAC, 0, nullptr, CREATE_NEW, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
      if (!file.valid()) Io(); payloadCreated = true; SecureFileHandle(file.get());
      writer(file.get()); LARGE_INTEGER actual{};
      if (!GetFileSizeEx(file.get(), &actual) || static_cast<uint64_t>(actual.QuadPart) != length || !FlushFileBuffers(file.get())) Io();
    }
    RejectReparse(target);
    const DWORD flags = MOVEFILE_WRITE_THROUGH | (download ? 0 : MOVEFILE_REPLACE_EXISTING);
    if (!MoveFileExW(temp.c_str(), target.c_str(), flags)) Io();
    payloadCreated = false;
    if (published) published();
    if (!DeleteFileW(owner.c_str())) Io(); ownerCreated = false;
  } catch (...) {
    bool payloadGone = !payloadCreated;
    if (payloadCreated) {
      payloadGone = DeleteFileW(temp.c_str()) != FALSE;
      if (!payloadGone) { const auto error = GetLastError(); payloadGone = error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND; }
    }
    // Preserve the proof of ownership when a payload could not be removed.
    if (ownerCreated && payloadGone) DeleteFileW(owner.c_str());
    throw;
  }
}
void Files::WriteRecord(const std::wstring& relative, const std::string& value, const std::function<void()>& published) {
  const auto maximum = RecordLimit(relative); if (!maximum || value.size() > maximum) Io();
  if (published) {
    if (relative != L"pending/consent.v1") Io();
    Stage(relative, value.size(), [&](HANDLE file) {
      DWORD written = 0;
      if (!WriteFile(file, value.data(), static_cast<DWORD>(value.size()), &written, nullptr) || written != value.size()) Io();
    }, false, published);
  } else Write(relative, reinterpret_cast<const uint8_t*>(value.data()), value.size());
}
void Files::WriteArtifact(const std::wstring& relative, const uint8_t* bytes, size_t length) {
  if (!Artifact(relative) || !length || length > updates::kArtifactLimit || !bytes) Io();
  Write(relative, bytes, length);
}
void Files::StreamDownload(const std::wstring& relative, uint64_t length, const std::function<void(HANDLE)>& writer) {
  if ((relative != L"pending/slot0/ServerDeckSetup.exe" && relative != L"pending/slot1/ServerDeckSetup.exe") || !length ||
      length > updates::kArtifactLimit || !writer) Io();
  Stage(relative, length, writer, true);
}
Identity Files::Inspect(const std::wstring& relative) const {
  std::unique_ptr<Handle> holder; auto* file = OpenRead(Path(relative), holder, updates::kArtifactLimit);
  Digest digest; std::array<uint8_t, 65536> bytes{}; uint64_t size = 0;
  for (;;) {
    DWORD count = 0; if (!ReadFile(file->get(), bytes.data(), static_cast<DWORD>(bytes.size()), &count, nullptr)) Io();
    if (!count) break;
    if (size > updates::kArtifactLimit - count) Io(); size += count; digest.Add(bytes.data(), count);
  }
  return {size, digest.Finish()};
}
void Files::Copy(const std::wstring& source, const std::wstring& target) {
  if (!Artifact(source) || !Artifact(target)) Io();
  std::unique_ptr<Handle> holder; const auto* input = OpenRead(Path(source), holder, updates::kArtifactLimit);
  LARGE_INTEGER size{}; if (!GetFileSizeEx(input->get(), &size) || size.QuadPart <= 0) Io();
  Stage(target, static_cast<uint64_t>(size.QuadPart), [&](HANDLE output) {
    std::array<uint8_t, 65536> bytes{};
    for (;;) {
      DWORD read = 0; if (!ReadFile(input->get(), bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr)) Io();
      if (!read) break;
      DWORD written = 0; if (!WriteFile(output, bytes.data(), read, &written, nullptr) || written != read) Io();
    }
  });
}
DWORD Files::Publish(const std::wstring& candidate, const std::wstring& target) {
  if (!Artifact(candidate) || !Artifact(target) || candidate == target) Io();
  const auto from = ExtendedPath(Path(candidate)), to = ExtendedPath(Path(target));
  if (Exists(target)) {
    if (ReplaceFileW(to.c_str(), from.c_str(), nullptr, 0, nullptr, nullptr)) return ERROR_SUCCESS;
  } else if (MoveFileExW(from.c_str(), to.c_str(), MOVEFILE_WRITE_THROUGH)) return ERROR_SUCCESS;
  return GetLastError();
}
void Files::Remove(const std::wstring& relative) {
  const auto path = Path(relative);
  if (!DeleteFileW(ExtendedPath(path).c_str())) {
    const auto error = GetLastError(); if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) Io();
  }
}
uint64_t Files::FreeBytes() const {
  auto path = paths_.install;
  while (!std::filesystem::exists(path)) {
    const auto parent = path.parent_path(); if (parent == path || parent.empty()) Io(); path = parent;
  }
  RejectReparse(path); ULARGE_INTEGER available{};
  if (!GetDiskFreeSpaceExW(ExtendedPath(path).c_str(), &available, nullptr, nullptr)) Io();
  return available.QuadPart;
}
}  // namespace sd::install
