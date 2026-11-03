#include "security.h"
#include <aclapi.h>
#include <sddl.h>
#include <winioctl.h>
#include <cstring>
#include <iostream>
#include <stdexcept>

namespace {
void Require(bool value, const char* reason) {
  if (!value) throw std::runtime_error(reason);
}
void CheckAcl(const std::filesystem::path& path) {
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  PACL acl = nullptr;
  Require(GetNamedSecurityInfoW(path.c_str(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION,
    nullptr, nullptr, &acl, nullptr, &descriptor) == ERROR_SUCCESS, "Read DACL");
  PSID current = nullptr;
  Require(ConvertStringSidToSidW(sd::UserSid().c_str(), &current) != FALSE, "User SID");
  BYTE system[SECURITY_MAX_SID_SIZE]{}, admin[SECURITY_MAX_SID_SIZE]{};
  DWORD size = sizeof(system);
  Require(CreateWellKnownSid(WinLocalSystemSid, nullptr, system, &size) != FALSE, "System SID");
  size = sizeof(admin);
  Require(CreateWellKnownSid(WinBuiltinAdministratorsSid, nullptr, admin, &size) != FALSE, "Admin SID");
  Require(acl != nullptr && acl->AceCount >= 3, "Missing protected access rules");
  for (DWORD i = 0; i < acl->AceCount; ++i) {
    void* raw = nullptr;
    Require(GetAce(acl, i, &raw) != FALSE, "Read ACE");
    const auto* header = static_cast<ACE_HEADER*>(raw);
    if (header->AceType != ACCESS_ALLOWED_ACE_TYPE) continue;
    const auto* ace = static_cast<ACCESS_ALLOWED_ACE*>(raw);
    constexpr DWORD write = FILE_WRITE_DATA | FILE_APPEND_DATA | FILE_WRITE_EA |
      FILE_WRITE_ATTRIBUTES | DELETE | WRITE_DAC | WRITE_OWNER | GENERIC_ALL | GENERIC_WRITE;
    if (ace->Mask & write) {
      auto* sid = const_cast<DWORD*>(&ace->SidStart);
      Require(EqualSid(sid, current) || EqualSid(sid, system) || EqualSid(sid, admin),
              "Unexpected principal can write");
    }
  }
  LocalFree(current); LocalFree(descriptor);
}
void Junction(const std::filesystem::path& link, const std::filesystem::path& target) {
  sd::SecureDirectory(link);
  const auto substitute = L"\\??\\" + target.wstring();
  const auto print = target.wstring();
  struct Reparse {
    ULONG tag;
    USHORT length, reserved;
    USHORT substituteOffset, substituteLength, printOffset, printLength;
    wchar_t paths[2048];
  } data{};
  Require(substitute.size() + print.size() + 2 < 2048, "Junction path bound");
  data.tag = IO_REPARSE_TAG_MOUNT_POINT;
  data.substituteLength = static_cast<USHORT>(substitute.size() * sizeof(wchar_t));
  data.printOffset = static_cast<USHORT>((substitute.size() + 1) * sizeof(wchar_t));
  data.printLength = static_cast<USHORT>(print.size() * sizeof(wchar_t));
  std::memcpy(data.paths, substitute.c_str(), data.substituteLength);
  std::memcpy(reinterpret_cast<BYTE*>(data.paths) + data.printOffset,
              print.c_str(), data.printLength);
  data.length = static_cast<USHORT>(8 + data.printOffset + data.printLength + sizeof(wchar_t));
  sd::Handle handle(CreateFileW(link.c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, nullptr));
  DWORD returned = 0;
  Require(handle.valid() && DeviceIoControl(handle.get(), FSCTL_SET_REPARSE_POINT,
    &data, 8 + data.length, nullptr, 0, &returned, nullptr), "Create junction without elevation");
}
}
int main() {
  wchar_t temp[MAX_PATH]{};
  if (!GetTempPathW(MAX_PATH, temp)) return 1;
  const auto root = std::filesystem::path(temp) / (L"ServerDeckSecurityTest-" + sd::Uuid());
  try {
    sd::SecureDirectory(root);
    CheckAcl(root);
    const std::vector<uint8_t> original{'o','l','d'}, replacement{'n','e','w'};
    sd::AtomicFile(root / L"CURRENT.json", original);
    CheckAcl(root / L"CURRENT.json");
    sd::AtomicFile(root / L"CURRENT.json", replacement);
    // A restored file can carry an explicit protected DACL independent of its
    // parent's ACL. Securing only the root must not leave it writable by others.
    PSECURITY_DESCRIPTOR permissive = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(L"D:P(A;;FA;;;WD)",
        SDDL_REVISION_1, &permissive, nullptr)) throw std::runtime_error("Fixture DACL");
    const BOOL changed = SetFileSecurityW((root / L"CURRENT.json").c_str(),
      DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION, permissive);
    LocalFree(permissive);
    Require(changed != FALSE, "Apply restored file fixture ACL");
    sd::SecureTree(root);
    CheckAcl(root / L"CURRENT.json");
    // A failed replacement must remove only its own temporary file.
    sd::SecureDirectory(root / L"blocked");
    bool failed = false;
    try { sd::AtomicFile(root / L"blocked", replacement); } catch (...) { failed = true; }
    Require(failed, "Replacing directory must fail");
    for (const auto& entry : std::filesystem::directory_iterator(root))
      Require(entry.path().extension() != L".tmp", "Leaked failed atomic temporary file");
    const auto target = root / L"target", link = root / L"junction";
    sd::SecureDirectory(target);
    Junction(link, target);
    bool rejected = false;
    try { sd::AtomicFile(link / L"escape.json", replacement); } catch (...) { rejected = true; }
    Require(rejected && !std::filesystem::exists(target / L"escape.json"), "Reparse traversal accepted");
    Require(RemoveDirectoryW(link.c_str()) != FALSE, "Remove test junction");
    std::filesystem::remove_all(root);
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << ":" << GetLastError();
    // remove_all never follows directory symlinks; explicitly detach a junction.
    RemoveDirectoryW((root / L"junction").c_str());
    std::error_code ignored;
    std::filesystem::remove_all(root, ignored);
    return 2;
  }
}
