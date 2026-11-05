#pragma once
#include "artifact_transfer.h"
#include "install_executor.h"
#include <mutex>

namespace sd::updates {
struct PendingConsent {
  std::string id, sid;
  unsigned slot = 0;
  Version version;
  install::Identity app, setup;
  std::string catalogHash;
  uint64_t verifiedAt = 0;
};
std::string EncodePending(const PendingConsent& value);
PendingConsent DecodePending(const std::string& bytes);
struct PendingRetirement { PendingConsent consent; std::string reason; };
struct PendingDeferral { PendingConsent consent; std::string attempt, code; bool consumed = false; };
struct PendingNotice { std::string version, code; };
std::string EncodeRetirement(const PendingRetirement& value);
PendingRetirement DecodeRetirement(const std::string& bytes);
std::string EncodeDeferral(const PendingDeferral& value);
PendingDeferral DecodeDeferral(const std::string& bytes);
std::wstring PendingPath(unsigned slot, const wchar_t* file);
struct PendingUpdate {
  PendingConsent consent;
  Release release;
  std::string catalog;
};
// The GUI owner is the sole downloader. Call on its worker; drain it before
// owner authority is released. Commit must arbitrate cancellation and the ready
// snapshot under the service mutex, invoking the provided write synchronously
// exactly once. The callback must not escape this call.
// The write calls `published` at the actual durable rename, before cleanup can
// throw. The service must mark committed/ready there under its same mutex.
using PendingWrite = std::function<void(const std::function<void()>& published)>;
using PendingCommit = std::function<void(const PendingWrite&)>;
struct PendingPersistence {
  virtual ~PendingPersistence() = default;
  virtual std::optional<PendingUpdate> Restore() = 0;
  // Read on the same serialized worker immediately after Restore.
  virtual PendingNotice Notice() const { return {}; }
  virtual PendingUpdate Download(const Release& release, const std::string& catalog, uint64_t verifiedAt,
      ArtifactTransport& transport, const std::atomic<bool>& cancel, const PendingCommit& commit, ArtifactProgress progress = {}) = 0;
};
class PendingStore : public PendingPersistence {
 public:
  PendingStore(install::Paths paths, Policy policy, install::SetupValidator validator, install::Checkpoint checkpoint = {});
  std::optional<PendingUpdate> Read(install::Lease& maintenance);
  std::optional<PendingUpdate> Restore() override;
  PendingNotice Notice() const override { return notice_; }
  std::optional<PendingUpdate> PrepareStartup(install::Lease& lease, const install::Installation& installed, bool allowOffer = true);
  void DeferOnce(install::Lease& lease, const PendingConsent& consent, const std::string& code, const std::string& attempt);
  bool ConsumeDeferOnce(install::Lease& lease, const std::function<void(const std::string&)>& latch);
  bool CleanupRetired(install::Lease& lease);
  PendingUpdate Download(const Release& release, const std::string& catalog, uint64_t verifiedAt,
                         ArtifactTransport& transport, const std::atomic<bool>& cancel,
                         const PendingCommit& commit, ArtifactProgress progress = {}) override;
  void CleanupInactive(install::Lease& maintenance, unsigned slot);
 private:
  void Guard(install::Lease& maintenance) const;
  void CheckSid(const PendingConsent& consent) const;
  PendingUpdate ReadSlot(const PendingConsent& consent);
  std::optional<std::string> ActiveBytes() const;
  std::optional<PendingRetirement> Retirement() const;
  std::optional<PendingDeferral> Deferral() const;
  void Point(const char* stage) const;
  install::Files files_;
  Policy policy_;
  install::SetupValidator validateSetup_;
  install::Checkpoint checkpoint_;
  std::mutex writer_;
  PendingNotice notice_;
};
}  // namespace sd::updates
