#pragma once
#include <filesystem>
#include <string>
#include <vector>
#include <cstdint>
namespace sd {
struct PayloadFile {
  std::wstring path;
  uint64_t size, offset;
  std::string hash;
};
struct Payload {
  std::string id;
  std::vector<PayloadFile> files;
  const uint8_t* data;
  size_t length;
};
bool SafePayloadPath(const std::wstring& path);
Payload ParsePayload(const uint8_t* bytes, size_t length);
std::filesystem::path ExtractPayload(const Payload& payload,
                                   const std::filesystem::path& root);
}
