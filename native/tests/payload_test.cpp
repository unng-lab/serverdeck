#include "payload.h"
#include "security.h"
#include <iostream>
#include <vector>
#include <fstream>
#include <iterator>
#include <algorithm>
#include <cstring>

namespace {
std::vector<uint8_t> Bundle(const std::string& variant = "") {
  std::vector<std::string> paths{"data/app.so", "data/icudtl.dat", "flutter_windows.dll",
                               "libisar.dll", "serverdeck_host.dll"};
  if (variant == "caseAlias") paths.push_back("data/APP.SO");
  if (variant == "invalidUtf8") paths.push_back(std::string("data/") + char(255));
  if (variant == "traversal") paths.push_back("data/../escape");
  if (variant == "missingLibrary") paths.erase(paths.begin() + 3);
  if (variant == "fileLimit")
    for (int i = 0; i < 10001; ++i) paths.push_back("data/extra" + std::to_string(i));
  std::sort(paths.begin(), paths.end());
  std::string manifest = "SDMF001\nhostAbi=1\nplatform=windows-x64\nbuild=e30=\n";
  for (size_t i = 0; i < paths.size(); ++i) {
    const auto size = variant == "sizeOverflow" && i == 0 ? "18446744073709551615" : "0";
    const auto offset = variant == "offsetOverflow" && i == 1 ? "18446744073709551615" : "0";
    const auto hash = variant == "hashMismatch" ? std::string(64, '0') : sd::Sha256(nullptr, 0);
    manifest += "file\t" + std::string(size) + "\t" + offset + "\t" + hash + "\t" + paths[i] + "\n";
  }
  if (variant == "truncatedLine") manifest.pop_back();
  std::vector<uint8_t> bytes(28 + manifest.size());
  std::memcpy(bytes.data(), "SDPKG001", 8);
  const uint32_t format = variant == "futureFormat" ? 2 : 1;
  const uint64_t length = variant == "manifestOverflow" ? UINT64_MAX : manifest.size();
  const uint64_t payloadLength = variant == "payloadLimit" ? 2ull * 1024 * 1024 * 1024 + 1 : 0;
  std::memcpy(bytes.data() + 8, &format, 4);
  std::memcpy(bytes.data() + 12, &length, 8);
  std::memcpy(bytes.data() + 20, &payloadLength, 8);
  std::memcpy(bytes.data() + 28, manifest.data(), manifest.size());
  return bytes;
}
}

int main(int argc, char** argv) {
  for (const auto* path : {L"../x", L"/root", L"a//b", L"CON.dll", L"nul", L"a:stream",
                           L"a\\b", L"a/..", L"x.", L"x ", L"a/", L"COM1.txt"}) {
    if (sd::SafePayloadPath(path)) { std::cerr << "accepted unsafe path"; return 1; }
  }
  if (!sd::SafePayloadPath(L"data/flutter_assets/a.txt")) return 2;
  if (sd::Sha256(nullptr, 0) !=
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") return 3;
  for (size_t length = 0; length < 40; ++length) {
    std::vector<uint8_t> bad(length, 0);
    try { sd::ParsePayload(bad.data(), bad.size()); return 4; } catch (...) {}
  }
  const auto valid = Bundle();
  if (sd::ParsePayload(valid.data(), valid.size()).files.size() != 5) return 12;
  for (const auto* variant : {"caseAlias", "invalidUtf8", "traversal", "missingLibrary",
      "fileLimit", "sizeOverflow", "offsetOverflow", "hashMismatch", "truncatedLine",
      "futureFormat", "manifestOverflow", "payloadLimit"}) {
    const auto bytes = Bundle(variant);
    bool rejected = false;
    try { sd::ParsePayload(bytes.data(), bytes.size()); } catch (...) { rejected = true; }
    if (!rejected) { std::cerr << "Accepted malformed manifest: " << variant; return 13; }
  }
  if (argc == 2) {
    try {
    std::ifstream input(argv[1], std::ios::binary);
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    if (!input || bytes.empty()) return 5;
    const auto payload = sd::ParsePayload(bytes.data(), bytes.size());
    wchar_t temp[MAX_PATH]{};
    if (!GetTempPathW(MAX_PATH, temp)) return 6;
    const auto root = std::filesystem::path(temp) / (L"ServerDeckPayloadTest-" + sd::Uuid());
    sd::SecureDirectory(root);
    try {
      const auto runtime = sd::ExtractPayload(payload, root);
      if (sd::ExtractPayload(payload, root) != runtime) return 7;
      // Corrupt cache must be quarantined and replaced using the same manifest.
      { std::ofstream corrupt(runtime / L"serverdeck_host.dll", std::ios::binary); corrupt << 'x'; }
      if (sd::ExtractPayload(payload, root) != runtime) return 8;
      if (std::filesystem::file_size(runtime / L"serverdeck_host.dll") <= 1) return 9;
      if (std::filesystem::exists(root / L"data")) return 10;
    } catch (...) { std::filesystem::remove_all(sd::ExtendedPath(root)); throw; }
    std::filesystem::remove_all(sd::ExtendedPath(root));
    } catch (const std::exception& error) { std::cerr << error.what(); return 11; }
  }
  return 0;
}
