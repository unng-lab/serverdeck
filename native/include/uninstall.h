#pragma once
#include "install_executor.h"

namespace sd::install {
struct RemovalTicket { std::string id, commitHash; Installation target; };
std::string EncodeRemovalTicket(const RemovalTicket& ticket);
RemovalTicket DecodeRemovalTicket(const std::string& bytes);
std::filesystem::path RemovalCacheRoot(const Paths& paths);
std::filesystem::path PrepareRemovalCache(Files& files, Lease& lease, const Installation& current, Bytes setup);
RemovalTicket ReadRemovalTicket(const Paths& paths, const std::filesystem::path& image);
RemovalTicket ReadRemovalCache(const Paths& paths, const std::filesystem::path& image, const Package& package);
std::optional<std::filesystem::path> FindInterruptedRemoval(Files& files, Lease& lease, SetupValidator validator);
void LaunchRemovalRetry(const Paths& paths, const std::filesystem::path& image);
struct RemovalResult {
  std::vector<std::wstring> remaining;
  bool complete() const { return remaining.empty(); }
};
// Requires both leases. The callback durably registers the marked temporary
// helper's fixed retry command before any owned installation file is removed.
RemovalResult RemoveInstallation(Files& files, Lease& lease, Registration& registration,
    const RemovalTicket& ticket, const std::function<void()>& preserveRetry, Checkpoint checkpoint = {});
}
