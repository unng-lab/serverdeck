#pragma once
#include "release_catalog.h"
#include <atomic>
#include <functional>
#include <memory>
#include <optional>

namespace sd::updates {
struct ArtifactHeaders {
  uint32_t status = 0;
  std::optional<uint64_t> length;
  std::string location;
};
struct ArtifactRequest {
  virtual ~ArtifactRequest() = default;
  virtual ArtifactHeaders Start(uint64_t deadline, const std::atomic<bool>& cancel) = 0;
  virtual size_t Read(uint8_t* bytes, size_t capacity, uint64_t deadline, const std::atomic<bool>& cancel) = 0;
};
struct ArtifactTransport {
  virtual ~ArtifactTransport() = default;
  virtual std::unique_ptr<ArtifactRequest> Open(const std::string& url) = 0;
};
using ArtifactSink = std::function<void(const uint8_t*, size_t)>;
using ArtifactProgress = std::function<void(uint64_t, std::optional<uint64_t>)>;
using TransferClock = std::function<uint64_t()>;
void RequireDownloadUrl(const Policy& policy, const std::string& url);
std::string ResolveDownloadRedirect(const Policy& policy, const std::string& base, const std::string& location);
std::unique_ptr<ArtifactTransport> MakeWinHttpArtifactTransport(const Policy& policy, const Version& current);
// Streams only a consented, signed identity; successful return means full exact
// length/SHA256 verification. Publication/PE-resource validation remain with store.
void TransferArtifact(const Policy& policy, const Release& release, ArtifactTransport& transport,
                      const std::atomic<bool>& cancel, const ArtifactSink& sink,
                      ArtifactProgress progress = {}, TransferClock clock = {});
}  // namespace sd::updates
