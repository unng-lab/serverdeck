#pragma once
#include "release_catalog.h"
#include "installation.h"
#include "pending_update.h"
#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <thread>

namespace sd::updates {
struct Preferences {
  bool enabled = true;
  std::optional<uint64_t> lastAttempt, lastSuccess, deferredUntil;
};
std::string EncodePreferences(const Preferences& value);
Preferences DecodePreferences(const std::string& bytes);
struct PreferenceStore {
  virtual ~PreferenceStore() = default;
  virtual Preferences Load() = 0;
  virtual void Save(const Preferences& value) = 0;
};
std::unique_ptr<PreferenceStore> MakeFilePreferenceStore(const install::Paths& paths);
struct Snapshot {
  std::string state = "idle", code;
  Version current;
  std::optional<Release> offer;
  uint64_t bytes = 0;
  std::optional<uint64_t> total;
  Preferences preferences;
  std::string preparedVersion, preparedCode;
};
// Private native transport; no caller-supplied URL is exposed by the platform API.
struct CatalogSource {
  virtual ~CatalogSource() = default;
  virtual std::string Fetch(const std::atomic<bool>& cancelled) = 0;
  virtual std::string FetchFor(const Release&, const std::atomic<bool>& cancelled) { return Fetch(cancelled); }
};
std::unique_ptr<CatalogSource> MakeWinHttpCatalogSource(const Policy& policy, const Version& current);

class UpdateService {
 public:
  using Clock = std::function<uint64_t()>;
  UpdateService(std::optional<Policy> policy, Version current, PreferenceStore& store,
                CatalogSource* source = nullptr, Clock clock = {}, PendingPersistence* pending = nullptr,
                ArtifactTransport* artifacts = nullptr, std::optional<install::Installation> installed = {});
  ~UpdateService();
  Snapshot Read() const;
  bool Check(); // Manual operation; enabled restricts the Dart automatic scheduler only.
  bool Download(const std::string& version);
  void Cancel();
  void SetEnabled(bool enabled);
  void Defer();
  void StopAdmission();
  void Drain();
  bool TryDrain(); // Window-thread safe poll; joins only an already terminated worker.
 private:
  void Run(uint64_t generation);
  void RestoreWorker(uint64_t generation);
  void LoadPrepared(uint64_t generation);
  void DownloadWorker(uint64_t generation, Release release, std::string catalog);
  void Launch(std::function<void()> work);
  void ProjectPrepared(); // mutex held
  void Finish(uint64_t generation, const std::function<void(Snapshot&)>& change);
  std::optional<Policy> policy_;
  PreferenceStore& store_;
  std::unique_ptr<CatalogSource> ownedSource_;
  CatalogSource* source_ = nullptr;
  Clock clock_;
  PendingPersistence* pending_ = nullptr;
  std::unique_ptr<ArtifactTransport> ownedArtifacts_;
  ArtifactTransport* artifacts_ = nullptr;
  std::optional<install::Installation> installed_;
  std::optional<PendingUpdate> prepared_;
  PendingNotice startupNotice_;
  std::optional<Catalog> catalog_;
  bool restored_ = true, committed_ = false;
  mutable std::mutex mutex_;
  std::mutex command_;
  Snapshot snapshot_;
  std::thread worker_;
  std::atomic<bool> cancelled_{false};
  bool stopped_ = false, busy_ = false;
  uint64_t generation_ = 0;
};
// A successful fresh request is mandatory for each apply attempt; cached signed
// metadata authenticates consent, but never supplies freshness at this boundary.
Release Revalidate(CatalogSource& source, const Policy& policy, const Release& consent,
                   const std::atomic<bool>& cancelled, UpdateService::Clock clock = {});
}  // namespace sd::updates
