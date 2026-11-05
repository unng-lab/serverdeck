#include "update_runtime.h"
#include "../../native/include/setup_package.h"
#include "../../native/include/mcp_json.h"
#include "../../native/include/github_releases.h"
#include <sstream>

sd::updates::Version UpdateBuildVersion() {
#ifdef FLUTTER_VERSION
  return sd::updates::ParseVersion(FLUTTER_VERSION);
#else
  return sd::updates::ParseVersion("0.1.0+1");
#endif
}
std::optional<sd::updates::Policy> ReadUpdatePolicy(const std::filesystem::path& executable) {
  sd::RejectReparse(executable);
  const auto module = LoadLibraryExW(sd::ExtendedPath(executable).c_str(), nullptr,
    LOAD_LIBRARY_AS_DATAFILE_EXCLUSIVE | LOAD_LIBRARY_AS_IMAGE_RESOURCE);
  if (!module) throw sd::updates::Failure("INVALID_ARTIFACT");
  try {
    const auto resource = FindResourceW(module, L"SERVERDECK_TRUST_V1", RT_RCDATA);
    std::optional<sd::updates::Policy> policy;
    if (resource) {
      const auto size = SizeofResource(module, resource); const auto loaded = LoadResource(module, resource);
      const auto* bytes = static_cast<const char*>(LockResource(loaded));
      if (!bytes || !size || size > 8192) throw sd::updates::Failure("INVALID_ARTIFACT");
      policy = sd::updates::ParsePolicy(std::string(bytes, size));
      sd::updates::ValidateGitHubPolicy(*policy);
    } else {
      const auto error = GetLastError();
      if (error != ERROR_RESOURCE_NAME_NOT_FOUND && error != ERROR_RESOURCE_TYPE_NOT_FOUND && error != ERROR_RESOURCE_DATA_NOT_FOUND)
        throw sd::updates::Failure("INVALID_ARTIFACT");
    }
    FreeLibrary(module); return policy;
  } catch (...) { FreeLibrary(module); throw; }
}
namespace {
bool SamePath(const std::filesystem::path& a, const std::filesystem::path& b) {
  const auto first = sd::ExtendedPath(a).lexically_normal().wstring(), second = sd::ExtendedPath(b).lexically_normal().wstring();
  return CompareStringOrdinal(first.c_str(), -1, second.c_str(), -1, TRUE) == CSTR_EQUAL;
}
}
std::unique_ptr<UpdateRuntime> CreateUpdateRuntime(const ServerDeckHostArgsV1& args, const sd::install::Paths& paths) {
  paths.Validate();
  if (!args.dataRoot || !args.exePath || !SamePath(args.dataRoot, paths.data)) throw sd::updates::Failure("RECOVERY_REQUIRED");
  const auto policy = ReadUpdatePolicy(args.exePath); const auto current = UpdateBuildVersion();
  std::optional<sd::install::Installation> installed;
  sd::install::Files files(paths);
  if (policy) {
    if (!SamePath(args.exePath, paths.install / L"ServerDeck.exe")) throw sd::updates::Failure("RECOVERY_REQUIRED");
    const auto record = sd::install::DecodeInstallation(files.ReadRecord(L"installation.v1"));
    if (record.sid != sd::Utf8(paths.sid) || !(record.version == current)) throw sd::updates::Failure("RECOVERY_REQUIRED");
    // Bootstrap verifies complete canonical bytes before entering the host.
    // Here check the bounded commit binding, without rehashing a GiB on the UI thread.
    const auto proof = files.ReadRecord(L"commit.v1"); std::istringstream lines(proof);
    std::string header, id, hash, extra;
    const auto encoded = sd::install::EncodeInstallation(record);
    if (proof.empty() || proof.back() != '\n' || proof.find('\r') != std::string::npos || proof.find('\0') != std::string::npos ||
        !std::getline(lines, header) || header != "SDCOMMIT001" || !std::getline(lines, id) || !sd::mcp::CanonicalUuid(id) ||
        !std::getline(lines, hash) || hash != sd::Sha256(reinterpret_cast<const uint8_t*>(encoded.data()), encoded.size()) ||
        std::getline(lines, extra)) throw sd::updates::Failure("RECOVERY_REQUIRED");
    installed = record;
  }
  auto runtime = std::make_unique<UpdateRuntime>();
  runtime->preferences = sd::updates::MakeFilePreferenceStore(paths);
  if (policy) runtime->pending = std::make_unique<sd::updates::PendingStore>(paths, *policy, sd::install::ValidateEmbeddedSetup);
  runtime->service = std::make_unique<sd::updates::UpdateService>(policy, current, *runtime->preferences,
    nullptr, sd::updates::UpdateService::Clock{}, runtime->pending.get(), nullptr, installed);
  return runtime;
}
