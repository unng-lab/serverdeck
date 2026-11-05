#pragma once
#include "installation.h"
#include <array>

namespace sd::install {
struct TransferHandles { HANDLE maintenance, owner, parent, ready, permit; };
// Arguments exclude executable and mode. Five exact named canonical decimal HANDLEs.
TransferHandles ParseTransfer(const std::vector<std::wstring>& args);
void ValidateLeaseHandle(HANDLE handle, const std::filesystem::path& expected);
void ValidateParent(HANDLE process, const Paths& paths);
void ValidateRemovalParent(HANDLE process, const Paths& paths);
struct AcceptedTransfer {
  std::unique_ptr<Lease> lease;
  std::unique_ptr<Handle> parent, ready, permit;
  void Acknowledge();
  void AwaitParent(std::function<DWORD(HANDLE, DWORD)> wait = {},
                   std::function<DWORD(HANDLE, HANDLE, DWORD)> permission = {});
};
// Validator injection is a unit seam, never selectable through the command line.
using ParentValidator = std::function<void(HANDLE, const Paths&)>;
AcceptedTransfer AcceptTransfer(const Paths& paths, TransferHandles handles, ParentValidator parent = {});
struct HandoffPort {
  virtual ~HandoffPort() = default;
  virtual std::unique_ptr<Handle> Spawn(const std::filesystem::path& executable,
                                      const std::wstring& command, const std::array<HANDLE, 5>& handles) = 0;
  virtual DWORD WaitReady(HANDLE ready, HANDLE child, DWORD timeout) = 0;
};
std::unique_ptr<HandoffPort> MakeWindowsHandoffPort();
// Caller must have verified the fixed selected pending executable and its bytes.
// Success means ready acknowledged. Caller exits before opening runtime/database.
void StartPendingHandoff(Lease& lease, const Paths& paths, unsigned slot, HandoffPort& port);
void StartRemovalHandoff(Lease& lease, const Paths& paths, const std::filesystem::path& markedImage, HandoffPort& port);
void LaunchCanonical(const Paths& paths);
}  // namespace sd::install
