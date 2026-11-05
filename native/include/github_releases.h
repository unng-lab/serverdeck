#pragma once
#include "update_service.h"

namespace sd::updates {
inline constexpr char kGitHubLatest[] = "https://api.github.com/repos/unng-lab/serverdeck/releases/latest";
struct MetadataRequest {
  std::string url, headers;
  size_t limit = 0;
  uint64_t deadline = 0;
};
struct MetadataResponse {
  uint32_t status = 0;
  std::string location, body;
};
struct MetadataTransport {
  virtual ~MetadataTransport() = default;
  // No automatic redirects/retries/auth. The bounded body and any async buffers
  // remain owned until the request is fully closed, including cancellation.
  virtual MetadataResponse Get(const MetadataRequest&, const std::atomic<bool>&) = 0;
};
void ValidateGitHubPolicy(const Policy& policy);
std::unique_ptr<MetadataTransport> MakeWinHttpMetadataTransport(const Version& current);
class GitHubReleaseSource final : public CatalogSource {
 public:
  using Clock = std::function<uint64_t()>;
  GitHubReleaseSource(Policy policy, Version current, std::unique_ptr<MetadataTransport> transport,
                      Clock monotonic = {}, Clock utc = {});
  std::string Fetch(const std::atomic<bool>& cancel) override;
  std::string FetchFor(const Release& consent, const std::atomic<bool>& cancel) override;
 private:
  std::string FetchImpl(const Release*, const std::atomic<bool>&);
  MetadataResponse Get(const std::string& url, bool api, size_t limit, uint64_t deadline,
                       const std::atomic<bool>& cancel);
  void Gate(uint64_t deadline, const std::atomic<bool>& cancel) const;
  Policy policy_;
  Version current_;
  std::unique_ptr<MetadataTransport> transport_;
  Clock monotonic_, utc_;
};
}  // namespace sd::updates
