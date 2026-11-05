#pragma once
#include "../../native/include/update_service.h"
#include "../../native/include/serverdeck_host.h"

// Service is destroyed first: all borrowed ports survive its worker drain.
struct UpdateRuntime {
  std::unique_ptr<sd::updates::PreferenceStore> preferences;
  std::unique_ptr<sd::updates::CatalogSource> source;
  std::unique_ptr<sd::updates::ArtifactTransport> artifacts;
  std::unique_ptr<sd::updates::PendingPersistence> pending;
  std::unique_ptr<sd::updates::UpdateService> service;
};
sd::updates::Version UpdateBuildVersion();
std::optional<sd::updates::Policy> ReadUpdatePolicy(const std::filesystem::path& executable);
std::unique_ptr<UpdateRuntime> CreateUpdateRuntime(const ServerDeckHostArgsV1& args, const sd::install::Paths& paths);
