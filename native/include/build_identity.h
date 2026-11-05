#pragma once
#include "installation.h"

namespace sd::install {
std::optional<std::string> ParseRawResource(const uint8_t* bytes, size_t size, const std::wstring& name, size_t limit);
updates::Version DecodeBuildVersion(const std::string& bytes);
updates::Version ReadBuildVersion(HMODULE module);
updates::Version ReadFileBuildVersion(const std::filesystem::path& image);
std::optional<updates::Policy> ReadEmbeddedPolicy(HMODULE module);
std::optional<updates::Policy> ReadFilePolicy(const std::filesystem::path& image);
bool SameInstallPath(const std::filesystem::path& a, const std::filesystem::path& b);
}
