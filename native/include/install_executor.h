#pragma once
#include "installation.h"

namespace sd::install {
struct Bytes { const uint8_t* data = nullptr; size_t size = 0; };
struct Package { updates::Version version; Bytes app, setup; };
struct Registration {
  virtual ~Registration() = default;
  virtual void CheckOwnership() = 0;
  virtual void SetRecoveryLink() = 0;
  virtual void Set(const Installation& record) = 0;
  virtual bool Matches(const Installation& record) = 0;
  virtual void Remove() = 0;
  virtual void RemoveRecoveryLink() = 0;
};
enum class InstallResult { cancelled, installed, repaired };
// Empty app identity requests internal resource validation of a recovery image
// whose complete setup identity was already checked against its SID-bound marker.
using SetupValidator = std::function<void(const std::filesystem::path&, const updates::Version&, const Identity&)>;
using Checkpoint = std::function<void(const char*)>;
class Executor {
 public:
  Executor(Files& files, Lease& lease, Registration& registration, SetupValidator validateSetup, Checkpoint checkpoint = {});
  std::optional<Installation> Current();
  // Before GUI owner publication/payload extraction: recover the transaction,
  // reject ambiguous staging, verify canonical files/commit and setup resources.
  Installation PrepareStartup();
  void Recover();
  InstallResult Repair();
  InstallResult Apply(const Package& package, bool confirmed, const updates::Release* consented = nullptr);
 private:
  void Guard() const;
  void Point(const char* stage) const;
  void CheckSid(const Installation& record) const;
  bool Matches(const std::wstring& path, const Identity& identity);
  bool Committed(const Installation& record);
  void Commit(const Installation& record, const std::string& id);
  void CleanupTransaction();
  void PrepareRecovery(const std::optional<Installation>& previous, const Package& package, const Installation& target);
  Files& files_;
  Lease& lease_;
  Registration& registration_;
  SetupValidator validateSetup_;
  Checkpoint checkpoint_;
};
}  // namespace sd::install
