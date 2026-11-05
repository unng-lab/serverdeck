#include "artifact_transfer.h"
#include "security.h"
#include <algorithm>
#include <array>
#include <bcrypt.h>
#include <shlwapi.h>

namespace sd::updates {
namespace {
class Digest {
 public:
  Digest() {
    if (BCryptOpenAlgorithmProvider(&algorithm_, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) throw Failure("STORAGE_IO");
    if (BCryptCreateHash(algorithm_, &hash_, nullptr, 0, nullptr, 0, 0) < 0) {
      BCryptCloseAlgorithmProvider(algorithm_, 0); algorithm_ = nullptr; throw Failure("STORAGE_IO");
    }
  }
  ~Digest() { if (hash_) BCryptDestroyHash(hash_); if (algorithm_) BCryptCloseAlgorithmProvider(algorithm_, 0); }
  void Add(const uint8_t* bytes, size_t count) {
    if (BCryptHashData(hash_, const_cast<uint8_t*>(bytes), static_cast<ULONG>(count), 0) < 0) throw Failure("STORAGE_IO");
  }
  std::string Finish() {
    std::array<uint8_t, 32> bytes{};
    if (BCryptFinishHash(hash_, bytes.data(), static_cast<ULONG>(bytes.size()), 0) < 0) throw Failure("STORAGE_IO");
    std::string result; constexpr char hex[] = "0123456789abcdef";
    for (const auto byte : bytes) { result += hex[byte >> 4]; result += hex[byte & 15]; }
    return result;
  }
 private:
  BCRYPT_ALG_HANDLE algorithm_ = nullptr;
  BCRYPT_HASH_HANDLE hash_ = nullptr;
};
void Gate(const std::atomic<bool>& cancel, uint64_t now, uint64_t deadline) {
  if (cancel.load()) throw Failure("CANCELLED");
  if (now >= deadline) throw Failure("TIMEOUT");
}
uint64_t Deadline(uint64_t now, uint64_t interval, uint64_t wall) {
  return now > wall || wall - now < interval ? wall : now + interval;
}
bool Redirect(uint32_t status) { return status == 301 || status == 302 || status == 303 || status == 307 || status == 308; }
}
void RequireDownloadUrl(const Policy& policy, const std::string& url) {
  try { if (AllowedDownload(policy, url)) return; } catch (const Failure&) {}
  throw Failure("SOURCE_UNTRUSTED");
}
std::string ResolveDownloadRedirect(const Policy& policy, const std::string& base, const std::string& location) {
  RequireDownloadUrl(policy, base);
  if (location.empty() || location.size() > 2048 ||
      location.find_first_of("\r\n\t\\#") != std::string::npos || location.find('\0') != std::string::npos)
    throw Failure("SOURCE_UNTRUSTED");
  const auto wideBase = sd::Wide(base), relative = sd::Wide(location);
  std::array<wchar_t, 2049> combined{}; DWORD size = static_cast<DWORD>(combined.size());
  if (FAILED(UrlCombineW(wideBase.c_str(), relative.c_str(), combined.data(), &size, 0)) || size >= combined.size())
    throw Failure("SOURCE_UNTRUSTED");
  const auto result = sd::Utf8(std::wstring(combined.data(), size));
  RequireDownloadUrl(policy, result);
  return result;
}
void TransferArtifact(const Policy& policy, const Release& release, ArtifactTransport& transport,
    const std::atomic<bool>& cancel, const ArtifactSink& sink, ArtifactProgress progress, TransferClock clock) {
  if (!sink) throw Failure("STORAGE_IO");
  if (!Compatible(release, policy) || !(ParseVersion(release.version.text) == release.version)) throw Failure("RELEASE_INCOMPATIBLE");
  if (!release.setupSize || release.setupSize > kArtifactLimit || release.setupHash.size() != 64 ||
      release.setupHash.find_first_not_of("0123456789abcdef") != std::string::npos) throw Failure("INVALID_ARTIFACT");
  RequireDownloadUrl(policy, release.url);
  if (!clock) clock = [] { return GetTickCount64(); };
  const auto started = clock();
  if (started > UINT64_MAX - 1800000) throw Failure("TIMEOUT");
  const uint64_t wall = started + 1800000;
  std::string url = release.url;
  // Keep buffer alive until request destruction, even if async cancellation
  // races with a read callback that is still completing into these bytes.
  std::array<uint8_t, 65536> buffer{};
  for (unsigned redirects = 0;; ++redirects) {
    Gate(cancel, clock(), wall);
    auto request = transport.Open(url); if (!request) throw Failure("NETWORK_UNAVAILABLE");
    const auto headerDeadline = Deadline(clock(), 30000, wall);
    const auto headers = request->Start(headerDeadline, cancel);
    Gate(cancel, clock(), headerDeadline);
    if (Redirect(headers.status)) {
      if (redirects >= 3) throw Failure("SOURCE_UNTRUSTED");
      url = ResolveDownloadRedirect(policy, url, headers.location); continue;
    }
    if (headers.status != 200) throw Failure("NETWORK_UNAVAILABLE");
    if (headers.length && *headers.length != release.setupSize) throw Failure("INVALID_ARTIFACT");
    if (progress) progress(0, headers.length);
    Digest digest; uint64_t received = 0;
    for (;;) {
      Gate(cancel, clock(), wall);
      const auto idleDeadline = Deadline(clock(), 60000, wall);
      const auto count = request->Read(buffer.data(), buffer.size(), idleDeadline, cancel);
      Gate(cancel, clock(), idleDeadline);
      if (!count) break;
      if (count > buffer.size() || count > release.setupSize - received) throw Failure("INVALID_ARTIFACT");
      digest.Add(buffer.data(), count); sink(buffer.data(), count); received += count;
      Gate(cancel, clock(), wall);
      if (progress) progress(received, headers.length);
    }
    if (received != release.setupSize || digest.Finish() != release.setupHash) throw Failure("INVALID_ARTIFACT");
    Gate(cancel, clock(), wall); return;
  }
}
}  // namespace sd::updates
