#include "release_catalog.h"
#include "security.h"
#include "mcp_json.h"
#include <bcrypt.h>
#include <cstring>
#include <functional>
#include <iostream>

namespace {
void Require(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
std::string Hex(const std::vector<uint8_t>& bytes) {
  constexpr char digits[] = "0123456789abcdef";
  std::string result;
  for (const auto c : bytes) { result += digits[c >> 4]; result += digits[c & 15]; }
  return result;
}
std::vector<uint8_t> Digest(const std::string& text) {
  const auto hex = sd::Sha256(reinterpret_cast<const uint8_t*>(text.data()), text.size());
  std::vector<uint8_t> result(32);
  for (size_t i = 0; i < result.size(); ++i)
    result[i] = static_cast<uint8_t>(std::stoul(hex.substr(i * 2, 2), nullptr, 16));
  return result;
}
class Signer {
 public:
  Signer() {
    Require(BCryptOpenAlgorithmProvider(&algorithm_, BCRYPT_ECDSA_P256_ALGORITHM, nullptr, 0) >= 0, "algorithm");
    Require(BCryptGenerateKeyPair(algorithm_, &key_, 256, 0) >= 0 && BCryptFinalizeKeyPair(key_, 0) >= 0, "keypair");
  }
  ~Signer() { if (key_) BCryptDestroyKey(key_); if (algorithm_) BCryptCloseAlgorithmProvider(algorithm_, 0); }
  std::string Public() const {
    ULONG length = 0;
    Require(BCryptExportKey(key_, nullptr, BCRYPT_ECCPUBLIC_BLOB, nullptr, 0, &length, 0) >= 0, "public size");
    std::vector<uint8_t> blob(length);
    Require(BCryptExportKey(key_, nullptr, BCRYPT_ECCPUBLIC_BLOB, blob.data(), length, &length, 0) >= 0 && length == 72, "public export");
    return Hex(std::vector<uint8_t>(blob.begin() + sizeof(BCRYPT_ECCKEY_BLOB), blob.end()));
  }
  std::string Envelope(const std::string& payload, const std::string& id = "test-key") const {
    auto digest = Digest(payload);
    std::vector<uint8_t> signature(64); ULONG length = 0;
    Require(BCryptSignHash(key_, nullptr, digest.data(), 32, signature.data(), 64, &length, 0) >= 0 && length == 64, "sign");
    const auto format = payload.rfind("SDRELEASES002\n", 0) == 0 ? "SDCATALOG002\n" : "SDCATALOG001\n";
    return format + id + "\n" + Hex(signature) + "\n" + payload;
  }
 private:
  BCRYPT_ALG_HANDLE algorithm_ = nullptr;
  BCRYPT_KEY_HANDLE key_ = nullptr;
};
std::string PolicyJson(const Signer& signer) {
  return "{\"schema\":1,\"endpoint\":\"https://updates.example.test/stable\","
    "\"downloadHosts\":[\"assets.example.test\"],\"storeFormat\":2,\"keys\":[{"
    "\"id\":\"test-key\",\"p256\":\"" + signer.Public() + "\"}]}";
}
std::string Record(const std::string& version, const std::string& hash = std::string(64, 'a'),
                   const std::string& abi = "1", const std::string& size = "12") {
  return version + "\nwindows-x64\n" + abi + "\n2\n99900\n" + size + "\n" + hash +
    "\n10\n" + std::string(64, 'b') + "\nhttps://assets.example.test/ServerDeckSetup.exe\n0KLQtdGB0YI=\n";
}
std::string Payload(const std::string& records, const std::string& count = "1",
                    const std::string& expires = "100100", const std::string& issued = "99990") {
  return "SDRELEASES001\n" + issued + "\n" + expires + "\n" + count + "\n" + records;
}
void Reject(const std::function<void()>& action, const std::string& code = {}) {
  try { action(); } catch (const sd::updates::Failure& e) {
    Require(code.empty() || e.what() == code, "wrong failure code"); return;
  }
  throw std::runtime_error("malformed input accepted");
}
}  // namespace
int main() {
  using namespace sd::updates;
  try {
    const Signer signer;
    const auto policyJson = PolicyJson(signer);
    const auto policy = ParsePolicy(policyJson);
    Require(ParseVersion("1.10.0+1").parts[1] == 10, "version fields");
    Require(ParseVersion("1.2.0+2") < ParseVersion("1.2.0+10"), "numeric build ordering");
    for (const auto* bad : {"1.2.3", "01.2.3+4", "1.2.3+04", "65536.0.0+1", "1.2.3+-1",
        "1.2.3+1x", "1.2.3+1\n", "1.2.3+1+2", "1.2.3.4+5", "0.0.0+", ""})
      Reject([&] { ParseVersion(bad); });
    for (const auto* bad : {"http://assets.example.test/a", "https://user:pw@assets.example.test/a",
        "https://@assets.example.test/a",
        "https://assets.example.test:444/a", "https://assets.example.test/a#x", "https://127.0.0.1/a",
        "https://0x7f.0.0.1/a", "https://0x7f.0.0.0x1/a", "https://0x7f000001/a", "https://0177.0.0.1/a",
        "https://assets.example.test\\@other.test/a", "https://a..example.test/a"})
      Reject([&] { HttpsHost(bad); });
    Require(!AllowedDownload(policy, "https://other.example.test/a"), "host allowlist");
    for (const auto& bad : {std::string("{}"), policyJson + "x", std::string(8193, ' '),
        std::string("{\"schema\":1,\"schema\":1}")}) Reject([&] { ParsePolicy(bad); });
    auto policyObject = sd::mcp::Decode(policyJson);
    auto hosts = sd::mcp::Json::Array{sd::mcp::Json("assets.example.test"), sd::mcp::Json("assets.example.test")};
    auto changed = policyObject.object(); changed["downloadHosts"] = sd::mcp::Json(hosts);
    Reject([&] { ParsePolicy(sd::mcp::Encode(sd::mcp::Json(changed))); });
    changed = policyObject.object(); changed["unknown"] = true;
    Reject([&] { ParsePolicy(sd::mcp::Encode(sd::mcp::Json(changed))); });
    for (const auto* alias : {"0x7f.0.0.1", "0x7f.0.0.0x1", "0x7f000001", "0177.0.0.1"}) {
      changed = policyObject.object();
      changed["downloadHosts"] = sd::mcp::Json(sd::mcp::Json::Array{sd::mcp::Json(alias)});
      Reject([&] { ParsePolicy(sd::mcp::Encode(sd::mcp::Json(changed))); });
    }

    const auto goodPayload = Payload(Record("0.2.0+2"));
    const auto envelope = signer.Envelope(goodPayload);
    const auto catalog = ParseCatalog(envelope, policy, 100000);
    const auto staticPayload = "SDRELEASES002\n99990\n1\n" + Record("0.2.0+2");
    const auto staticEnvelope = signer.Envelope(staticPayload);
    const auto staticCatalog = ParseCatalog(staticEnvelope, policy, 100000 + 365 * 86400);
    Require(staticCatalog.protocol == 2 && !staticCatalog.expires &&
      SameIdentity(catalog.releases.front(), staticCatalog.releases.front()), "static catalog expires or changes identity");
    Reject([&] { ParseCatalog(signer.Envelope("SDRELEASES002\n100301\n0\n"), policy, 100000); }, "SOURCE_EXPIRED");
    Require(ParseCatalog(signer.Envelope("SDRELEASES002\n100300\n0\n"), policy, 100000).releases.empty(), "static skew boundary");
    auto crossed = staticEnvelope; crossed.replace(0, 12, "SDCATALOG001");
    Reject([&] { ParseCatalog(crossed, policy, 100000); }, "INVALID_CATALOG");
    auto staticTamper = staticEnvelope; staticTamper[staticTamper.size() - 3] = 'A';
    Reject([&] { ParseCatalog(staticTamper, policy, 100000); }, "SOURCE_UNTRUSTED");
    Require(catalog.releases.size() == 1 && catalog.releases[0].notes == sd::Utf8(L"Тест"), "catalog decode");
    const auto* offer = LatestCompatible(catalog, policy, ParseVersion("0.1.0+1"));
    Require(offer && offer->setupSize == 12 && offer->published == 99900, "signed offer fields");
    Require(FindConsented(catalog, *offer, policy) == &catalog.releases[0], "consent lookup");
    Require(!LatestCompatible(catalog, policy, ParseVersion("0.2.0+2")), "equal version offered");
    Require(!LatestCompatible(catalog, policy, ParseVersion("1.0.0+1")), "downgrade offered");
    const auto unordered = ParseCatalog(signer.Envelope(Payload(Record("0.10.0+1") + Record("0.3.0+20"), "2")), policy, 100000);
    Require(LatestCompatible(unordered, policy, ParseVersion("0.1.0+1"))->version.text == "0.10.0+1", "feed order selected");
    const auto empty = ParseCatalog(signer.Envelope(Payload("", "0")), policy, 100000);
    Require(empty.releases.empty(), "empty catalog");
    Reject([&] { FindConsented(empty, *offer, policy); }, "RELEASE_REVOKED");
    const auto rebound = ParseCatalog(signer.Envelope(Payload(Record("0.2.0+2", std::string(64, 'c')))), policy, 100000);
    Reject([&] { FindConsented(rebound, *offer, policy); }, "SOURCE_CHANGED");
    auto incompatible = catalog.releases[0]; incompatible.storeFormat = 3;
    Require(!Compatible(incompatible, policy), "incompatible store accepted");
    auto altered = envelope; altered[altered.size() - 3] = 'A';
    Reject([&] { ParseCatalog(altered, policy, 100000); }, "SOURCE_UNTRUSTED");
    Reject([&] { ParseCatalog(signer.Envelope(goodPayload, "unknown"), policy, 100000); }, "SOURCE_UNTRUSTED");
    const Signer other;
    Reject([&] { ParseCatalog(other.Envelope(goodPayload), policy, 100000); }, "SOURCE_UNTRUSTED");
    Reject([&] { ParseCatalog(signer.Envelope(Payload(Record("0.2.0+2"), "1", "100000")), policy, 100000); }, "SOURCE_EXPIRED");
    Reject([&] { ParseCatalog(signer.Envelope(Payload("", "0", "1001000")), policy, 100000); }, "SOURCE_EXPIRED");
    Reject([&] { ParseCatalog(signer.Envelope(Payload("", "0", "101000", "100301")), policy, 100000); }, "SOURCE_EXPIRED");
    for (const auto& badPayload : {
        Payload(Record("0.2.0+2") + Record("0.2.0+2"), "2"), Payload("", "33"),
        Payload(Record("0.2.0+2", std::string(64, 'a'), "1", "1073741825")),
        Payload(Record("0.2.0+2", std::string(64, 'A'))), Payload(Record("0.2.0+2")) + "extra\n"})
      Reject([&] { ParseCatalog(signer.Envelope(badPayload), policy, 100000); });
    Reject([&] { ParseCatalog(envelope + "\r", policy, 100000); });
    Reject([&] { ParseCatalog(std::string(kCatalogLimit + 1, 'x'), policy, 100000); });
    std::cout << "release catalog unit checks passed\n";
    return 0;
  } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}
