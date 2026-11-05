#include "maintenance_handoff.h"
#include "uninstall.h"
#include "mcp_json.h"
#include <winternl.h>
#include <sddl.h>
#include <tlhelp32.h>
#include <algorithm>
#include <set>

namespace sd::install {
namespace {
[[noreturn]] void Invalid() { throw updates::Failure("RECOVERY_REQUIRED"); }
using QueryObject = NTSTATUS(NTAPI*)(HANDLE, OBJECT_INFORMATION_CLASS, PVOID, ULONG, PULONG);
void Object(HANDLE handle, const wchar_t* type, ACCESS_MASK required, ACCESS_MASK forbidden = 0) {
  DWORD flags = 0;
  if (!handle || handle == INVALID_HANDLE_VALUE || !GetHandleInformation(handle, &flags)) Invalid();
  const auto query = reinterpret_cast<QueryObject>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtQueryObject"));
  if (!query) Invalid();
  struct Basic { ULONG attributes; ACCESS_MASK access; ULONG handles, pointers, reserved[10]; } basic{};
  ULONG length = 0;
  if (query(handle, ObjectBasicInformation, &basic, sizeof(basic), &length) < 0 || (basic.access & required) != required || (basic.access & forbidden)) Invalid();
  alignas(void*) std::array<uint8_t, 4096> bytes{};
  if (query(handle, ObjectTypeInformation, bytes.data(), static_cast<ULONG>(bytes.size()), &length) < 0 || length > bytes.size()) Invalid();
  const auto* name = reinterpret_cast<const UNICODE_STRING*>(bytes.data());
  const auto start = reinterpret_cast<uintptr_t>(bytes.data()), pointer = reinterpret_cast<uintptr_t>(name->Buffer);
  if (!name->Buffer || name->Length % sizeof(wchar_t) || pointer < start || pointer - start > bytes.size() ||
      name->Length > bytes.size() - (pointer - start) || std::wstring(name->Buffer, name->Length / sizeof(wchar_t)) != type) Invalid();
}
bool SamePath(const std::filesystem::path& first, const std::filesystem::path& second) {
  const auto a = ExtendedPath(first).lexically_normal().wstring(), b = ExtendedPath(second).lexically_normal().wstring();
  return CompareStringOrdinal(a.c_str(), -1, b.c_str(), -1, TRUE) == CSTR_EQUAL;
}
std::unique_ptr<Handle> Duplicate(HANDLE value, DWORD access = 0, DWORD options = DUPLICATE_SAME_ACCESS) {
  HANDLE copy = nullptr;
  if (!DuplicateHandle(GetCurrentProcess(), value, GetCurrentProcess(), &copy, access, TRUE, options)) Invalid();
  return std::make_unique<Handle>(copy);
}
std::wstring Sid(PSID sid) {
  LPWSTR text = nullptr; if (!ConvertSidToStringSidW(sid, &text)) Invalid();
  std::wstring value(text); LocalFree(text); return value;
}
std::vector<uint8_t> Token(HANDLE token, TOKEN_INFORMATION_CLASS type) {
  DWORD size = 0; GetTokenInformation(token, type, nullptr, 0, &size);
  if (!size || size > 128 * 1024) Invalid();
  std::vector<uint8_t> bytes(size);
  if (!GetTokenInformation(token, type, bytes.data(), size, &size)) Invalid(); return bytes;
}
class WindowsHandoffPort final : public HandoffPort {
 public:
  std::unique_ptr<Handle> Spawn(const std::filesystem::path& executable, const std::wstring& text,
      const std::array<HANDLE, 5>& handles) override {
    SIZE_T size = 0; InitializeProcThreadAttributeList(nullptr, 1, 0, &size);
    if (!size || size > 65536) Invalid();
    std::vector<uint8_t> storage(size); auto* attributes = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
    if (!InitializeProcThreadAttributeList(attributes, 1, 0, &size)) Invalid();
    struct Attributes { LPPROC_THREAD_ATTRIBUTE_LIST value; ~Attributes() { DeleteProcThreadAttributeList(value); } } cleanup{attributes};
    if (!UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
        const_cast<HANDLE*>(handles.data()), sizeof(handles), nullptr, nullptr)) Invalid();
    STARTUPINFOEXW startup{}; startup.StartupInfo.cb = sizeof(startup); startup.lpAttributeList = attributes;
    PROCESS_INFORMATION process{}; auto command = text;
    if (!CreateProcessW(ExtendedPath(executable).c_str(), command.data(), nullptr, nullptr, TRUE,
        EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT, nullptr, nullptr, &startup.StartupInfo, &process))
      throw updates::Failure("STORAGE_IO");
    Handle thread(process.hThread); return std::make_unique<Handle>(process.hProcess);
  }
  DWORD WaitReady(HANDLE ready, HANDLE child, DWORD timeout) override {
    const HANDLE objects[]{ready, child}; return WaitForMultipleObjects(2, objects, FALSE, timeout);
  }
};
}
TransferHandles ParseTransfer(const std::vector<std::wstring>& args) {
  if (args.size() != 10) Invalid();
  std::array<HANDLE, 5> handles{}; std::set<uintptr_t> unique;
  const std::array<std::wstring, 5> names{L"--maintenance-handle", L"--owner-handle", L"--parent-handle", L"--ready-handle", L"--permit-handle"};
  for (size_t i = 0; i < handles.size(); ++i) {
    const auto& text = args[i * 2 + 1];
    if (args[i * 2] != names[i] || text.empty() || text.size() > 20 || text.front() == L'0' ||
        text.find_first_not_of(L"0123456789") != std::wstring::npos) Invalid();
    uintptr_t value = 0;
    for (const auto digit : text) {
      const auto n = static_cast<uintptr_t>(digit - L'0');
      if (value > (UINTPTR_MAX - n) / 10) Invalid(); value = value * 10 + n;
    }
    if (value >= UINTPTR_MAX - 1 || !unique.insert(value).second) Invalid();
    handles[i] = reinterpret_cast<HANDLE>(value);
  }
  return {handles[0], handles[1], handles[2], handles[3], handles[4]};
}
void ValidateLeaseHandle(HANDLE handle, const std::filesystem::path& expected) {
  RejectReparse(expected);
  Object(handle, L"File", FILE_READ_DATA | FILE_WRITE_DATA | WRITE_DAC | SYNCHRONIZE);
  BY_HANDLE_FILE_INFORMATION info{}; LARGE_INTEGER size{};
  if (GetFileType(handle) != FILE_TYPE_DISK || !GetFileInformationByHandle(handle, &info) ||
      (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) || !GetFileSizeEx(handle, &size) || size.QuadPart != 0) Invalid();
  std::wstring final(32768, L'\0'); const auto length = GetFinalPathNameByHandleW(handle, final.data(), static_cast<DWORD>(final.size()), FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
  if (!length || length >= final.size()) Invalid(); final.resize(length);
  if (!SamePath(final, expected)) Invalid();
  // Probe all sharing dimensions independently, on the exact original file
  // object rather than a mutable pathname. A combined RW denial says nothing
  // about delete/rename permission or which of READ/WRITE was denied.
  for (const DWORD access : {static_cast<DWORD>(FILE_READ_DATA), static_cast<DWORD>(FILE_WRITE_DATA), static_cast<DWORD>(DELETE)}) {
    Handle probe(ReOpenFile(handle, access, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, FILE_FLAG_OPEN_REPARSE_POINT));
    if (probe.valid() || GetLastError() != ERROR_SHARING_VIOLATION) Invalid();
  }
}
namespace {
void ValidateParentImage(HANDLE process, const Paths& paths, bool removal) {
  paths.Validate();
  Object(process, L"Process", SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION);
  const auto id = GetProcessId(process);
  if (!id || id == GetCurrentProcessId() || WaitForSingleObject(process, 0) != WAIT_TIMEOUT) Invalid();
  Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)); if (!snapshot.valid()) Invalid();
  PROCESSENTRY32W entry{}; entry.dwSize = sizeof(entry); DWORD parent = 0;
  if (!Process32FirstW(snapshot.get(), &entry)) Invalid();
  do { if (entry.th32ProcessID == GetCurrentProcessId()) { parent = entry.th32ParentProcessID; break; } }
  while (Process32NextW(snapshot.get(), &entry));
  FILETIME parentCreated{}, childCreated{}, ended{}, kernel{}, userTime{};
  if (parent != id || !GetProcessTimes(process, &parentCreated, &ended, &kernel, &userTime) ||
      !GetProcessTimes(GetCurrentProcess(), &childCreated, &ended, &kernel, &userTime) || CompareFileTime(&parentCreated, &childCreated) > 0) Invalid();
  std::wstring image(32768, L'\0'); DWORD length = static_cast<DWORD>(image.size());
  if (!QueryFullProcessImageNameW(process, 0, image.data(), &length)) Invalid(); image.resize(length);
  if (!SamePath(image, paths.install / (removal ? L"ServerDeckSetup.exe" : L"ServerDeck.exe"))) Invalid();
  HANDLE raw = nullptr; if (!OpenProcessToken(process, TOKEN_QUERY, &raw)) Invalid(); Handle token(raw);
  const auto user = Token(token.get(), TokenUser), groups = Token(token.get(), TokenGroups);
  if (Sid(reinterpret_cast<const TOKEN_USER*>(user.data())->User.Sid) != UserSid()) Invalid();
  const auto* list = reinterpret_cast<const TOKEN_GROUPS*>(groups.data()); bool logon = false;
  for (DWORD i = 0; i < list->GroupCount; ++i) if ((list->Groups[i].Attributes & SE_GROUP_LOGON_ID) == SE_GROUP_LOGON_ID)
    logon = Sid(list->Groups[i].Sid) == LogonSid();
  if (!logon) Invalid();
}
}
void ValidateParent(HANDLE process, const Paths& paths) { ValidateParentImage(process, paths, false); }
void ValidateRemovalParent(HANDLE process, const Paths& paths) { ValidateParentImage(process, paths, true); }
AcceptedTransfer AcceptTransfer(const Paths& paths, TransferHandles handles, ParentValidator parent) {
  paths.Validate();
  const std::array<HANDLE, 5> values{handles.maintenance, handles.owner, handles.parent, handles.ready, handles.permit};
  const std::set<HANDLE> unique(values.begin(), values.end()); if (unique.size() != 5) Invalid();
  auto maintenance = std::make_unique<Handle>(handles.maintenance), owner = std::make_unique<Handle>(handles.owner);
  auto process = std::make_unique<Handle>(handles.parent), ready = std::make_unique<Handle>(handles.ready);
  auto permit = std::make_unique<Handle>(handles.permit);
  Object(ready->get(), L"Event", EVENT_MODIFY_STATE | SYNCHRONIZE);
  if (WaitForSingleObject(ready->get(), 0) != WAIT_TIMEOUT) Invalid();
  Object(permit->get(), L"Event", SYNCHRONIZE, ~static_cast<ACCESS_MASK>(SYNCHRONIZE));
  if (WaitForSingleObject(permit->get(), 0) != WAIT_TIMEOUT) Invalid();
  using Compare = BOOL(WINAPI*)(HANDLE, HANDLE);
  const auto compare = reinterpret_cast<Compare>(GetProcAddress(GetModuleHandleW(L"kernelbase.dll"), "CompareObjectHandles"));
  if (!compare || compare(ready->get(), permit->get())) Invalid();
  if (!parent) parent = ValidateParent; parent(process->get(), paths);
  auto lease = Lease::Adopt(paths, std::move(maintenance), std::move(owner));
  for (const auto handle : values) if (!SetHandleInformation(handle, HANDLE_FLAG_INHERIT, 0)) Invalid();
  return {std::move(lease), std::move(process), std::move(ready), std::move(permit)};
}
void AcceptedTransfer::Acknowledge() {
  if (!lease || !parent || !ready || WaitForSingleObject(parent->get(), 0) != WAIT_TIMEOUT || !SetEvent(ready->get())) Invalid();
}
void AcceptedTransfer::AwaitParent(std::function<DWORD(HANDLE, DWORD)> wait,
    std::function<DWORD(HANDLE, HANDLE, DWORD)> permission) {
  if (!parent || !permit) Invalid();
  if (!permission) permission = [](HANDLE approval, HANDLE process, DWORD timeout) {
    const HANDLE handles[]{approval, process}; return WaitForMultipleObjects(2, handles, FALSE, timeout);
  };
  const auto allowed = permission(permit->get(), parent->get(), 3000);
  if (allowed == WAIT_TIMEOUT) throw updates::Failure("TIMEOUT"); if (allowed != WAIT_OBJECT_0) Invalid();
  if (!wait) wait = [](HANDLE process, DWORD timeout) { return WaitForSingleObject(process, timeout); };
  const auto result = wait(parent->get(), 10000);
  if (result == WAIT_TIMEOUT) throw updates::Failure("TIMEOUT"); if (result != WAIT_OBJECT_0) Invalid();
}
std::unique_ptr<HandoffPort> MakeWindowsHandoffPort() { return std::make_unique<WindowsHandoffPort>(); }
namespace {
void StartHandoff(Lease& lease, const Paths& paths, const std::filesystem::path& executable, const wchar_t* mode, HandoffPort& port) {
  if (!lease.Owns(paths, true)) Invalid();
  RejectReparse(executable);
  Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr)), approval(CreateEventW(nullptr, TRUE, FALSE, nullptr));
  if (!event.valid() || !approval.valid()) Invalid();
  auto maintenance = Duplicate(lease.maintenance()), owner = Duplicate(lease.owner());
  auto parent = Duplicate(GetCurrentProcess(), SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, 0), ready = Duplicate(event.get());
  auto permit = Duplicate(approval.get(), SYNCHRONIZE, 0);
  const std::array<HANDLE, 5> values{maintenance->get(), owner->get(), parent->get(), ready->get(), permit->get()};
  const std::array<std::wstring, 5> names{L"--maintenance-handle", L"--owner-handle", L"--parent-handle", L"--ready-handle", L"--permit-handle"};
  std::wstring command = L"\"" + executable.wstring() + L"\" " + mode;
  for (size_t i = 0; i < values.size(); ++i) command += L" " + names[i] + L" " + std::to_wstring(reinterpret_cast<uintptr_t>(values[i]));
  if (command.size() >= 32767) Invalid();
  auto child = port.Spawn(executable, command, values); if (!child || !child->valid()) Invalid();
  const auto result = port.WaitReady(event.get(), child->get(), 3000);
  if (result == WAIT_TIMEOUT) throw updates::Failure("TIMEOUT"); if (result != WAIT_OBJECT_0) Invalid();
  if (WaitForSingleObject(child->get(), 0) != WAIT_TIMEOUT) Invalid();
  if (!SetEvent(approval.get())) Invalid();
}
}
void StartPendingHandoff(Lease& lease, const Paths& paths, unsigned slot, HandoffPort& port) {
  if (slot > 1) Invalid();
  StartHandoff(lease, paths, paths.install / L"pending" / (L"slot" + std::to_wstring(slot)) / L"ServerDeckSetup.exe", L"--apply-pending", port);
}
void StartRemovalHandoff(Lease& lease, const Paths& paths, const std::filesystem::path& image, HandoffPort& port) {
  if (!SamePath(image.parent_path().parent_path(), RemovalCacheRoot(paths)) || image.filename() != L"ServerDeckSetup.exe" ||
      !mcp::CanonicalUuid(Utf8(image.parent_path().filename().wstring()))) Invalid();
  StartHandoff(lease, paths, image, L"--uninstall-helper", port);
}
void LaunchCanonical(const Paths& paths) {
  paths.Validate(); const auto executable = paths.install / L"ServerDeck.exe"; RejectReparse(executable);
  std::wstring command = L"\"" + executable.wstring() + L"\""; if (command.size() >= 32767) Invalid();
  STARTUPINFOW startup{}; startup.cb = sizeof(startup); PROCESS_INFORMATION process{};
  if (!CreateProcessW(ExtendedPath(executable).c_str(), command.data(), nullptr, nullptr, FALSE,
      CREATE_UNICODE_ENVIRONMENT, nullptr, nullptr, &startup, &process)) throw updates::Failure("STORAGE_IO");
  Handle thread(process.hThread), child(process.hProcess);
}
}  // namespace sd::install
