#include "installation.h"
#include "mcp_json.h"
#include <winioctl.h>
#include <cstring>
#include <fstream>
#include <iostream>
#include <functional>

namespace {
void Require(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
void Reject(const std::function<void()>& action, const std::string& code = {}) {
  try { action(); } catch (const std::exception& e) { Require(code.empty() || e.what() == code, "wrong failure classification"); return; }
  throw std::runtime_error("invalid input accepted");
}
sd::install::Identity Id(const std::string& bytes) {
  return {bytes.size(), sd::Sha256(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size())};
}
sd::install::Installation Record(const std::string& version, const std::string& app, const std::string& setup) {
  return {sd::Utf8(sd::UserSid()), sd::updates::ParseVersion(version), Id(app), Id(setup), {}, {}};
}
void Junction(const std::filesystem::path& link, const std::filesystem::path& target) {
  sd::SecureDirectory(link);
  const auto substitute = L"\\??\\" + target.wstring(), print = target.wstring();
  struct Reparse {
    ULONG tag; USHORT length, reserved;
    USHORT substituteOffset, substituteLength, printOffset, printLength;
    wchar_t paths[2048];
  } data{};
  Require(substitute.size() + print.size() + 2 < 2048, "junction bounds");
  data.tag = IO_REPARSE_TAG_MOUNT_POINT;
  data.substituteLength = static_cast<USHORT>(substitute.size() * sizeof(wchar_t));
  data.printOffset = static_cast<USHORT>((substitute.size() + 1) * sizeof(wchar_t));
  data.printLength = static_cast<USHORT>(print.size() * sizeof(wchar_t));
  std::memcpy(data.paths, substitute.c_str(), data.substituteLength);
  std::memcpy(reinterpret_cast<BYTE*>(data.paths) + data.printOffset, print.c_str(), data.printLength);
  data.length = static_cast<USHORT>(8 + data.printOffset + data.printLength + sizeof(wchar_t));
  sd::Handle handle(CreateFileW(link.c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, nullptr));
  DWORD returned = 0;
  Require(handle.valid() && DeviceIoControl(handle.get(), FSCTL_SET_REPARSE_POINT, &data,
    8 + data.length, nullptr, 0, &returned, nullptr), "junction creation");
}
}
int main() {
  using namespace sd::install;
  std::filesystem::path temporary;
  try {
    const auto old = Record("0.1.0", "old app", "old setup");
    auto next = Record("0.1.1", "new app", "new setup");
    next.consumedVersion = next.version.text; next.consumedSetupHash = next.setup.hash;
    Require(DecodeInstallation(EncodeInstallation(next)).consumedVersion == next.version.text, "metadata roundtrip");
    for (const auto& bad : {std::string(), std::string("SDINSTALL002\n{}\n"),
        EncodeInstallation(next) + "x", std::string(8193, 'x')}) Reject([&] { DecodeInstallation(bad); });
    auto malformed = next; malformed.app.size = sd::updates::kArtifactLimit + 1;
    Reject([&] { EncodeInstallation(malformed); });
    malformed = next; malformed.consumedSetupHash.clear(); Reject([&] { EncodeInstallation(malformed); });
    malformed = next; malformed.consumedSetupHash = old.setup.hash; Reject([&] { EncodeInstallation(malformed); });
    malformed = next; malformed.sid = "S-1-invalid"; Reject([&] { EncodeInstallation(malformed); });
    Journal journal{sd::Utf8(sd::Uuid()), Operation::update, Stage::prepared, old, next};
    const auto decoded = DecodeJournal(EncodeJournal(journal));
    Require(decoded.previous && decoded.target.setup == next.setup, "journal roundtrip");
    Reject([&] { DecodeJournal("SDJOURNAL001\n{}\n"); });
    auto wrong = journal; wrong.target.version = old.version; wrong.target.consumedVersion.clear(); wrong.target.consumedSetupHash.clear();
    Reject([&] { EncodeJournal(wrong); }); // immutable release id cannot acquire other bytes.
    wrong = journal; wrong.kind = Operation::remove;
    Reject([&] { EncodeJournal(wrong); });
    const auto recovery = Recovery{old.sid, old.version, old.setup};
    Require(DecodeRecovery(EncodeRecovery(recovery)).setup == old.setup, "recovery roundtrip");

    Observation o;
    o.app = next.app; o.setup = next.setup; o.backupApp = old.app; o.backupSetup = old.setup;
    o.registrationMatchesTarget = true;
    Require(PlanRecovery(journal, o).action == RecoveryAction::commit, "complete new version must commit");
    o.registrationMatchesTarget = false;
    auto plan = PlanRecovery(journal, o);
    Require(plan.action == RecoveryAction::rollback && plan.appSource == L"ServerDeck.previous", "registration failure must roll back");
    o.app.reset(); // ReplaceFile 1177 / interrupted helper: canonical can be absent.
    Require(PlanRecovery(journal, o).action == RecoveryAction::rollback, "missing canonical recovery");
    o.backupApp.reset();
    Require(PlanRecovery(journal, o).action == RecoveryAction::blocked, "unverified bytes cannot restore");
    o.app = old.app; o.setup = old.setup; o.backupSetup.reset();
    plan = PlanRecovery(journal, o);
    Require(plan.action == RecoveryAction::rollback && plan.appSource == L"ServerDeck.exe", "old canonical remains valid");
    auto fresh = journal; fresh.kind = Operation::install; fresh.previous.reset();
    o = {}; o.app = next.app;
    Require(PlanRecovery(fresh, o).action == RecoveryAction::discardFresh, "fresh partial install cleanup");
    o.app = Id("foreign bytes");
    Require(PlanRecovery(fresh, o).action == RecoveryAction::blocked, "foreign canonical must survive");

    wchar_t temp[32768]{};
    Require(GetTempPathW(32768, temp) != 0, "temp root");
    temporary = std::filesystem::path(temp) / (L"ServerDeckInstallUnit-" + sd::Uuid());
    sd::SecureDirectory(temporary);
    const Paths paths{temporary / L"install", temporary / L"data", temporary / L"programs", sd::UserSid()};
    sd::SecureDirectory(paths.data); sd::SecureDirectory(paths.programs);
    const auto sentinel = paths.data / L"do-not-touch";
    { std::ofstream f(sentinel); f << "user data"; }
    Files files(paths);
    Require(!files.Exists(L"ServerDeck.exe"), "fresh existence");
    for (const auto* bad : {L"../data/do-not-touch", L"C:/foreign.exe", L"pending/../ServerDeck.exe", L"unknown.bin", L"ServerDeck.exe:ads"})
      Reject([&] { files.Remove(bad); });
    files.WriteRecord(L"installation.v1", EncodeInstallation(old));
    Require(DecodeInstallation(files.ReadRecord(L"installation.v1")).version == old.version, "native metadata IO");
    Reject([&] { files.WriteRecord(L"journal.v1", std::string(8193, 'x')); });
    const std::string app = "old app", replacement = "new app";
    files.WriteArtifact(L"ServerDeck.exe", reinterpret_cast<const uint8_t*>(app.data()), app.size());
    Require(files.Inspect(L"ServerDeck.exe") == old.app, "streaming fingerprint");
    files.Copy(L"ServerDeck.exe", L"ServerDeck.previous");
    files.WriteArtifact(L"ServerDeck.new", reinterpret_cast<const uint8_t*>(replacement.data()), replacement.size());
    Require(files.Publish(L"ServerDeck.new", L"ServerDeck.exe") == ERROR_SUCCESS, "publish replacement");
    Require(files.Inspect(L"ServerDeck.exe") == next.app && files.Inspect(L"ServerDeck.previous") == old.app, "full new and backup");
    Reject([&] { files.WriteArtifact(L"ServerDeck.exe", nullptr, 0); });
    {
      sd::Handle blocker(CreateFileW(files.Path(L"ServerDeck.exe").c_str(), GENERIC_READ, 0,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
      Require(blocker.valid(), "synthetic sharing blocker");
      Reject([&] { files.Copy(L"ServerDeck.exe", L"ServerDeck.previous"); });
    }
    Require(files.Inspect(L"ServerDeck.previous") == old.app, "failed copy changed backup");
    Junction(paths.install / L"recovery", paths.data);
    Reject([&] { files.Remove(L"recovery/ServerDeckSetup.exe"); });
    Reject([&] { files.WriteRecord(L"recovery/recovery.v1", "foreign"); });
    Require(RemoveDirectoryW((paths.install / L"recovery").c_str()), "remove synthetic junction");
    const auto stageOwner = paths.install / L".stage-owner.v1";
    const auto stagePayload = paths.install / L".stage.bin";
    const auto foreignFile = paths.install / L"foreign.tmp";
    { std::ofstream f(foreignFile); f << "foreign"; }
    const auto orphan = [&](const std::string& sid) {
      const auto body = sd::mcp::Encode(sd::mcp::Json::Object{{"id", sd::Utf8(sd::Uuid())},
        {"sid", sid}, {"target", "ServerDeck.new"}, {"size", 1024}});
      { std::ofstream f(stageOwner, std::ios::binary); f << "SDSTAGE001\n" << body << '\n'; }
      { std::ofstream f(stagePayload, std::ios::binary); f << "partial interrupted staging"; }
    };
    orphan(old.sid);
    files.CleanupStaging();
    Require(!std::filesystem::exists(stageOwner) && !std::filesystem::exists(stagePayload), "owned interrupted stage not reclaimed");
    orphan(old.sid);
    files.WriteArtifact(L"ServerDeck.new", reinterpret_cast<const uint8_t*>(replacement.data()), replacement.size());
    Require(files.Inspect(L"ServerDeck.new") == next.app && !std::filesystem::exists(stagePayload), "retry did not reclaim stage");
    orphan("S-1-foreign");
    Reject([&] { files.CleanupStaging(); }, "RECOVERY_REQUIRED");
    Require(std::filesystem::exists(stageOwner) && std::filesystem::exists(stagePayload), "foreign stage deleted");
    std::filesystem::remove(stageOwner); std::filesystem::remove(stagePayload);
    { std::ofstream f(stagePayload); f << "unattributed"; }
    Reject([&] { files.CleanupStaging(); }, "RECOVERY_REQUIRED");
    Require(std::filesystem::exists(stagePayload), "unattributed file deleted");
    std::filesystem::remove(stagePayload);
    orphan(old.sid);
    { std::ofstream f(stagePayload, std::ios::binary); f << std::string(1025, 'x'); }
    Reject([&] { files.CleanupStaging(); }, "RECOVERY_REQUIRED");
    Require(std::filesystem::file_size(stagePayload) == 1025 && std::filesystem::exists(stageOwner), "oversized payload changed");
    std::filesystem::remove(stageOwner); std::filesystem::remove(stagePayload);
    orphan(old.sid);
    { std::ofstream f(stageOwner, std::ios::binary); f << std::string(8193, 'x'); }
    Reject([&] { files.CleanupStaging(); }, "RECOVERY_REQUIRED");
    Require(std::filesystem::file_size(stageOwner) == 8193 && std::filesystem::exists(stagePayload), "oversized owner changed");
    std::filesystem::remove(stageOwner); std::filesystem::remove(stagePayload);
    orphan(old.sid);
    {
      sd::Handle blocker(CreateFileW(stageOwner.c_str(), GENERIC_READ, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
      Require(blocker.valid(), "stage read blocker");
      Reject([&] { files.CleanupStaging(); }, "STORAGE_IO");
    }
    files.CleanupStaging();
    orphan(old.sid); std::filesystem::remove(stagePayload);
    Junction(stagePayload, paths.data);
    Reject([&] { files.CleanupStaging(); }, "RECOVERY_REQUIRED");
    Require(RemoveDirectoryW(stagePayload.c_str()), "remove staging junction");
    std::filesystem::remove(stageOwner);
    orphan(old.sid); files.CleanupStaging(true);
    Require(!std::filesystem::exists(stageOwner) && !std::filesystem::exists(stagePayload) &&
      !std::filesystem::exists(paths.install / L".stage.lock"), "uninstall staging cleanup incomplete");
    Junction(paths.install / L".stage.lock", paths.data);
    Reject([&] { files.CleanupStaging(); }, "RECOVERY_REQUIRED");
    Reject([&] { files.WriteRecord(L"journal.v1", EncodeJournal(journal)); }, "RECOVERY_REQUIRED");
    Require(std::filesystem::file_size(sentinel) == 9, "slot-lock reparse changed sentinel");
    Require(RemoveDirectoryW((paths.install / L".stage.lock").c_str()), "remove slot-lock junction");
    Require(std::filesystem::file_size(foreignFile) == 7, "unlisted file deleted");
    Require(files.FreeBytes() > 0, "disk space");
    {
      Lease first(paths, true);
      Reject([&] { Lease second(paths, true, 0); });
      first.ReleaseMaintenance();
      Reject([&] { Lease mutation(paths, true, 0); }); // owner held, despite free maintenance.
    }
    { Lease nextLease(paths, true, 0); }
    auto foreignSid = paths; foreignSid.sid = L"S-1-5-18";
    if (paths.sid != foreignSid.sid) Reject([&] { Lease foreign(foreignSid, true, 0); });
    auto overlap = paths; overlap.install = paths.data / L"nested";
    Reject([&] { Files invalid(overlap); });
    Require(std::filesystem::file_size(sentinel) == 9, "data sentinel changed");
    std::filesystem::remove_all(temporary); temporary.clear();
    std::cout << "installation foundation unit checks passed\n"; return 0;
  } catch (const std::exception& e) {
    std::cerr << e.what() << '\n';
    if (!temporary.empty()) std::filesystem::remove_all(temporary);
    return 1;
  }
}
