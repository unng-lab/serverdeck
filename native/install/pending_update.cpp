#include "pending_update.h"
#include "mcp_json.h"
#include <limits>

namespace sd::updates {
namespace {
[[noreturn]] void Invalid() { throw Failure("RECOVERY_REQUIRED"); }
std::string Hash(const std::string& bytes) { return sd::Sha256(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size()); }
bool IsHash(const std::string& hash) { return hash.size() == 64 && hash.find_first_not_of("0123456789abcdef") == std::string::npos; }
void Validate(const PendingConsent& value) {
  install::EncodeInstallation({value.sid, value.version, value.app, value.setup, {}, {}});
  if (!mcp::CanonicalUuid(value.id) || value.slot > 1 || !IsHash(value.catalogHash) ||
      value.verifiedAt > static_cast<uint64_t>(std::numeric_limits<int64_t>::max())) Invalid();
}
void Cancelled(const std::atomic<bool>& cancel) { if (cancel.load()) throw Failure("CANCELLED"); }
Release Original(const PendingConsent& consent, const std::string& catalog, const Policy& policy) {
  if (catalog.size() > kCatalogLimit || Hash(catalog) != consent.catalogHash) Invalid();
  const auto parsed = ParseCatalog(catalog, policy, consent.verifiedAt);
  for (const auto& release : parsed.releases) if (release.version == consent.version) {
    if (!Compatible(release, policy) || release.appSize != consent.app.size || release.appHash != consent.app.hash ||
        release.setupSize != consent.setup.size || release.setupHash != consent.setup.hash) Invalid();
    return release;
  }
  Invalid();
}
}
std::string EncodePending(const PendingConsent& value) {
  Validate(value);
  const auto text = "SDPENDING001\n" + mcp::Encode(mcp::Json::Object{
    {"id", value.id}, {"sid", value.sid}, {"slot", static_cast<int64_t>(value.slot)},
    {"version", value.version.text}, {"appSize", static_cast<int64_t>(value.app.size)}, {"appHash", value.app.hash},
    {"setupSize", static_cast<int64_t>(value.setup.size)}, {"setupHash", value.setup.hash},
    {"catalogHash", value.catalogHash}, {"verifiedAt", static_cast<int64_t>(value.verifiedAt)}}) + '\n';
  if (text.size() > install::kRecordLimit) Invalid(); return text;
}
PendingConsent DecodePending(const std::string& bytes) {
  try {
    const std::string prefix = "SDPENDING001\n";
    if (bytes.size() > install::kRecordLimit || bytes.size() <= prefix.size() || bytes.rfind(prefix, 0) != 0 || bytes.back() != '\n' ||
        bytes.find('\r') != std::string::npos || bytes.find('\0') != std::string::npos) Invalid();
    const auto json = mcp::Decode(bytes.substr(prefix.size(), bytes.size() - prefix.size() - 1));
    if (json.object().size() != 10) Invalid();
    const auto slot = json.at("slot").integer(), at = json.at("verifiedAt").integer();
    const auto appSize = json.at("appSize").integer(), setupSize = json.at("setupSize").integer();
    if (slot < 0 || slot > 1 || at < 0 || appSize <= 0 || setupSize <= 0) Invalid();
    PendingConsent value{json.at("id").string(), json.at("sid").string(), static_cast<unsigned>(slot),
      ParseVersion(json.at("version").string()), {static_cast<uint64_t>(appSize), json.at("appHash").string()},
      {static_cast<uint64_t>(setupSize), json.at("setupHash").string()}, json.at("catalogHash").string(), static_cast<uint64_t>(at)};
    Validate(value); return value;
  } catch (...) { Invalid(); }
}
std::wstring PendingPath(unsigned slot, const wchar_t* file) {
  if (slot > 1 || !file || (std::wstring(file) != L"ServerDeckSetup.exe" && std::wstring(file) != L"catalog.v1" && std::wstring(file) != L"owner.v1")) Invalid();
  return L"pending/slot" + std::to_wstring(slot) + L"/" + file;
}
PendingStore::PendingStore(install::Paths paths, Policy policy, install::SetupValidator validator, install::Checkpoint checkpoint)
    : files_(std::move(paths)), policy_(std::move(policy)), validateSetup_(std::move(validator)), checkpoint_(std::move(checkpoint)) {
  if (!validateSetup_) Invalid();
}
void PendingStore::Guard(install::Lease& lease) const {
  if (!lease.Owns(files_.roots(), false)) throw Failure("BUSY");
}
void PendingStore::CheckSid(const PendingConsent& value) const { if (value.sid != sd::Utf8(files_.roots().sid)) Invalid(); }
void PendingStore::Point(const char* stage) const { if (checkpoint_) checkpoint_(stage); }
std::optional<std::string> PendingStore::ActiveBytes() const {
  return files_.Exists(L"pending/consent.v1") ? std::optional<std::string>{files_.ReadRecord(L"pending/consent.v1")} : std::nullopt;
}
PendingUpdate PendingStore::ReadSlot(const PendingConsent& value) {
  CheckSid(value);
  const auto owner = PendingPath(value.slot, L"owner.v1"), setup = PendingPath(value.slot, L"ServerDeckSetup.exe"), catalog = PendingPath(value.slot, L"catalog.v1");
  if (!files_.Exists(owner) || EncodePending(DecodePending(files_.ReadRecord(owner))) != EncodePending(value) ||
      !files_.Exists(setup) || !files_.Exists(catalog) || !(files_.Inspect(setup) == value.setup)) Invalid();
  const auto bytes = files_.ReadRecord(catalog); const auto release = Original(value, bytes, policy_);
  validateSetup_(files_.Path(setup), value.version, value.app);
  return {value, release, bytes};
}
std::optional<PendingUpdate> PendingStore::Read(install::Lease& lease) {
  Guard(lease); notice_ = {}; const auto bytes = ActiveBytes();
  const auto retired = Retirement();
  if (retired && retired->reason == "changed") notice_ = {retired->consent.version.text, "SOURCE_CHANGED"};
  if (!bytes) return {};
  const auto consent = DecodePending(*bytes); CheckSid(consent);
  if (retired && EncodePending(retired->consent) == EncodePending(consent)) return {};
  notice_ = {};
  auto result = ReadSlot(consent);
  if (const auto deferred = Deferral(); deferred && EncodePending(deferred->consent) == EncodePending(consent))
    notice_ = {consent.version.text, deferred->code};
  return result;
}
std::optional<PendingUpdate> PendingStore::Restore() {
  install::Lease maintenance(files_.roots(), false); return Read(maintenance);
}
void PendingStore::CleanupInactive(install::Lease& lease, unsigned slot) {
  Guard(lease); const auto owner = PendingPath(slot, L"owner.v1");
  if (const auto bytes = ActiveBytes()) { const auto active = DecodePending(*bytes); CheckSid(active); if (active.slot == slot) throw Failure("BUSY"); }
  const auto setup = PendingPath(slot, L"ServerDeckSetup.exe"), catalog = PendingPath(slot, L"catalog.v1");
  if (!files_.Exists(owner)) { if (files_.Exists(setup) || files_.Exists(catalog)) Invalid(); return; }
  const auto value = DecodePending(files_.ReadRecord(owner)); CheckSid(value); if (value.slot != slot) Invalid();
  if (files_.Exists(setup) && !(files_.Inspect(setup) == value.setup)) Invalid();
  if (files_.Exists(catalog) && Hash(files_.ReadRecord(catalog)) != value.catalogHash) Invalid();
  files_.Remove(setup); files_.Remove(catalog); files_.Remove(owner);
}
PendingUpdate PendingStore::Download(const Release& release, const std::string& catalog, uint64_t verifiedAt,
    ArtifactTransport& transport, const std::atomic<bool>& cancel, const PendingCommit& commit, ArtifactProgress progress) {
  std::unique_lock<std::mutex> writer(writer_, std::try_to_lock); if (!writer.owns_lock()) throw Failure("BUSY");
  if (!commit) Invalid(); Cancelled(cancel);
  if (catalog.size() > kCatalogLimit) throw Failure("INVALID_CATALOG");
  PendingConsent value{sd::Utf8(sd::Uuid()), sd::Utf8(files_.roots().sid), 0, release.version,
    {release.appSize, release.appHash}, {release.setupSize, release.setupHash}, Hash(catalog), verifiedAt};
  Validate(value); const auto authenticated = Original(value, catalog, policy_);
  if (!SameIdentity(authenticated, release)) throw Failure("SOURCE_CHANGED");
  std::optional<std::string> previous;
  {
    install::Lease maintenance(files_.roots(), false);
    const auto active = Read(maintenance); previous = ActiveBytes();
    if (active) {
      value.slot = 1 - active->consent.slot;
      if (active->release.version == release.version && !SameIdentity(active->release, release)) throw Failure("SOURCE_CHANGED");
    }
    Cancelled(cancel);
    if (files_.FreeBytes() < release.setupSize + 64ull * 1024 * 1024) throw Failure("DISK_SPACE");
    CleanupInactive(maintenance, value.slot);
    files_.WriteRecord(PendingPath(value.slot, L"owner.v1"), EncodePending(value)); Point("pending-owner");
  }
  const auto consentBytes = EncodePending(value);
  try {
    Cancelled(cancel);
    files_.StreamDownload(PendingPath(value.slot, L"ServerDeckSetup.exe"), release.setupSize, [&](HANDLE file) {
      TransferArtifact(policy_, release, transport, cancel, [&](const uint8_t* bytes, size_t count) {
        DWORD written = 0;
        if (!WriteFile(file, bytes, static_cast<DWORD>(count), &written, nullptr) || written != count) throw Failure("STORAGE_IO");
      }, std::move(progress));
    }); Point("pending-setup");
    Cancelled(cancel);
    validateSetup_(files_.Path(PendingPath(value.slot, L"ServerDeckSetup.exe")), value.version, value.app);
    files_.WriteRecord(PendingPath(value.slot, L"catalog.v1"), catalog); Point("pending-catalog");
    install::Lease maintenance(files_.roots(), false);
    if (ActiveBytes() != previous) throw Failure("SOURCE_CHANGED");
    const auto ready = ReadSlot(value); Point("pending-verified"); Cancelled(cancel);
    commit([&](const std::function<void()>& published) {
      if (!published) Invalid(); Cancelled(cancel);
      files_.WriteRecord(L"pending/consent.v1", consentBytes, published);
    });
    if (ActiveBytes() != std::optional<std::string>{consentBytes}) Invalid();
    Point("pending-committed"); return ready;
  } catch (const std::exception&) {
    install::Lease maintenance(files_.roots(), false);
    if (ActiveBytes() == std::optional<std::string>{consentBytes}) return ReadSlot(value);
    CleanupInactive(maintenance, value.slot);
    throw;
  }
}
}  // namespace sd::updates
