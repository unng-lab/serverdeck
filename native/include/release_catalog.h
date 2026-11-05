#pragma once
#include <array>
#include <cstdint>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>

namespace sd::updates {
constexpr size_t kCatalogLimit = 128 * 1024;
constexpr uint64_t kArtifactLimit = 1024ull * 1024 * 1024;
class Failure : public std::runtime_error {
 public:
  explicit Failure(const char* code) : std::runtime_error(code) {}
};
struct Version {
  std::array<uint16_t, 4> parts{};
  std::string text;
  bool operator<(const Version& other) const { return parts < other.parts; }
  bool operator==(const Version& other) const { return parts == other.parts; }
};
Version ParseVersion(const std::string& value);
struct Policy {
  std::string endpoint;
  std::vector<std::string> downloadHosts;
  std::map<std::string, std::string> publicKeys;
  uint32_t storeFormat = 0;
};
Policy ParsePolicy(const std::string& json);
std::string HttpsHost(const std::string& url);
bool AllowedDownload(const Policy& policy, const std::string& url);
struct Release {
  Version version;
  std::string platform, setupHash, appHash, url, notes;
  uint32_t bootstrapAbi = 0, storeFormat = 0;
  uint64_t published = 0, setupSize = 0, appSize = 0;
};
struct Catalog {
  uint32_t protocol = 1;
  uint64_t issued = 0, expires = 0;
  std::string signedBytes;
  std::vector<Release> releases;
};
Catalog ParseCatalog(const std::string& envelope, const Policy& policy, uint64_t now);
bool Compatible(const Release& release, const Policy& policy);
bool SameIdentity(const Release& a, const Release& b);
const Release* LatestCompatible(const Catalog& catalog, const Policy& policy,
                                const Version& installed);
const Release* FindConsented(const Catalog& catalog, const Release& consented,
                             const Policy& policy);
}  // namespace sd::updates
