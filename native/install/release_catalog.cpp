#include "release_catalog.h"
#include <winsock2.h>
#include <ws2tcpip.h>
#include "security.h"
#include "mcp_json.h"
#include <bcrypt.h>
#include <wincrypt.h>
#include <winhttp.h>
#include <algorithm>
#include <cstring>
#include <limits>
#include <set>
#include <sstream>

namespace sd::updates {
namespace {
[[noreturn]] void Invalid() { throw Failure("INVALID_CATALOG"); }
uint64_t Number(const std::string& value, uint64_t maximum = INT64_MAX) {
  if (value.empty() || value.size() > 20 || (value.size() > 1 && value[0] == '0')) Invalid();
  uint64_t result = 0;
  for (const auto c : value) {
    if (c < '0' || c > '9') Invalid();
    const auto digit = static_cast<uint64_t>(c - '0');
    if (digit > maximum || result > (maximum - digit) / 10) Invalid();
    result = result * 10 + digit;
  }
  return result;
}
bool LowerHex(const std::string& value, size_t length) {
  return value.size() == length && value.find_first_not_of("0123456789abcdef") == std::string::npos;
}
std::vector<uint8_t> Unhex(const std::string& value, size_t bytes) {
  if (!LowerHex(value, bytes * 2)) Invalid();
  std::vector<uint8_t> result(bytes);
  for (size_t i = 0; i < bytes; ++i) {
    const auto nibble = [](char c) { return c <= '9' ? c - '0' : c - 'a' + 10; };
    result[i] = static_cast<uint8_t>((nibble(value[i * 2]) << 4) | nibble(value[i * 2 + 1]));
  }
  return result;
}
bool KeyId(const std::string& value) {
  return !value.empty() && value.size() <= 32 &&
    value.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789-") == std::string::npos;
}
bool Host(const std::string& value) {
  if (value.empty() || value.size() > 253 || value.front() == '.' || value.back() == '.' ||
      value.find('.') == std::string::npos ||
      value.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789.-") != std::string::npos ||
      value.find_first_not_of("0123456789.") == std::string::npos) return false;
  // Windows accepts numeric aliases such as 0x7f.0.0.1. AI_NUMERICHOST
  // classifies them without ever making a DNS/network request.
  WSADATA sockets{};
  if (WSAStartup(MAKEWORD(2, 2), &sockets) != 0) Invalid();
  ADDRINFOW hints{}; hints.ai_flags = AI_NUMERICHOST;
  ADDRINFOW* address = nullptr;
  const auto wide = Wide(value);
  const int numeric = GetAddrInfoW(wide.c_str(), nullptr, &hints, &address);
  if (address) FreeAddrInfoW(address);
  WSACleanup();
  if (numeric == 0) return false;
  if (numeric != WSAHOST_NOT_FOUND) Invalid();
  size_t start = 0;
  while (start < value.size()) {
    const auto end = value.find('.', start);
    const auto length = (end == std::string::npos ? value.size() : end) - start;
    if (!length || length > 63 || value[start] == '-' || value[start + length - 1] == '-') return false;
    if (end == std::string::npos) break;
    start = end + 1;
  }
  return true;
}
struct Algorithm {
  BCRYPT_ALG_HANDLE value = nullptr;
  Algorithm() {
    if (BCryptOpenAlgorithmProvider(&value, BCRYPT_ECDSA_P256_ALGORITHM, nullptr, 0) < 0)
      throw Failure("SOURCE_UNTRUSTED");
  }
  ~Algorithm() { if (value) BCryptCloseAlgorithmProvider(value, 0); }
};
struct Key {
  BCRYPT_KEY_HANDLE value = nullptr;
  ~Key() { if (value) BCryptDestroyKey(value); }
};
bool Verify(const std::string& publicHex, const std::string& payload,
            const std::string* signatureHex) {
  Algorithm algorithm;
  const auto coordinates = Unhex(publicHex, 64);
  BCRYPT_ECCKEY_BLOB header{BCRYPT_ECDSA_PUBLIC_P256_MAGIC, 32};
  std::vector<uint8_t> blob(sizeof(header) + coordinates.size());
  std::memcpy(blob.data(), &header, sizeof(header));
  std::memcpy(blob.data() + sizeof(header), coordinates.data(), coordinates.size());
  Key key;
  if (BCryptImportKeyPair(algorithm.value, nullptr, BCRYPT_ECCPUBLIC_BLOB, &key.value,
      blob.data(), static_cast<ULONG>(blob.size()), 0) < 0) return false;
  if (!signatureHex) return true;
  const auto digest = Unhex(Sha256(reinterpret_cast<const uint8_t*>(payload.data()), payload.size()), 32);
  const auto signature = Unhex(*signatureHex, 64);
  return BCryptVerifySignature(key.value, nullptr, const_cast<PUCHAR>(digest.data()),
    static_cast<ULONG>(digest.size()), const_cast<PUCHAR>(signature.data()),
    static_cast<ULONG>(signature.size()), 0) >= 0;
}
std::string Notes(const std::string& text) {
  if (text.empty()) return {};
  if (text.size() > 21848 || text.size() % 4) Invalid();
  DWORD length = 0;
  if (!CryptStringToBinaryA(text.c_str(), static_cast<DWORD>(text.size()),
      CRYPT_STRING_BASE64 | CRYPT_STRING_STRICT, nullptr, &length, nullptr, nullptr) || length > 16384) Invalid();
  std::string decoded(length, '\0');
  if (!CryptStringToBinaryA(text.c_str(), static_cast<DWORD>(text.size()),
      CRYPT_STRING_BASE64 | CRYPT_STRING_STRICT, reinterpret_cast<BYTE*>(decoded.data()),
      &length, nullptr, nullptr) || !mcp::ValidUtf8(decoded) || decoded.find('\0') != std::string::npos) Invalid();
  // Roundtrip makes the wire encoding canonical (no whitespace or trailing bits).
  DWORD encodedLength = 0;
  CryptBinaryToStringA(reinterpret_cast<const BYTE*>(decoded.data()), length,
    CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, nullptr, &encodedLength);
  std::string encoded(encodedLength, '\0');
  if (!CryptBinaryToStringA(reinterpret_cast<const BYTE*>(decoded.data()), length,
      CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, encoded.data(), &encodedLength)) Invalid();
  if (!encoded.empty() && encoded.back() == '\0') encoded.pop_back();
  if (encoded != text) Invalid();
  return decoded;
}
class Lines {
 public:
  explicit Lines(const std::string& text) : stream_(text) {
    if (text.empty() || text.size() > kCatalogLimit || text.back() != '\n' ||
        text.find('\r') != std::string::npos || text.find('\0') != std::string::npos) Invalid();
    for (const unsigned char c : text) if (c != '\n' && (c < 32 || c > 126)) Invalid();
  }
  std::string Next() { std::string out; if (!std::getline(stream_, out)) Invalid(); return out; }
  void Finish() { std::string extra; if (std::getline(stream_, extra)) Invalid(); }
 private:
  std::istringstream stream_;
};
}  // namespace

Version ParseVersion(const std::string& value) {
  Version version;
  size_t start = 0;
  for (size_t i = 0; i < 3; ++i) {
    const auto end = i == 2 ? value.size() : value.find('.', start);
    if (end == std::string::npos || end <= start || end - start > 5) Invalid();
    version.parts[i] = static_cast<uint16_t>(Number(value.substr(start, end - start), 65535));
    start = end + 1;
  }
  version.text = value;
  return version;
}
std::string HttpsHost(const std::string& url) {
  if (url.empty() || url.size() > 2048 || url.rfind("https://", 0) != 0 ||
      url.find('#') != std::string::npos || url.find('\\') != std::string::npos) Invalid();
  for (const unsigned char c : url) if (c < 33 || c > 126) Invalid();
  const auto authorityEnd = url.find_first_of("/?", 8);
  if (url.substr(8, authorityEnd == std::string::npos ? std::string::npos : authorityEnd - 8)
      .find('@') != std::string::npos) Invalid();
  const auto wide = Wide(url);
  URL_COMPONENTS parts{}; parts.dwStructSize = sizeof(parts);
  parts.dwHostNameLength = parts.dwUserNameLength = parts.dwPasswordLength = static_cast<DWORD>(-1);
  if (!WinHttpCrackUrl(wide.c_str(), static_cast<DWORD>(wide.size()), 0, &parts) ||
      parts.nScheme != INTERNET_SCHEME_HTTPS || parts.nPort != INTERNET_DEFAULT_HTTPS_PORT ||
      parts.dwUserNameLength || parts.dwPasswordLength) Invalid();
  const auto host = Utf8(std::wstring(parts.lpszHostName, parts.dwHostNameLength));
  if (!Host(host)) Invalid();
  return host;
}
bool AllowedDownload(const Policy& policy, const std::string& url) {
  const auto host = HttpsHost(url);
  return std::find(policy.downloadHosts.begin(), policy.downloadHosts.end(), host) != policy.downloadHosts.end();
}
Policy ParsePolicy(const std::string& text) {
  try {
    if (text.empty() || text.size() > 8192) Invalid();
    const auto json = mcp::Decode(text);
    if (json.object().size() != 5 || json.at("schema").integer() != 1) Invalid();
    Policy policy;
    policy.endpoint = json.at("endpoint").string();
    HttpsHost(policy.endpoint);
    const auto format = json.at("storeFormat").integer();
    if (format <= 0 || format > UINT32_MAX) Invalid();
    policy.storeFormat = static_cast<uint32_t>(format);
    const auto& hosts = std::get<mcp::Json::Array>(json.at("downloadHosts").value);
    if (hosts.empty() || hosts.size() > 8) Invalid();
    for (const auto& entry : hosts) {
      const auto& host = entry.string();
      if (!Host(host) || std::find(policy.downloadHosts.begin(), policy.downloadHosts.end(), host) != policy.downloadHosts.end()) Invalid();
      policy.downloadHosts.push_back(host);
    }
    const auto& keys = std::get<mcp::Json::Array>(json.at("keys").value);
    if (keys.empty() || keys.size() > 3) Invalid();
    for (const auto& entry : keys) {
      if (entry.object().size() != 2) Invalid();
      const auto& id = entry.at("id").string();
      const auto& key = entry.at("p256").string();
      if (!KeyId(id) || !Verify(key, {}, nullptr) || !policy.publicKeys.emplace(id, key).second) Invalid();
    }
    return policy;
  } catch (const Failure&) { throw; }
  catch (...) { Invalid(); }
}
Catalog ParseCatalog(const std::string& envelope, const Policy& policy, uint64_t now) {
  Lines header(envelope);
  const auto format = header.Next();
  if (format != "SDCATALOG001" && format != "SDCATALOG002") Invalid();
  const auto id = header.Next(), signature = header.Next();
  if (!KeyId(id) || !LowerHex(signature, 128)) Invalid();
  const auto key = policy.publicKeys.find(id);
  if (key == policy.publicKeys.end()) throw Failure("SOURCE_UNTRUSTED");
  size_t offset = 0;
  for (int i = 0; i < 3; ++i) offset = envelope.find('\n', offset) + 1;
  const auto payload = envelope.substr(offset);
  if (!Verify(key->second, payload, &signature)) throw Failure("SOURCE_UNTRUSTED");
  Lines lines(payload);
  const bool staticCatalog = format == "SDCATALOG002";
  if (lines.Next() != (staticCatalog ? "SDRELEASES002" : "SDRELEASES001")) Invalid();
  Catalog catalog;
  catalog.protocol = staticCatalog ? 2 : 1;
  catalog.issued = Number(lines.Next());
  if (!staticCatalog) catalog.expires = Number(lines.Next());
  if ((catalog.issued > now && catalog.issued - now > 300) ||
      (!staticCatalog && (catalog.issued > catalog.expires ||
        catalog.expires - catalog.issued > 7 * 86400 || catalog.expires <= now)))
    throw Failure("SOURCE_EXPIRED");
  const auto count = Number(lines.Next(), 32);
  std::set<std::string> ids;
  for (uint64_t i = 0; i < count; ++i) {
    Release r;
    r.version = ParseVersion(lines.Next());
    if (!ids.insert(r.version.text).second) Invalid();
    r.platform = lines.Next();
    if (r.platform != "windows-x64") throw Failure("RELEASE_INCOMPATIBLE");
    r.bootstrapAbi = static_cast<uint32_t>(Number(lines.Next(), UINT32_MAX));
    r.storeFormat = static_cast<uint32_t>(Number(lines.Next(), UINT32_MAX));
    r.published = Number(lines.Next());
    r.setupSize = Number(lines.Next(), kArtifactLimit); r.setupHash = lines.Next();
    r.appSize = Number(lines.Next(), kArtifactLimit); r.appHash = lines.Next();
    r.url = lines.Next(); r.notes = Notes(lines.Next());
    if (!r.setupSize || !r.appSize || r.published > catalog.issued ||
        !LowerHex(r.setupHash, 64) || !LowerHex(r.appHash, 64) || !AllowedDownload(policy, r.url)) Invalid();
    catalog.releases.push_back(std::move(r));
  }
  lines.Finish(); catalog.signedBytes = envelope;
  return catalog;
}
bool Compatible(const Release& release, const Policy& policy) {
  return release.platform == "windows-x64" && release.bootstrapAbi == 1 && release.storeFormat == policy.storeFormat;
}
bool SameIdentity(const Release& a, const Release& b) {
  return a.version == b.version && a.platform == b.platform && a.bootstrapAbi == b.bootstrapAbi &&
    a.storeFormat == b.storeFormat && a.published == b.published && a.setupSize == b.setupSize &&
    a.appSize == b.appSize && a.setupHash == b.setupHash && a.appHash == b.appHash && a.url == b.url && a.notes == b.notes;
}
const Release* LatestCompatible(const Catalog& catalog, const Policy& policy, const Version& installed) {
  const Release* latest = nullptr;
  for (const auto& r : catalog.releases)
    if (Compatible(r, policy) && installed < r.version && (!latest || latest->version < r.version)) latest = &r;
  return latest;
}
const Release* FindConsented(const Catalog& catalog, const Release& consented, const Policy& policy) {
  for (const auto& r : catalog.releases) if (r.version == consented.version) {
    if (!SameIdentity(r, consented)) throw Failure("SOURCE_CHANGED");
    if (!Compatible(r, policy)) throw Failure("RELEASE_INCOMPATIBLE");
    return &r;
  }
  throw Failure("RELEASE_REVOKED");
}
}  // namespace sd::updates
