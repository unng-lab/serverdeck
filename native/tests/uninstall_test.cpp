#include "uninstall.h"
#include "maintenance_handoff.h"
#include "install_registration.h"
#include "pending_update.h"
#include <winioctl.h>
#include <cstring>
#include <fstream>
#include <iostream>

namespace {
void Require(bool value, const char* reason) { if (!value) throw std::runtime_error(reason); }
struct Interrupted {};
struct FakeRegistration : sd::install::Registration {
  bool present = false, recovery = false, failRemove = false; int retries = 0;
  void CheckOwnership() override {}
  void SetRecoveryLink() override { recovery = true; }
  void Set(const sd::install::Installation&) override { present = true; recovery = true; }
  bool Matches(const sd::install::Installation&) override { return present && recovery; }
  void Remove() override { if (failRemove) { failRemove = false; throw sd::updates::Failure("STORAGE_IO"); } present = false; }
  void RemoveRecoveryLink() override { recovery = false; }
};
struct Registry : sd::install::RegistryPort {
  std::map<std::wstring, std::wstring> strings; std::map<std::wstring, DWORD> dwords;
  bool Exists() override { return !strings.empty(); }
  std::optional<std::wstring> String(const std::wstring& key) override { const auto it = strings.find(key); return it == strings.end() ? std::optional<std::wstring>{} : it->second; }
  std::optional<DWORD> Dword(const std::wstring& key) override { const auto it = dwords.find(key); return it == dwords.end() ? std::optional<DWORD>{} : it->second; }
  void SetString(const std::wstring& key, const std::wstring& value) override { strings[key] = value; }
  void SetDword(const std::wstring& key, DWORD value) override { dwords[key] = value; }
  void Flush() override {}
  void Remove() override { strings.clear(); dwords.clear(); }
};
struct Shortcuts : sd::install::ShortcutPort {
  bool Exists(const std::filesystem::path&) override { return false; }
  bool Matches(const std::filesystem::path&, const std::filesystem::path&, const wchar_t*) override { return false; }
  void Save(const std::filesystem::path&, const std::filesystem::path&, const wchar_t*) override {}
  void Remove(const std::filesystem::path&) override {}
};
struct Launch : sd::install::HandoffPort {
  std::filesystem::path expected; int calls = 0;
  std::unique_ptr<sd::Handle> Spawn(const std::filesystem::path& file, const std::wstring& command, const std::array<HANDLE, 5>& handles) override {
    ++calls; Require(file == expected && command.find(L" --uninstall-helper ") != std::wstring::npos, "removal executable/mode");
    Require(!SetEvent(handles[4]) && GetLastError() == ERROR_ACCESS_DENIED, "removal child can authorize itself");
    HANDLE process = nullptr; Require(DuplicateHandle(GetCurrentProcess(), GetCurrentProcess(), GetCurrentProcess(), &process,
      SYNCHRONIZE, FALSE, 0) != FALSE, "synthetic process"); return std::make_unique<sd::Handle>(process);
  }
  DWORD WaitReady(HANDLE, HANDLE, DWORD timeout) override { Require(timeout == 3000, "removal readiness deadline"); return WAIT_OBJECT_0; }
};
sd::install::Bytes View(const std::string& text) { return {reinterpret_cast<const uint8_t*>(text.data()), text.size()}; }
std::string Read(const std::filesystem::path& path) {
  std::ifstream stream(path, std::ios::binary); return {std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
}
void Junction(const std::filesystem::path& link, const std::filesystem::path& target) {
  sd::SecureDirectory(link); const auto substitute = L"\\??\\" + target.wstring(), print = target.wstring();
  struct Reparse { ULONG tag; USHORT length, reserved, substituteOffset, substituteLength, printOffset, printLength; wchar_t paths[2048]; } data{};
  Require(substitute.size() + print.size() + 2 < 2048, "junction bounds"); data.tag = IO_REPARSE_TAG_MOUNT_POINT;
  data.substituteLength = static_cast<USHORT>(substitute.size() * sizeof(wchar_t));
  data.printOffset = static_cast<USHORT>((substitute.size() + 1) * sizeof(wchar_t)); data.printLength = static_cast<USHORT>(print.size() * sizeof(wchar_t));
  std::memcpy(data.paths, substitute.c_str(), data.substituteLength);
  std::memcpy(reinterpret_cast<BYTE*>(data.paths) + data.printOffset, print.c_str(), data.printLength);
  data.length = static_cast<USHORT>(8 + data.printOffset + data.printLength + sizeof(wchar_t));
  sd::Handle directory(CreateFileW(link.c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, nullptr)); DWORD returned = 0;
  Require(directory.valid() && DeviceIoControl(directory.get(), FSCTL_SET_REPARSE_POINT, &data, 8 + data.length, nullptr, 0, &returned, nullptr), "junction fixture");
}
}
int main() {
  using namespace sd::install;
  std::filesystem::path root;
  try {
    wchar_t temporary[32768]{}; Require(GetTempPathW(32768, temporary) != 0, "temp path");
    root = std::filesystem::path(temporary) / (L"ServerDeckRemovalUnit-" + sd::Uuid()); sd::SecureDirectory(root);
    const std::string app = "synthetic application", setup = "synthetic setup";
    const Package package{sd::updates::ParseVersion("0.1.0"), View(app), View(setup)};
    for (const auto* name : {L"normal", L"empty-root", L"locked", L"interrupted", L"sid", L"active", L"foreign-pending", L"reparse", L"retry-registration", L"remove-registration", L"after-registration"}) {
      const auto scenario = root / name; sd::SecureDirectory(scenario);
      const Paths paths{scenario / L"install", scenario / L"data", scenario / L"programs", sd::UserSid()};
      Files files(paths); FakeRegistration registration; std::optional<Installation> installed;
      const auto validator = [](const std::filesystem::path&, const sd::updates::Version&, const Identity&) {};
      {
        Lease lease(paths, true); Executor executor(files, lease, registration, validator);
        executor.Apply(package, true); installed = executor.Current();
      }
      { std::ofstream sentinel(paths.data / L"profiles-and-secrets", std::ios::binary); sentinel << "user data remains exact"; }
      if (std::wstring(name) != L"empty-root") { std::ofstream foreign(paths.install / L"user-note.txt", std::ios::binary); foreign << "foreign bytes"; }
      if (std::wstring(name) == L"active") {
        Lease owner(paths, true); owner.ReleaseMaintenance(); bool blocked = false;
        try { Lease removal(paths, true); } catch (const sd::updates::Failure& error) { blocked = std::string(error.what()) == "OWNER_RUNNING"; }
        Require(blocked && files.Exists(L"ServerDeck.exe") && !files.Exists(L"journal.v1"), "active owner removal");
        continue;
      }
      Lease lease(paths, true);
      const auto helper = PrepareRemovalCache(files, lease, *installed, View(setup));
      const auto ticket = ReadRemovalCache(paths, helper, package);
      Require(Read(helper) == setup && DecodeRemovalTicket(EncodeRemovalTicket(ticket)).id == ticket.id, "marked helper copy/codec");
      bool invalidMarker = false;
      try { DecodeRemovalTicket(EncodeRemovalTicket(ticket) + "\n"); } catch (const sd::updates::Failure&) { invalidMarker = true; }
      Require(invalidMarker, "noncanonical removal ticket accepted");
      bool arbitraryPath = false;
      try { ReadRemovalCache(paths, paths.install / L"ServerDeckSetup.exe", package); } catch (const sd::updates::Failure&) { arbitraryPath = true; }
      Require(arbitraryPath, "arbitrary uninstaller path accepted");
      Launch launch; launch.expected = helper; StartRemovalHandoff(lease, paths, helper, launch);
      Require(launch.calls == 1, "removal handoff missing");
      bool arbitraryHandoff = false;
      try { StartRemovalHandoff(lease, paths, paths.install / L"ServerDeckSetup.exe", launch); } catch (const sd::updates::Failure&) { arbitraryHandoff = true; }
      Require(arbitraryHandoff && launch.calls == 1, "arbitrary removal helper launch");
      Registry registry; Shortcuts shortcuts; WindowsRegistration realRegistration(paths, &registry, &shortcuts);
      realRegistration.SetRemovalRetry(*installed, helper);
      Require(registry.strings[L"UninstallString"] == L"\"" + helper.wstring() + L"\" --uninstall-retry" &&
        registry.strings[L"DisplayName"] == L"ServerDeck" && registry.strings[L"InstallLocation"] == paths.install.wstring(), "partial retry registration projection");
      const auto retry = [&] { ++registration.retries; registration.present = true; };
      if (std::wstring(name) == L"reparse") {
        const auto saved = helper.parent_path().parent_path() / L"saved-unit-cache";
        Require(MoveFileExW(helper.parent_path().c_str(), saved.c_str(), 0) != FALSE, "save cache fixture");
        Junction(helper.parent_path(), paths.data); bool blocked = false;
        try { ReadRemovalTicket(paths, helper); } catch (const std::exception&) { blocked = true; }
        Require(blocked && Read(paths.data / L"profiles-and-secrets") == "user data remains exact", "cache reparse accepted");
        Require(RemoveDirectoryW(helper.parent_path().c_str()) && MoveFileExW(saved.c_str(), helper.parent_path().c_str(), 0), "restore cache fixture");
      }
      if (std::wstring(name) == L"sid") {
        auto foreign = ticket; foreign.target.sid = "S-1-5-18"; bool blocked = false;
        try { RemoveInstallation(files, lease, registration, foreign, retry); } catch (const sd::updates::Failure&) { blocked = true; }
        Require(blocked && !files.Exists(L"journal.v1") && registration.retries == 0 && files.Exists(L"ServerDeck.exe"), "foreign SID removal");
        continue;
      }
      const std::string catalog = "synthetic signed catalog bytes";
      const sd::updates::PendingConsent pending{sd::Utf8(sd::Uuid()), installed->sid, 0, installed->version,
        installed->app, installed->setup, sd::Sha256(reinterpret_cast<const uint8_t*>(catalog.data()), catalog.size()), 100000};
      files.WriteRecord(sd::updates::PendingPath(0, L"owner.v1"), sd::updates::EncodePending(pending));
      files.WriteRecord(sd::updates::PendingPath(0, L"catalog.v1"), catalog);
      files.WriteArtifact(sd::updates::PendingPath(0, L"ServerDeckSetup.exe"), package.setup.data, package.setup.size);
      if (std::wstring(name) == L"foreign-pending") {
        const std::string changed = "unowned replacement";
        files.WriteArtifact(sd::updates::PendingPath(0, L"ServerDeckSetup.exe"), reinterpret_cast<const uint8_t*>(changed.data()), changed.size());
        bool blocked = false;
        try { RemoveInstallation(files, lease, registration, ticket, retry); } catch (const sd::updates::Failure&) { blocked = true; }
        Require(blocked && !files.Exists(L"journal.v1") && files.Exists(L"ServerDeck.exe") &&
          Read(paths.data / L"profiles-and-secrets") == "user data remains exact", "changed pending bytes deleted or data changed");
        continue;
      }
      if (std::wstring(name) == L"locked") {
        {
          sd::Handle locked(CreateFileW((paths.install / L"ServerDeck.exe").c_str(), GENERIC_READ, FILE_SHARE_READ,
            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr)); Require(locked.valid(), "locked fixture");
          const auto result = RemoveInstallation(files, lease, registration, ticket, retry);
          Require(!result.complete() && registration.present && files.Exists(L"journal.v1") && files.Exists(L"installation.v1"), "partial deletion lost retry authority");
          Require(DecodeJournal(files.ReadRecord(L"journal.v1")).kind == Operation::remove, "removal journal kind");
        }
      }
      if (std::wstring(name) == L"interrupted") {
        bool stopped = false;
        try { RemoveInstallation(files, lease, registration, ticket, retry, [](const char* stage) {
          if (std::string(stage) == "remove-file") throw Interrupted{};
        }); } catch (const Interrupted&) { stopped = true; }
        Require(stopped && registration.present && files.Exists(L"journal.v1"), "interrupted deletion authority");
      }
      if (std::wstring(name) == L"retry-registration") {
        bool stopped = false;
        try { RemoveInstallation(files, lease, registration, ticket, [] { throw sd::updates::Failure("STORAGE_IO"); }); }
        catch (const sd::updates::Failure&) { stopped = true; }
        Require(stopped && files.Exists(L"ServerDeck.exe") && files.Exists(L"ServerDeckSetup.exe") && files.Exists(L"journal.v1"), "retry registration failure deleted files");
      }
      if (std::wstring(name) == L"remove-registration") {
        registration.failRemove = true;
        Require(!RemoveInstallation(files, lease, registration, ticket, retry).complete() && files.Exists(L"journal.v1") && registration.present,
          "registry failure lost partial retry authority");
      }
      if (std::wstring(name) == L"after-registration") {
        bool stopped = false;
        try { RemoveInstallation(files, lease, registration, ticket, retry, [](const char* stage) {
          if (std::string(stage) == "remove-registration") throw Interrupted{};
        }); } catch (const Interrupted&) { stopped = true; }
        Require(stopped && !registration.present && files.Exists(L"journal.v1") && !files.Exists(L"ServerDeckSetup.exe") &&
          !files.Exists(L"installation.v1"), "post-registration interruption fixture");
        Require(FindInterruptedRemoval(files, lease, validator) == std::optional<std::filesystem::path>{helper},
          "ordinary setup cannot resolve marked retry after registration removal");
      }
      Require(RemoveInstallation(files, lease, registration, ticket, retry).complete(), "removal retry incomplete");
      Require(!registration.present && !registration.recovery && !files.Exists(L"ServerDeck.exe") && !files.Exists(L"ServerDeckSetup.exe") &&
        !files.Exists(L"installation.v1") && !files.Exists(L"journal.v1"), "owned files survived success");
      Require(Read(paths.data / L"profiles-and-secrets") == "user data remains exact" &&
        (std::wstring(name) == L"empty-root" ? !std::filesystem::exists(paths.install) : Read(paths.install / L"user-note.txt") == "foreign bytes"), "removal changed user data or retained owned empty root");
      Executor reinstall(files, lease, registration, validator); reinstall.Apply(package, true);
      Require(reinstall.Current()->version == package.version && Read(paths.data / L"profiles-and-secrets") == "user data remains exact", "reinstall replaced data root");
      bool replayBlocked = false;
      try { RemoveInstallation(files, lease, registration, ticket, retry); } catch (const sd::updates::Failure&) { replayBlocked = true; }
      Require(replayBlocked && !files.Exists(L"journal.v1") && files.Exists(L"ServerDeck.exe") && registration.present, "old helper ticket removed new equal-version installation");
    }
    std::filesystem::remove_all(root); root.clear(); std::cout << "uninstall unit scenarios passed\n"; return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n'; if (!root.empty()) std::filesystem::remove_all(root); return 1;
  }
}
