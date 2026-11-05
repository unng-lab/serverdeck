#include "pending_update.h"
#include "mcp_json.h"

namespace sd::updates {
namespace {
[[noreturn]] void Invalid() { throw Failure("RECOVERY_REQUIRED"); }
bool Same(const PendingConsent& a, const PendingConsent& b) { return EncodePending(a) == EncodePending(b); }
bool Code(const std::string& code) {
  for (const auto* allowed : {"UPDATE_NOT_CONFIGURED", "NETWORK_UNAVAILABLE", "TIMEOUT", "CANCELLED", "SOURCE_UNTRUSTED",
      "SOURCE_EXPIRED", "SOURCE_CHANGED", "RELEASE_REVOKED", "RELEASE_INCOMPATIBLE", "INVALID_CATALOG", "INVALID_ARTIFACT",
      "DISK_SPACE", "OWNER_RUNNING", "BUSY", "STORAGE_IO", "RECOVERY_REQUIRED"}) if (code == allowed) return true;
  return false;
}
std::string Envelope(const char* prefix, mcp::Json::Object fields) {
  const auto result = std::string(prefix) + '\n' + mcp::Encode(fields) + '\n';
  if (result.size() > install::kRecordLimit) Invalid(); return result;
}
mcp::Json Body(const std::string& bytes, const std::string& prefix, size_t fields) {
  if (bytes.size() > install::kRecordLimit || bytes.size() <= prefix.size() + 1 || bytes.rfind(prefix + '\n', 0) ||
      bytes.back() != '\n' || bytes.find('\r') != std::string::npos || bytes.find('\0') != std::string::npos) Invalid();
  auto body = mcp::Decode(bytes.substr(prefix.size() + 1)); if (body.object().size() != fields) Invalid(); return body;
}
}
std::string EncodeRetirement(const PendingRetirement& value) {
  if (value.reason != "consumed" && value.reason != "superseded" && value.reason != "changed") Invalid();
  return Envelope("SDRETIRED001", {{"consent", EncodePending(value.consent)}, {"reason", value.reason}});
}
PendingRetirement DecodeRetirement(const std::string& bytes) {
  try {
    const auto body = Body(bytes, "SDRETIRED001", 2);
    PendingRetirement value{DecodePending(body.at("consent").string()), body.at("reason").string()};
    if (EncodeRetirement(value) != bytes) Invalid(); return value;
  } catch (...) { Invalid(); }
}
std::string EncodeDeferral(const PendingDeferral& value) {
  if (!mcp::CanonicalUuid(value.attempt) || !Code(value.code)) Invalid();
  return Envelope("SDDEFER001", {{"consent", EncodePending(value.consent)}, {"attempt", value.attempt},
    {"code", value.code}, {"consumed", value.consumed}});
}
PendingDeferral DecodeDeferral(const std::string& bytes) {
  try {
    const auto body = Body(bytes, "SDDEFER001", 4);
    PendingDeferral value{DecodePending(body.at("consent").string()), body.at("attempt").string(), body.at("code").string(),
      std::get<bool>(body.at("consumed").value)}; if (EncodeDeferral(value) != bytes) Invalid(); return value;
  } catch (...) { Invalid(); }
}
std::optional<PendingRetirement> PendingStore::Retirement() const {
  if (!files_.Exists(L"pending/tombstone.v1")) return {};
  auto value = DecodeRetirement(files_.ReadRecord(L"pending/tombstone.v1")); CheckSid(value.consent); return value;
}
std::optional<PendingDeferral> PendingStore::Deferral() const {
  if (!files_.Exists(L"pending/defer-once.v1")) return {};
  auto value = DecodeDeferral(files_.ReadRecord(L"pending/defer-once.v1")); CheckSid(value.consent); return value;
}
void PendingStore::DeferOnce(install::Lease& lease, const PendingConsent& consent, const std::string& code, const std::string& attempt) {
  Guard(lease); if (!lease.Owns(files_.roots(), true)) throw Failure("OWNER_RUNNING"); CheckSid(consent);
  const auto active = ActiveBytes(); if (!active || !Same(DecodePending(*active), consent)) throw Failure("SOURCE_CHANGED");
  if (const auto retired = Retirement(); retired && Same(retired->consent, consent)) throw Failure("SOURCE_CHANGED");
  files_.WriteRecord(L"pending/defer-once.v1", EncodeDeferral({consent, attempt, code, false})); Point("defer-written");
}
bool PendingStore::ConsumeDeferOnce(install::Lease& lease, const std::function<void(const std::string&)>& latch) {
  Guard(lease); if (!lease.Owns(files_.roots(), true) || !latch) throw Failure("OWNER_RUNNING");
  auto value = Deferral(); if (!value) return false;
  const auto active = ActiveBytes();
  if (!active || !Same(DecodePending(*active), value->consent)) { files_.Remove(L"pending/defer-once.v1"); return false; }
  if (value->consumed) return false;
  // Latch the entire invocation before fallible publication/marker cleanup, so
  // a retry of startup cannot immediately invoke the same failing helper.
  latch(value->code); value->consumed = true;
  files_.WriteRecord(L"pending/defer-once.v1", EncodeDeferral(*value)); Point("defer-consumed"); return true;
}
bool PendingStore::CleanupRetired(install::Lease& lease) {
  Guard(lease); const auto retired = Retirement(); if (!retired) return true;
  try {
    if (const auto active = ActiveBytes()) {
      const auto current = DecodePending(*active); CheckSid(current);
      if (Same(current, retired->consent)) { files_.Remove(L"pending/consent.v1"); Point("retired-detached"); }
      else if (current.slot == retired->consent.slot) { files_.Remove(L"pending/tombstone.v1"); return true; }
    }
    const auto owner = PendingPath(retired->consent.slot, L"owner.v1");
    if (files_.Exists(owner)) {
      const auto current = DecodePending(files_.ReadRecord(owner)); CheckSid(current);
      if (!Same(current, retired->consent)) { files_.Remove(L"pending/tombstone.v1"); return true; }
    }
    CleanupInactive(lease, retired->consent.slot); Point("retired-files-cleaned");
    if (const auto deferred = Deferral(); deferred && Same(deferred->consent, retired->consent)) files_.Remove(L"pending/defer-once.v1");
    // A same-version mismatch remains visible until a new consent replaces it.
    if (retired->reason != "changed") files_.Remove(L"pending/tombstone.v1");
    return true;
  } catch (const Failure& error) {
    if (std::string(error.what()) == "STORAGE_IO") return false;
    throw;
  }
}
std::optional<PendingUpdate> PendingStore::PrepareStartup(install::Lease& lease, const install::Installation& installed, bool allowOffer) {
  Guard(lease); if (!lease.Owns(files_.roots(), true)) throw Failure("OWNER_RUNNING");
  install::EncodeInstallation(installed); if (installed.sid != sd::Utf8(files_.roots().sid)) Invalid();
  if (auto retired = Retirement(); retired && retired->reason == "changed" && retired->consent.version < installed.version) {
    retired->reason = "superseded"; files_.WriteRecord(L"pending/tombstone.v1", EncodeRetirement(*retired));
  }
  CleanupRetired(lease);
  const auto bytes = ActiveBytes(); if (!bytes) return Read(lease);
  const auto consent = DecodePending(*bytes); CheckSid(consent);
  if (installed.version < consent.version) return allowOffer ? Read(lease) : std::nullopt;
  const auto owner = PendingPath(consent.slot, L"owner.v1");
  if (!files_.Exists(owner) || !Same(DecodePending(files_.ReadRecord(owner)), consent)) Invalid();
  const auto reason = consent.version < installed.version ? "superseded" :
    consent.setup == installed.setup && consent.app == installed.app ? "consumed" : "changed";
  files_.WriteRecord(L"pending/tombstone.v1", EncodeRetirement({consent, reason})); Point("pending-retired");
  CleanupRetired(lease); return Read(lease);
}
}  // namespace sd::updates
