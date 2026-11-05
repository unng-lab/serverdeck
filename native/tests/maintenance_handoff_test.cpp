#include "maintenance_handoff.h"
#include <iostream>
#include <sstream>

namespace {
using namespace sd::install;
void Require(bool value, const char* reason) { if (!value) throw std::runtime_error(reason); }
template<class F> void Reject(F action, const char* code = "RECOVERY_REQUIRED") {
  try { action(); } catch (const sd::updates::Failure& error) { Require(std::string(error.what()) == code, error.what()); return; }
  throw std::runtime_error("invalid handoff accepted");
}
HANDLE Copy(HANDLE original, bool inheritable = true) {
  HANDLE copy = nullptr;
  Require(DuplicateHandle(GetCurrentProcess(), original, GetCurrentProcess(), &copy, 0, inheritable, DUPLICATE_SAME_ACCESS) != FALSE, "duplicate"); return copy;
}
HANDLE ReadPermit(HANDLE original) {
  HANDLE copy = nullptr;
  Require(DuplicateHandle(GetCurrentProcess(), original, GetCurrentProcess(), &copy, SYNCHRONIZE, TRUE, 0) != FALSE, "read-only permit"); return copy;
}
struct ProcessPort : HandoffPort {
  DWORD result = WAIT_OBJECT_0; int calls = 0;
  HANDLE originalMaintenance = nullptr, originalOwner = nullptr;
  std::unique_ptr<sd::Handle> childReady, childPermit;
  std::unique_ptr<sd::Handle> Spawn(const std::filesystem::path& executable, const std::wstring& command, const std::array<HANDLE, 5>& handles) override {
    ++calls; childReady = std::make_unique<sd::Handle>(Copy(handles[3])); childPermit = std::make_unique<sd::Handle>(Copy(handles[4]));
    Require(!SetEvent(childPermit->get()) && GetLastError() == ERROR_ACCESS_DENIED, "child can self-authorize");
    Require(executable.filename() == L"ServerDeckSetup.exe" && executable.parent_path().filename() == L"slot1", "arbitrary executable");
    const auto mode = command.find(L" --apply-pending "); Require(mode != std::wstring::npos, "mode");
    std::vector<std::wstring> arguments; std::wistringstream input(command.substr(mode + 17)); std::wstring item;
    while (input >> item) arguments.push_back(item);
    const auto decoded = ParseTransfer(arguments);
    Require(decoded.maintenance == handles[0] && decoded.owner == handles[1] && decoded.parent == handles[2] && decoded.ready == handles[3] && decoded.permit == handles[4], "argv handles");
    Require(handles[0] != originalMaintenance && handles[1] != originalOwner, "parent originals marked inheritable");
    for (const auto handle : handles) { DWORD flags = 0; Require(GetHandleInformation(handle, &flags) && (flags & HANDLE_FLAG_INHERIT), "not inheritable"); }
    return std::make_unique<sd::Handle>(Copy(GetCurrentProcess(), false));
  }
  DWORD WaitReady(HANDLE ready, HANDLE, DWORD timeout) override {
    Require(timeout == 3000, "readiness deadline"); if (result == WAIT_OBJECT_0) Require(SetEvent(ready) != FALSE, "ack"); return result;
  }
};
}
int main() {
  std::filesystem::path root;
  try {
    std::vector<std::wstring> arguments{L"--maintenance-handle", L"12", L"--owner-handle", L"16", L"--parent-handle", L"20", L"--ready-handle", L"24", L"--permit-handle", L"28"};
    Require(ParseTransfer(arguments).ready == reinterpret_cast<HANDLE>(24), "parse");
    for (const auto* bad : {L"0", L"01", L"-1", L"1x", L"18446744073709551616", L"18446744073709551615", L" 12", L"12\n"}) {
      auto changed = arguments; changed[1] = bad; Reject([&] { ParseTransfer(changed); });
    }
    auto changed = arguments; changed.push_back(L"extra"); Reject([&] { ParseTransfer(changed); });
    changed = arguments; changed.resize(8); Reject([&] { ParseTransfer(changed); });
    changed = arguments; changed[1] = L"16"; Reject([&] { ParseTransfer(changed); });
    changed = arguments; changed[0] = L"--path"; Reject([&] { ParseTransfer(changed); });
    wchar_t temporary[32768]{}; Require(GetTempPathW(32768, temporary) != 0, "temp");
    root = std::filesystem::path(temporary) / (L"ServerDeckHandoffUnit-" + sd::Uuid()); sd::SecureDirectory(root);
    const Paths paths{root / L"install", root / L"data", root / L"programs", sd::UserSid()};
    {
      Lease original(paths, true);
      ValidateLeaseHandle(original.maintenance(), paths.data / L"maintenance.lock");
      ValidateLeaseHandle(original.owner(), paths.data / L"owner.lock");
      Reject([&] { ValidateLeaseHandle(original.owner(), paths.data / L"maintenance.lock"); });
      sd::Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr)), permit(CreateEventW(nullptr, TRUE, FALSE, nullptr));
      Reject([&] { ValidateLeaseHandle(event.get(), paths.data / L"owner.lock"); });
      Reject([&] { ValidateParent(GetCurrentProcess(), paths); });
      Reject([&] { AcceptTransfer(paths, {Copy(original.maintenance()), Copy(original.owner()), Copy(GetCurrentProcess()), Copy(event.get()), ReadPermit(permit.get())}); });
      Require(original.Owns(paths, true), "invalid parent destroyed original authority");
      bool checkedParent = false;
      auto accepted = AcceptTransfer(paths, {Copy(original.maintenance()), Copy(original.owner()), Copy(GetCurrentProcess()), Copy(event.get()), ReadPermit(permit.get())},
        [&](HANDLE parent, const Paths& actual) { checkedParent = GetProcessId(parent) == GetCurrentProcessId() && actual.sid == paths.sid; });
      Require(checkedParent && accepted.lease->Owns(paths, true) && original.Owns(paths, true), "leases not continuously held");
      DWORD flags = HANDLE_FLAG_INHERIT;
      Require(GetHandleInformation(accepted.lease->owner(), &flags) && !(flags & HANDLE_FLAG_INHERIT), "child inheritance not cleared");
      accepted.Acknowledge(); Require(WaitForSingleObject(event.get(), 0) == WAIT_OBJECT_0, "ready not signaled");
      Reject([&] { AcceptTransfer(paths, {Copy(original.maintenance()), Copy(original.owner()), Copy(GetCurrentProcess()), Copy(event.get()), ReadPermit(permit.get())},
        [](HANDLE, const Paths&) {}); });
      Reject([&] { AcceptTransfer(paths, {Copy(original.maintenance()), Copy(original.owner()), Copy(GetCurrentProcess()), Copy(original.owner()), ReadPermit(permit.get())},
        [](HANDLE, const Paths&) {}); });
      Require(original.Owns(paths, true), "invalid event destroyed original authority");
      bool waitedForParent = false;
      Reject([&] { accepted.AwaitParent([&](HANDLE, DWORD) { waitedForParent = true; return WAIT_OBJECT_0; },
        [](HANDLE, HANDLE, DWORD timeout) { Require(timeout == 3000, "permission deadline"); return WAIT_TIMEOUT; }); }, "TIMEOUT");
      Reject([&] { accepted.AwaitParent([&](HANDLE, DWORD) { waitedForParent = true; return WAIT_OBJECT_0; },
        [](HANDLE, HANDLE, DWORD) { return WAIT_OBJECT_0 + 1; }); });
      Require(!waitedForParent, "late ACK/parent exit bypassed permission");
      {
        sd::Handle different(CreateEventW(nullptr, TRUE, FALSE, nullptr));
        Reject([&] { AcceptTransfer(paths, {Copy(original.maintenance()), Copy(original.owner()), Copy(GetCurrentProcess()),
          Copy(different.get()), ReadPermit(different.get())}, [](HANDLE, const Paths&) {}); });
        Reject([&] { AcceptTransfer(paths, {Copy(original.maintenance()), Copy(original.owner()), Copy(GetCurrentProcess()),
          Copy(different.get()), Copy(permit.get())}, [](HANDLE, const Paths&) {}); });
      }
      Require(SetEvent(permit.get()) != FALSE, "parent permission");
      accepted.AwaitParent([](HANDLE, DWORD timeout) { Require(timeout == 10000, "parent wait deadline"); return WAIT_OBJECT_0; });
      Reject([&] { accepted.AwaitParent([](HANDLE, DWORD) { return WAIT_TIMEOUT; }); }, "TIMEOUT");
      Reject([&] { accepted.AwaitParent([](HANDLE, DWORD) { return WAIT_FAILED; }); });
      Require(accepted.lease->Owns(paths, true), "wait failure released leases");
      ProcessPort process; process.originalMaintenance = original.maintenance(); process.originalOwner = original.owner();
      for (const auto status : std::array<DWORD, 4>{WAIT_OBJECT_0, WAIT_OBJECT_0 + 1, WAIT_TIMEOUT, WAIT_FAILED}) {
        process.result = status;
        if (status == WAIT_OBJECT_0) StartPendingHandoff(original, paths, 1, process);
        else Reject([&] { StartPendingHandoff(original, paths, 1, process); }, status == WAIT_TIMEOUT ? "TIMEOUT" : "RECOVERY_REQUIRED");
        Require(original.Owns(paths, true), "parent failed handoff dropped original authority");
        Require(SetEvent(process.childReady->get()) != FALSE, "late child ACK");
        Require(WaitForSingleObject(process.childPermit->get(), 0) == (status == WAIT_OBJECT_0 ? WAIT_OBJECT_0 : WAIT_TIMEOUT), "failed handoff granted late permission");
      }
      DWORD parentFlags = 0;
      Require(GetHandleInformation(original.owner(), &parentFlags) && !(parentFlags & HANDLE_FLAG_INHERIT), "original owner became inheritable");
      Reject([&] { StartPendingHandoff(original, paths, 2, process); });
      Require(process.calls == 4, "invalid slot spawned");
    }
    // Broadly shared files and attribute-only handles cannot pose as owner locks.
    sd::SecureDirectory(paths.data);
    const auto loose = paths.data / L"loose.lock";
    for (DWORD sharing = 1; sharing <= 7; ++sharing) {
      sd::Handle shared(CreateFileW(sd::ExtendedPath(loose).c_str(), GENERIC_READ | GENERIC_WRITE | WRITE_DAC,
        sharing, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr));
      Require(shared.valid(), "shared fixture"); Reject([&] { ValidateLeaseHandle(shared.get(), loose); });
    }
    {
      sd::Handle attributes(CreateFileW(sd::ExtendedPath(loose).c_str(), FILE_READ_ATTRIBUTES, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
      Require(attributes.valid(), "attribute fixture"); Reject([&] { ValidateLeaseHandle(attributes.get(), loose); });
    }
    {
      Lease onlyMaintenance(paths, false);
      sd::Handle sharedOwner(CreateFileW(sd::ExtendedPath(paths.data / L"owner.lock").c_str(),
        GENERIC_READ | GENERIC_WRITE | WRITE_DAC, FILE_SHARE_READ | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
      sd::Handle ready(CreateEventW(nullptr, TRUE, FALSE, nullptr)), permit(CreateEventW(nullptr, TRUE, FALSE, nullptr));
      Require(sharedOwner.valid() && ready.valid(), "partial sharing fixture");
      Reject([&] { AcceptTransfer(paths, {Copy(onlyMaintenance.maintenance()), Copy(sharedOwner.get()),
        Copy(GetCurrentProcess()), Copy(ready.get()), ReadPermit(permit.get())}, [](HANDLE, const Paths&) {}); });
      Require(WaitForSingleObject(ready.get(), 0) == WAIT_TIMEOUT && onlyMaintenance.Owns(paths, false),
        "partial sharing acknowledged or dropped parent lease");
    }
    std::filesystem::remove_all(root); root.clear(); std::cout << "maintenance handoff unit checks passed\n"; return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; if (!root.empty()) std::filesystem::remove_all(root); return 1; }
}
