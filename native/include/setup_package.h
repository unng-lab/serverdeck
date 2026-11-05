#pragma once
#include "install_executor.h"

namespace sd::install {
struct SetupManifest { updates::Version version; Identity app; };
SetupManifest DecodeSetupManifest(const std::string& text);
void ValidateApplicationImage(Bytes bytes);
class LoadedSetup {
 public:
  LoadedSetup(HMODULE module, const std::filesystem::path& ownFile);
  ~LoadedSetup();
  LoadedSetup(const LoadedSetup&) = delete;
  Package package() const;
  bool IsFile(const std::filesystem::path& path) const;
 private:
  SetupManifest manifest_;
  Bytes app_, setup_;
  std::unique_ptr<Handle> file_, mapping_;
  void* view_ = nullptr;
};
void ValidateEmbeddedSetup(const std::filesystem::path& path, const updates::Version& version, const Identity& app);
std::filesystem::path ModuleFile();
}  // namespace sd::install
