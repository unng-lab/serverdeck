#pragma once
#include "security.h"
#include "installation.h"
#include <memory>
namespace sd {
constexpr uint32_t kActivationVersion = 1;
struct ActivationRequest { uint32_t version; wchar_t epoch[37]; wchar_t requestId[37]; };
struct ActivationAck { uint32_t version; uint32_t status; }; // 1 activated, 2 shutting down, 3 storage blocked
struct OwnerLease {
  std::unique_ptr<Handle> lock, mutex, pipe;
  std::wstring epoch;
  std::filesystem::path root;
  ~OwnerLease();
};
std::unique_ptr<OwnerLease> AcquireOwner(const std::filesystem::path& root,
                                      const std::filesystem::path& exe);
// Internal trusted transfer only (not an argv HANDLE adoption API). Caller
// prepares installation while both leases are held, then publishes GUI owner.
std::unique_ptr<OwnerLease> AcquireOwnerFromLease(install::Lease& lease, const install::Paths& paths,
                                                const std::filesystem::path& exe);
// Activation only: if the old owner disappears, do not silently become a new
// owner without the installation/maintenance preflight.
void ActivateOwner(const std::filesystem::path& root);
bool PeerIdentity(HANDLE pipe, bool serverPeer, const std::wstring& user,
                  const std::wstring& logon, DWORD expectedPid = 0,
                  uint64_t expectedCreation = 0);
}
