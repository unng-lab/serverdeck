#pragma once
#include "release_catalog.h"
#include "security.h"
#include <memory>
#include <optional>
#include <functional>

namespace sd::install {
constexpr size_t kRecordLimit = 8192;
struct Identity {
  uint64_t size = 0;
  std::string hash;
  bool operator==(const Identity& other) const { return size == other.size && hash == other.hash; }
};
struct Installation {
  std::string sid;
  updates::Version version;
  Identity app, setup;
  std::string consumedVersion, consumedSetupHash;
};
enum class Operation { install, update, remove };
enum class Stage { prepared, files, registered };
struct Journal {
  std::string id;
  Operation kind = Operation::install;
  Stage stage = Stage::prepared;
  std::optional<Installation> previous;
  Installation target;
};
struct Recovery {
  std::string sid;
  updates::Version version;
  Identity setup;
};
std::string EncodeInstallation(const Installation& value);
Installation DecodeInstallation(const std::string& value);
std::string EncodeJournal(const Journal& value);
Journal DecodeJournal(const std::string& value);
std::string EncodeRecovery(const Recovery& value);
Recovery DecodeRecovery(const std::string& value);

struct Observation {
  std::optional<Identity> app, setup, backupApp, backupSetup;
  bool registrationMatchesTarget = false;
};
enum class RecoveryAction { commit, rollback, discardFresh, resumeRemoval, blocked };
struct RecoveryPlan {
  RecoveryAction action = RecoveryAction::blocked;
  std::wstring appSource, setupSource;
};
RecoveryPlan PlanRecovery(const Journal& journal, const Observation& files);

struct Paths {
  std::filesystem::path install, data, programs;
  std::wstring sid;
  static Paths CurrentUser();
  void Validate() const;
};
class Lease {
 public:
  explicit Lease(const Paths& paths, bool vacantOwner, DWORD timeoutMs = 3000);
  static std::unique_ptr<Lease> Adopt(const Paths& paths, std::unique_ptr<Handle> maintenance, std::unique_ptr<Handle> owner);
  static std::unique_ptr<Lease> Resume(const Paths& paths, std::unique_ptr<Handle>& owner, DWORD timeoutMs = 3000);
  void ReleaseMaintenance() { maintenance_.reset(); }
  HANDLE maintenance() const { return maintenance_ ? maintenance_->get() : INVALID_HANDLE_VALUE; }
  HANDLE owner() const { return owner_ ? owner_->get() : INVALID_HANDLE_VALUE; }
  std::unique_ptr<Handle> TakeOwner() { return std::move(owner_); }
  bool Owns(const Paths& paths, bool vacantOwner) const;
 private:
  Lease(Paths paths, std::unique_ptr<Handle> maintenance, std::unique_ptr<Handle> owner);
  Paths paths_;
  std::unique_ptr<Handle> maintenance_, owner_;
};

// Internal adapter: relative names are a closed manifest allowlist. Production
// callers use CurrentUser(); tests inject roots confined to their own temp tree.
class Files {
 public:
  explicit Files(Paths paths);
  const Paths& roots() const { return paths_; }
  std::filesystem::path Path(const std::wstring& relative) const;
  bool Exists(const std::wstring& relative) const;
  std::string ReadRecord(const std::wstring& relative) const;
  // Pending consent alone may report its successful durable rename before
  // fallible staging cleanup. The notification is synchronous.
  void WriteRecord(const std::wstring& relative, const std::string& value, const std::function<void()>& published = {});
  void WriteArtifact(const std::wstring& relative, const uint8_t* bytes, size_t length);
  void StreamDownload(const std::wstring& relative, uint64_t length, const std::function<void(HANDLE)>& writer);
  Identity Inspect(const std::wstring& relative) const;
  void Copy(const std::wstring& source, const std::wstring& target);
  DWORD Publish(const std::wstring& candidate, const std::wstring& target);
  void Remove(const std::wstring& relative);
  void CleanupStaging(bool removeLockForUninstall = false);
  uint64_t FreeBytes() const;
 private:
  void EnsureParent(const std::wstring& relative);
  void Write(const std::wstring& relative, const uint8_t* bytes, size_t length);
  void Stage(const std::wstring& relative, uint64_t length, const std::function<void(HANDLE)>& writer, bool download = false,
             const std::function<void()>& published = {});
  void CleanupStagingHeld(bool download = false);
  Paths paths_;
};
}  // namespace sd::install
