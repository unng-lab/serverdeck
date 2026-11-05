#include "install_registration.h"
#include "uninstall.h"
#include <shobjidl.h>
#include <shlguid.h>
#include <shlobj.h>
#include <array>

namespace sd::install {
namespace {
constexpr wchar_t kKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\ServerDeck";
[[noreturn]] void Io() { throw updates::Failure("STORAGE_IO"); }
[[noreturn]] void Foreign() { throw updates::Failure("RECOVERY_REQUIRED"); }
std::wstring Quote(const std::filesystem::path& path) { return L"\"" + path.wstring() + L"\""; }
bool Equal(const std::wstring& a, const std::wstring& b) {
  return CompareStringOrdinal(a.c_str(), -1, b.c_str(), -1, TRUE) == CSTR_EQUAL;
}
struct Com {
  HRESULT result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  Com() { if (FAILED(result)) Io(); }
  ~Com() { CoUninitialize(); }
};
template<class T> struct Pointer {
  T* value = nullptr;
  ~Pointer() { if (value) value->Release(); }
};
struct Key { HKEY value = nullptr; ~Key() { if (value) RegCloseKey(value); } };
bool OpenKey(Key& key, REGSAM access) {
  const auto result = RegOpenKeyExW(HKEY_CURRENT_USER, kKey, 0, access | KEY_WOW64_64KEY, &key.value);
  if (result == ERROR_FILE_NOT_FOUND || result == ERROR_PATH_NOT_FOUND) return false;
  if (result != ERROR_SUCCESS) Io(); return true;
}
std::optional<std::wstring> ReadString(HKEY key, const std::wstring& name) {
  return ReadRegistryString([&](void* buffer, DWORD* bytes) {
    return RegGetValueW(key, nullptr, name.c_str(), RRF_RT_REG_SZ, nullptr, buffer, bytes);
  });
}
bool LinkMatches(const std::filesystem::path& path, const std::filesystem::path& target, const wchar_t* arguments) {
  RejectReparse(path);
  if (!std::filesystem::exists(path)) return false;
  if (!std::filesystem::is_regular_file(path) || std::filesystem::file_size(path) > 65536) return false;
  Com com; Pointer<IShellLinkW> link;
  if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link.value)))) Io();
  Pointer<IPersistFile> persist; if (FAILED(link.value->QueryInterface(IID_PPV_ARGS(&persist.value)))) Io();
  if (FAILED(persist.value->Load(path.c_str(), STGM_READ))) return false;
  std::array<wchar_t, 32768> actual{}, args{};
  if (FAILED(link.value->GetPath(actual.data(), static_cast<int>(actual.size()), nullptr, SLGP_RAWPATH)) ||
      FAILED(link.value->GetArguments(args.data(), static_cast<int>(args.size())))) return false;
  return Equal(actual.data(), target.wstring()) && std::wstring(args.data()) == arguments;
}
void SaveLink(const std::filesystem::path& path, const std::filesystem::path& target, const wchar_t* arguments) {
  RejectReparse(path); RejectReparse(target);
  if (!std::filesystem::exists(path.parent_path())) {
    const auto result = SHCreateDirectoryExW(nullptr, path.parent_path().c_str(), nullptr);
    if (result != ERROR_SUCCESS && result != ERROR_ALREADY_EXISTS && result != ERROR_FILE_EXISTS) Io();
    RejectReparse(path.parent_path());
  }
  Com com; Pointer<IShellLinkW> link;
  if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link.value)))) Io();
  const auto working = target.parent_path().wstring();
  if (FAILED(link.value->SetPath(target.c_str())) || FAILED(link.value->SetArguments(arguments)) ||
      FAILED(link.value->SetWorkingDirectory(working.c_str())) || FAILED(link.value->SetDescription(L"ServerDeck"))) Io();
  Pointer<IPersistFile> persist; if (FAILED(link.value->QueryInterface(IID_PPV_ARGS(&persist.value))) ||
      FAILED(persist.value->Save(path.c_str(), TRUE))) Io();
  FlushFile(path);
  if (!LinkMatches(path, target, arguments)) Io();
}
void RemoveLink(const std::filesystem::path& path) {
  RejectReparse(path);
  if (!DeleteFileW(ExtendedPath(path).c_str())) {
    const auto error = GetLastError(); if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) Io();
  }
}
class NativeRegistry final : public RegistryPort {
 public:
  bool Exists() override { Key key; return OpenKey(key, KEY_QUERY_VALUE); }
  std::optional<std::wstring> String(const std::wstring& name) override {
    Key key; if (!OpenKey(key, KEY_QUERY_VALUE)) return {}; return ReadString(key.value, name);
  }
  std::optional<DWORD> Dword(const std::wstring& name) override {
    Key key; if (!OpenKey(key, KEY_QUERY_VALUE)) return {};
    DWORD value = 0, size = sizeof(value);
    const auto result = RegGetValueW(key.value, nullptr, name.c_str(), RRF_RT_REG_DWORD, nullptr, &value, &size);
    if (result == ERROR_FILE_NOT_FOUND) return {}; if (result != ERROR_SUCCESS) Io(); return value;
  }
  void SetString(const std::wstring& name, const std::wstring& value) override {
    Key key; Create(key);
    if (RegSetValueExW(key.value, name.c_str(), 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
        static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) != ERROR_SUCCESS) Io();
  }
  void SetDword(const std::wstring& name, DWORD value) override {
    Key key; Create(key);
    if (RegSetValueExW(key.value, name.c_str(), 0, REG_DWORD, reinterpret_cast<const BYTE*>(&value), sizeof(value)) != ERROR_SUCCESS) Io();
  }
  void Flush() override { Key key; if (OpenKey(key, KEY_QUERY_VALUE) && RegFlushKey(key.value) != ERROR_SUCCESS) Io(); }
  void Remove() override {
    const auto result = RegDeleteTreeW(HKEY_CURRENT_USER, kKey);
    if (result != ERROR_SUCCESS && result != ERROR_FILE_NOT_FOUND && result != ERROR_PATH_NOT_FOUND) Io();
  }
 private:
  static void Create(Key& key) {
    DWORD disposition = 0;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kKey, 0, nullptr, 0, KEY_SET_VALUE | KEY_QUERY_VALUE | KEY_WOW64_64KEY,
        nullptr, &key.value, &disposition) != ERROR_SUCCESS) Io();
  }
};
class NativeShortcuts final : public ShortcutPort {
 public:
  bool Exists(const std::filesystem::path& path) override { RejectReparse(path); return std::filesystem::exists(path); }
  bool Matches(const std::filesystem::path& path, const std::filesystem::path& target, const wchar_t* arguments) override { return LinkMatches(path, target, arguments); }
  void Save(const std::filesystem::path& path, const std::filesystem::path& target, const wchar_t* arguments) override { SaveLink(path, target, arguments); }
  void Remove(const std::filesystem::path& path) override { RemoveLink(path); }
};
}
std::optional<std::wstring> ReadRegistryString(const std::function<LSTATUS(void*, DWORD*)>& read) {
  DWORD bytes = 0;
  auto result = read(nullptr, &bytes);
  if (result == ERROR_FILE_NOT_FOUND) return {};
  if (result != ERROR_SUCCESS || bytes < sizeof(wchar_t) || bytes > 65536 || bytes % sizeof(wchar_t)) Io();
  std::wstring text(bytes / sizeof(wchar_t), L'\0');
  result = read(text.data(), &bytes);
  if (result != ERROR_SUCCESS || bytes < sizeof(wchar_t) ||
      bytes % sizeof(wchar_t) || bytes / sizeof(wchar_t) > text.size()) Io();
  text.resize(bytes / sizeof(wchar_t));
  if (text.back() != L'\0') Io();
  text.pop_back(); if (text.find(L'\0') != std::wstring::npos) Foreign(); return text;
}
RegistrationValues ProjectRegistration(const Paths& paths, const Installation& record) {
  paths.Validate(); if (record.sid != Utf8(paths.sid)) Foreign(); EncodeInstallation(record);
  RegistrationValues values;
  values.application = paths.install / L"ServerDeck.exe"; values.setup = paths.install / L"ServerDeckSetup.exe";
  values.recovery = paths.install / L"recovery" / L"ServerDeckSetup.exe";
  values.shortcut = paths.programs / L"ServerDeck.lnk";
  values.recoveryShortcut = paths.programs / L"ServerDeck — восстановление.lnk";
  values.strings = {{L"DisplayName", L"ServerDeck"}, {L"Publisher", L"ServerDeck"},
    {L"DisplayVersion", Wide(record.version.text)}, {L"InstallLocation", paths.install.wstring()},
    {L"DisplayIcon", Quote(values.application)}, {L"UninstallString", Quote(values.setup) + L" --uninstall"}};
  values.dwords = {{L"NoModify", 1}, {L"NoRepair", 1}}; return values;
}
WindowsRegistration::WindowsRegistration(Paths paths, RegistryPort* registry, ShortcutPort* shortcuts) : paths_(std::move(paths)) {
  paths_.Validate();
  if (!registry) { ownRegistry_ = std::make_unique<NativeRegistry>(); registry = ownRegistry_.get(); }
  if (!shortcuts) { ownShortcuts_ = std::make_unique<NativeShortcuts>(); shortcuts = ownShortcuts_.get(); }
  registry_ = registry; shortcuts_ = shortcuts;
}
bool WindowsRegistration::JournalEvidence() const {
  Files files(paths_); if (!files.Exists(L"journal.v1")) return false;
  const auto journal = DecodeJournal(files.ReadRecord(L"journal.v1"));
  return journal.target.sid == Utf8(paths_.sid) && (!journal.previous || journal.previous->sid == Utf8(paths_.sid));
}
bool WindowsRegistration::RecoveryEvidence() const {
  Files files(paths_);
  if (!files.Exists(L"recovery/recovery.v1") || !files.Exists(L"recovery/ServerDeckSetup.exe")) return false;
  const auto record = DecodeRecovery(files.ReadRecord(L"recovery/recovery.v1"));
  return record.sid == Utf8(paths_.sid) && files.Inspect(L"recovery/ServerDeckSetup.exe") == record.setup;
}
void WindowsRegistration::CheckOwnership() {
  paths_.Validate(); const bool journaled = JournalEvidence();
  if (registry_->Exists()) {
    const auto root = registry_->String(L"InstallLocation");
    if ((!root && !journaled) || (root && !Equal(*root, paths_.install.wstring()))) Foreign();
  }
  const auto app = paths_.programs / L"ServerDeck.lnk";
  const auto recovery = paths_.programs / L"ServerDeck — восстановление.lnk";
  RejectReparse(app); RejectReparse(recovery);
  if (!journaled && shortcuts_->Exists(app) && !shortcuts_->Matches(app, paths_.install / L"ServerDeck.exe", L"")) Foreign();
  if (!journaled && shortcuts_->Exists(recovery) &&
      !shortcuts_->Matches(recovery, paths_.install / L"recovery" / L"ServerDeckSetup.exe", L"--repair") && !RecoveryEvidence()) Foreign();
}
void WindowsRegistration::SetRecoveryLink() {
  CheckOwnership(); const auto path = paths_.programs / L"ServerDeck — восстановление.lnk";
  const auto target = paths_.install / L"recovery" / L"ServerDeckSetup.exe";
  if (!shortcuts_->Matches(path, target, L"--repair")) shortcuts_->Save(path, target, L"--repair");
}
void WindowsRegistration::Set(const Installation& record) {
  CheckOwnership(); const auto values = ProjectRegistration(paths_, record);
  registry_->SetString(L"InstallLocation", paths_.install.wstring());
  for (const auto& [name, value] : values.strings) registry_->SetString(name, value);
  for (const auto& [name, value] : values.dwords) registry_->SetDword(name, value);
  registry_->Flush(); shortcuts_->Save(values.shortcut, values.application, L""); SetRecoveryLink();
}
bool WindowsRegistration::Matches(const Installation& record) {
  const auto values = ProjectRegistration(paths_, record); if (!registry_->Exists()) return false;
  for (const auto& [name, value] : values.strings) { const auto actual = registry_->String(name); if (!actual || *actual != value) return false; }
  for (const auto& [name, value] : values.dwords) {
    const auto actual = registry_->Dword(name); if (!actual || *actual != value) return false;
  }
  return shortcuts_->Matches(values.shortcut, values.application, L"") && shortcuts_->Matches(values.recoveryShortcut, values.recovery, L"--repair");
}
void WindowsRegistration::Remove() {
  CheckOwnership(); shortcuts_->Remove(paths_.programs / L"ServerDeck.lnk"); registry_->Remove();
}
void WindowsRegistration::RemoveRecoveryLink() {
  CheckOwnership(); shortcuts_->Remove(paths_.programs / L"ServerDeck — восстановление.lnk");
}
void WindowsRegistration::SetRemovalRetry(const Installation& record, const std::filesystem::path& helper) {
  CheckOwnership();
  const auto ticket = ReadRemovalTicket(paths_, helper);
  if (EncodeInstallation(ticket.target) != EncodeInstallation(record)) Foreign();
  auto values = ProjectRegistration(paths_, record);
  values.strings[L"UninstallString"] = Quote(helper) + L" --uninstall-retry";
  values.strings[L"DisplayIcon"] = Quote(helper);
  registry_->SetString(L"InstallLocation", paths_.install.wstring());
  for (const auto& [name, value] : values.strings) registry_->SetString(name, value);
  for (const auto& [name, value] : values.dwords) registry_->SetDword(name, value);
  registry_->Flush();
}
}  // namespace sd::install
