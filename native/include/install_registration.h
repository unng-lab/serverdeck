#pragma once
#include "install_executor.h"
#include <map>

namespace sd::install {
struct RegistrationValues {
  std::map<std::wstring, std::wstring> strings;
  std::map<std::wstring, DWORD> dwords;
  std::filesystem::path shortcut, recoveryShortcut, application, setup, recovery;
};
RegistrationValues ProjectRegistration(const Paths& paths, const Installation& record);
struct RegistryPort {
  virtual ~RegistryPort() = default;
  virtual bool Exists() = 0;
  virtual std::optional<std::wstring> String(const std::wstring& name) = 0;
  virtual std::optional<DWORD> Dword(const std::wstring& name) = 0;
  virtual void SetString(const std::wstring& name, const std::wstring& value) = 0;
  virtual void SetDword(const std::wstring& name, DWORD value) = 0;
  virtual void Flush() = 0;
  virtual void Remove() = 0;
};
struct ShortcutPort {
  virtual ~ShortcutPort() = default;
  virtual bool Exists(const std::filesystem::path& path) = 0;
  virtual bool Matches(const std::filesystem::path& path, const std::filesystem::path& target, const wchar_t* arguments) = 0;
  virtual void Save(const std::filesystem::path& path, const std::filesystem::path& target, const wchar_t* arguments) = 0;
  virtual void Remove(const std::filesystem::path& path) = 0;
};
class WindowsRegistration final : public Registration {
 public:
  explicit WindowsRegistration(Paths paths, RegistryPort* registry = nullptr, ShortcutPort* shortcuts = nullptr);
  void CheckOwnership() override;
  void SetRecoveryLink() override;
  void Set(const Installation& record) override;
  bool Matches(const Installation& record) override;
  void Remove() override;
  void RemoveRecoveryLink() override;
  void SetRemovalRetry(const Installation& record, const std::filesystem::path& markedHelper);
 private:
  bool JournalEvidence() const;
  bool RecoveryEvidence() const;
  Paths paths_;
  std::unique_ptr<RegistryPort> ownRegistry_;
  std::unique_ptr<ShortcutPort> ownShortcuts_;
  RegistryPort* registry_ = nullptr;
  ShortcutPort* shortcuts_ = nullptr;
};
}  // namespace sd::install
