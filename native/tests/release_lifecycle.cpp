#include "security.h"
#include "runtime_text.h"
#include <UIAutomation.h>
#include <sddl.h>
#include <shellapi.h>
#include <shlobj.h>
#include <psapi.h>
#include <wrl/client.h>
#include <wbemidl.h>
#include <aclapi.h>
#include <algorithm>
#include <cwctype>
#include <fstream>
#include <functional>
#include <iostream>
#include <memory>
#include <map>
#include <regex>
#include <set>
#include <stdexcept>

using Microsoft::WRL::ComPtr;
namespace {
constexpr UINT kTrayNotification = WM_APP + 41;
constexpr wchar_t kMainClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
void Check(bool value, const char* error) { if (!value) throw std::runtime_error(error); }
std::string Quote(const std::wstring& value) {
  std::string output = "\"";
  constexpr char hex[] = "0123456789abcdef";
  for (const unsigned char ch : sd::Utf8(value)) {
    if (ch == '\\' || ch == '"') { output += '\\'; output += ch; }
    else if (ch < 32) { output += "\\u00"; output += hex[ch >> 4]; output += hex[ch & 15]; }
    else output += ch;
  }
  return output + '"';
}
class Journal {
 public:
  explicit Journal(const std::filesystem::path& path)
      : file_(CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                          FILE_ATTRIBUTE_NORMAL, nullptr)) {
    Check(file_.valid(), "EVIDENCE_CREATE_FAILED");
  }
  void Write(const std::string& json) {
    const auto line = json + '\n';
    DWORD written = 0;
    Check(WriteFile(file_.get(), line.data(), static_cast<DWORD>(line.size()), &written, nullptr) &&
          written == line.size() && FlushFileBuffers(file_.get()), "EVIDENCE_WRITE_FAILED");
  }
 private:
  sd::Handle file_;
};
void Wait(const std::function<bool()>& predicate, DWORD timeout, const char* error) {
  const auto start = GetTickCount64();
  while (!predicate()) {
    Check(GetTickCount64() - start < timeout, error);
    Sleep(25);
  }
}
struct WindowQuery {
  DWORD pid;
  const wchar_t* name;
  HWND window = nullptr;
  bool multiple = false;
};
BOOL CALLBACK MatchWindow(HWND window, LPARAM parameter) {
  auto& query = *reinterpret_cast<WindowQuery*>(parameter);
  DWORD pid = 0;
  GetWindowThreadProcessId(window, &pid);
  wchar_t name[256]{};
  if (pid == query.pid && GetClassNameW(window, name, 256) && wcscmp(name, query.name) == 0) {
    if (query.window) query.multiple = true;
    query.window = window;
  }
  return TRUE;
}
HWND FindWindow(DWORD pid, const wchar_t* className) {
  WindowQuery query{pid, className};
  Check(EnumWindows(MatchWindow, reinterpret_cast<LPARAM>(&query)) != FALSE, "WINDOW_ENUM_FAILED");
  Check(!query.multiple, "MULTIPLE_PRODUCT_WINDOWS");
  return query.window;
}
class Automation {
 public:
  Automation() {
    Check(SUCCEEDED(CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&client_))), "UIA_CREATE_FAILED");
  }
  ComPtr<IUIAutomationElement> Named(HWND window, const wchar_t* name, int controlType = 0) {
    ComPtr<IUIAutomationElement> root, found;
    if (FAILED(client_->ElementFromHandle(window, &root))) return found;
    VARIANT value{};
    value.vt = VT_BSTR; value.bstrVal = SysAllocString(name);
    Check(value.bstrVal != nullptr, "UIA_ALLOCATION_FAILED");
    ComPtr<IUIAutomationCondition> condition;
    const HRESULT result = client_->CreatePropertyCondition(UIA_NamePropertyId, value, &condition);
    VariantClear(&value);
    Check(SUCCEEDED(result), "UIA_CONDITION_FAILED");
    if (controlType) {
      value.vt = VT_I4; value.lVal = controlType;
      ComPtr<IUIAutomationCondition> type, combined;
      Check(SUCCEEDED(client_->CreatePropertyCondition(UIA_ControlTypePropertyId, value, &type)) &&
            SUCCEEDED(client_->CreateAndCondition(condition.Get(), type.Get(), &combined)), "UIA_CONDITION_FAILED");
      condition = combined;
    }
    if (FAILED(root->FindFirst(TreeScope_Subtree, condition.Get(), &found))) return {};
    return found;
  }
  bool Contains(HWND window, const wchar_t* text) {
    ComPtr<IUIAutomationElement> root;
    ComPtr<IUIAutomationCondition> condition;
    ComPtr<IUIAutomationElementArray> elements;
    if (FAILED(client_->ElementFromHandle(window, &root)) ||
        FAILED(client_->CreateTrueCondition(&condition)) ||
        FAILED(root->FindAll(TreeScope_Subtree, condition.Get(), &elements))) return false;
    int length = 0;
    Check(SUCCEEDED(elements->get_Length(&length)) && length <= 10000, "UIA_ELEMENT_LIMIT_FAILED");
    for (int index = 0; index < length; ++index) {
      ComPtr<IUIAutomationElement> element;
      if (FAILED(elements->GetElement(index, &element))) continue;
      BSTR name = nullptr;
      if (FAILED(element->get_CurrentName(&name))) continue;
      const bool found = name && wcsstr(name, text) != nullptr;
      SysFreeString(name);
      if (found) return true;
    }
    return false;
  }
  void Invoke(IUIAutomationElement* element) {
    ComPtr<IUIAutomationInvokePattern> invoke;
    if (SUCCEEDED(element->GetCurrentPatternAs(UIA_InvokePatternId, IID_PPV_ARGS(&invoke)))) {
      Check(SUCCEEDED(invoke->Invoke()), "MENU_INVOKE_FAILED"); return;
    }
    ComPtr<IUIAutomationLegacyIAccessiblePattern> legacy;
    Check(SUCCEEDED(element->GetCurrentPatternAs(UIA_LegacyIAccessiblePatternId,
          IID_PPV_ARGS(&legacy))) && SUCCEEDED(legacy->DoDefaultAction()), "MENU_INVOKE_FAILED");
  }
  void Button(HWND dialog, int id) {
    const auto button = GetDlgItem(dialog, id);
    Check(button != nullptr, "STARTUP_DIALOG_ACTION_MISSING");
    ComPtr<IUIAutomationElement> element;
    Check(SUCCEEDED(client_->ElementFromHandle(button, &element)), "STARTUP_DIALOG_ACTION_UNAVAILABLE");
    Invoke(element.Get());
  }
 private:
  ComPtr<IUIAutomation> client_;
};
class Children {
 public:
  struct Child {
    Child() = default;
    Child(const Child&) = delete;
    Child& operator=(const Child&) = delete;
    ~Child() {
      if (info.hThread) CloseHandle(info.hThread);
      if (info.hProcess) CloseHandle(info.hProcess);
    }
    PROCESS_INFORMATION info{};
    DWORD pid = 0;
    bool resumed = false;
    bool Alive() const { return WaitForSingleObject(info.hProcess, 0) == WAIT_TIMEOUT; }
    DWORD ExitCode() const {
      DWORD code = STILL_ACTIVE;
      Check(GetExitCodeProcess(info.hProcess, &code) != FALSE, "CHILD_EXIT_QUERY_FAILED");
      return code;
    }
  };
  Children() : job_(CreateJobObjectW(nullptr, nullptr)) {
    Check(job_.valid(), "CHILD_JOB_FAILED");
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    Check(SetInformationJobObject(job_.get(), JobObjectExtendedLimitInformation, &limits,
                                  sizeof(limits)) != FALSE, "CHILD_JOB_FAILED");
  }
  Child& CreateSuspended(const std::filesystem::path& exe, const std::wstring& arguments = L"") {
    Check(exe.is_absolute() && exe.wstring().find(L'"') == std::wstring::npos, "INVALID_EXE_PATH");
    auto command = L"\"" + exe.wstring() + L"\"" + (arguments.empty() ? L"" : L" " + arguments);
    STARTUPINFOW startup{}; startup.cb = sizeof(startup);
    // Allocate ownership before CreateProcess so allocation failure cannot
    // strand a suspended process before it has been assigned to the job.
    auto child = std::make_unique<Child>();
    Check(CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr, FALSE,
          CREATE_SUSPENDED | CREATE_NO_WINDOW, nullptr, exe.parent_path().c_str(), &startup, &child->info) != FALSE,
          "CHILD_START_FAILED");
    child->pid = child->info.dwProcessId;
    if (!AssignProcessToJobObject(job_.get(), child->info.hProcess)) {
      TerminateProcess(child->info.hProcess, 90); WaitForSingleObject(child->info.hProcess, 5000);
      throw std::runtime_error("CHILD_JOB_ASSIGN_FAILED");
    }
    children_.push_back(std::move(child));
    return *children_.back();
  }
  void Resume(Child& child) {
    Check(!child.resumed && ResumeThread(child.info.hThread) != static_cast<DWORD>(-1), "CHILD_RESUME_FAILED");
    child.resumed = true;
  }
  Child& Launch(const std::filesystem::path& exe, const std::wstring& arguments = L"") {
    auto& child = CreateSuspended(exe, arguments); Resume(child); return child;
  }
  void AssertStopped() const {
    for (const auto& child : children_) Check(!child->Alive(), "FILE_FAULT_REQUIRES_STOPPED_CHILDREN");
  }
  void Crash(Child& child) {
    Check(child.Alive() && TerminateProcess(child.info.hProcess, 91) &&
          WaitForSingleObject(child.info.hProcess, 5000) == WAIT_OBJECT_0 && child.ExitCode() == 91,
          "OWNED_CHILD_CRASH_FAILED");
  }
 private:
  // The job closes last: failed/killed driver runs cannot leave any of its
  // launched children behind. It never acquires unrelated product PIDs.
  sd::Handle job_;
  std::vector<std::unique_ptr<Child>> children_;
};
std::vector<uint8_t> ReadSmall(const std::filesystem::path& path) {
  sd::RejectReparse(path);
  const auto length = std::filesystem::file_size(path);
  Check(length > 0 && length <= 8192, "INVALID_METADATA_SIZE");
  std::ifstream input(path, std::ios::binary);
  std::vector<uint8_t> bytes(static_cast<size_t>(length));
  Check(static_cast<bool>(input.read(reinterpret_cast<char*>(bytes.data()), length)), "METADATA_READ_FAILED");
  return bytes;
}
std::string HashFile(const std::filesystem::path& path) {
  sd::RejectReparse(path);
  const auto length = std::filesystem::file_size(path);
  Check(length <= 64ull * 1024 * 1024, "FIXTURE_HASH_FILE_LIMIT");
  std::ifstream input(path, std::ios::binary);
  std::vector<uint8_t> bytes(static_cast<size_t>(length));
  if (length) Check(static_cast<bool>(input.read(reinterpret_cast<char*>(bytes.data()), length)), "FIXTURE_HASH_READ_FAILED");
  else Check(input.good(), "FIXTURE_HASH_READ_FAILED");
  return sd::Sha256(bytes.data(), bytes.size());
}
using TreeHashes = std::map<std::wstring, std::string>;
TreeHashes DataHashes(const std::filesystem::path& root) {
  TreeHashes result;
  const auto data = root / L"data";
  sd::RejectReparse(data);
  uint64_t total = 0;
  size_t entries = 0;
  for (const auto& item : std::filesystem::recursive_directory_iterator(data)) {
    sd::RejectReparse(item.path());
    Check(++entries <= 1024, "FIXTURE_HASH_ENTRY_LIMIT");
    const auto relative = item.path().lexically_relative(data).generic_wstring();
    if (relative == L"CURRENT.json") continue;
    if (item.is_directory()) result.emplace(L"directory:" + relative, "");
    else {
      Check(item.is_regular_file(), "FIXTURE_UNEXPECTED_DATA_ENTITY");
      const auto length = item.file_size();
      Check(length <= 64ull * 1024 * 1024 && total <= 256ull * 1024 * 1024 - length,
            "FIXTURE_HASH_TOTAL_LIMIT");
      total += length;
      result.emplace(relative, HashFile(item.path()));
    }
  }
  Check(!result.empty(), "FIXTURE_EMPTY_DATA_TREE");
  return result;
}
std::vector<uint8_t> FutureCurrent(const std::vector<uint8_t>& current) {
  const std::string text(current.begin(), current.end());
  const std::regex field("\"formatVersion\"\\s*:\\s*1(?=\\s*[,}])");
  const auto count = std::distance(std::sregex_iterator(text.begin(), text.end(), field), std::sregex_iterator());
  Check(count == 1, "FIXTURE_EXPECTED_FORMAT_ONE_CURRENT");
  const auto changed = std::regex_replace(text, field, "\"formatVersion\":2147483647");
  return {changed.begin(), changed.end()};
}
void FlipFirstByte(const std::filesystem::path& path) {
  sd::RejectReparse(path);
  sd::Handle file(CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
      OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  Check(file.valid(), "FIXTURE_CORRUPTION_OPEN_FAILED");
  uint8_t value = 0; DWORD length = 0;
  Check(ReadFile(file.get(), &value, 1, &length, nullptr) && length == 1, "FIXTURE_CORRUPTION_READ_FAILED");
  value ^= 0xff;
  Check(SetFilePointer(file.get(), 0, nullptr, FILE_BEGIN) != INVALID_SET_FILE_POINTER &&
        WriteFile(file.get(), &value, 1, &length, nullptr) && length == 1 && FlushFileBuffers(file.get()),
        "FIXTURE_CORRUPTION_WRITE_FAILED");
}
struct LocalDescriptor {
  void operator()(void* pointer) const { if (pointer) LocalFree(pointer); }
};
class DirectoryAclFault {
 public:
  explicit DirectoryAclFault(const std::filesystem::path& path)
      : path_(sd::ExtendedPath(path)), handle_(Open(path_)) {
    PSECURITY_DESCRIPTOR raw = nullptr;
    Check(GetSecurityInfo(handle_.get(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION,
        nullptr, nullptr, &originalAcl_, nullptr, &raw) == ERROR_SUCCESS, "ACL_FIXTURE_CAPTURE_FAILED");
    descriptor_.reset(raw);
    SECURITY_DESCRIPTOR_CONTROL control{}; DWORD revision = 0;
    Check(originalAcl_ && GetSecurityDescriptorControl(raw, &control, &revision), "ACL_FIXTURE_CAPTURE_FAILED");
    protected_ = (control & SE_DACL_PROTECTED) != 0;
    // OWNER RIGHTS suppresses the owner's implicit WRITE_DAC. Keep a previously
    // granted handle so the fixture can restore access without elevation.
    const auto text = L"D:P(D;;0x00040006;;;OW)(A;;FA;;;" + sd::UserSid() + L")(A;;FA;;;SY)(A;;FA;;;BA)";
    PSECURITY_DESCRIPTOR restricted = nullptr;
    Check(ConvertStringSecurityDescriptorToSecurityDescriptorW(text.c_str(), SDDL_REVISION_1,
          &restricted, nullptr) != FALSE, "ACL_FIXTURE_DESCRIPTOR_FAILED");
    std::unique_ptr<void, LocalDescriptor> temporary(restricted);
    BOOL present = FALSE, defaulted = FALSE; PACL acl = nullptr;
    Check(GetSecurityDescriptorDacl(restricted, &present, &acl, &defaulted) && present && acl,
          "ACL_FIXTURE_DESCRIPTOR_FAILED");
    Check(SetSecurityInfo(handle_.get(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
          nullptr, nullptr, acl, nullptr) == ERROR_SUCCESS, "ACL_FIXTURE_APPLY_FAILED");
    active_ = true;
    try { AssertDenied(); } catch (...) { Restore(); throw; }
  }
  ~DirectoryAclFault() { if (active_) { try { Restore(); } catch (...) {} } }
  void Restore() {
    if (!active_) return;
    const SECURITY_INFORMATION flags = DACL_SECURITY_INFORMATION |
        (protected_ ? PROTECTED_DACL_SECURITY_INFORMATION : UNPROTECTED_DACL_SECURITY_INFORMATION);
    Check(SetSecurityInfo(handle_.get(), SE_FILE_OBJECT, flags, nullptr, nullptr, originalAcl_, nullptr) == ERROR_SUCCESS,
          "ACL_FIXTURE_RESTORE_FAILED");
    active_ = false;
  }
  void AssertDenied() const {
    sd::Handle repair(CreateFileW(path_.c_str(), WRITE_DAC,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
    const auto repairError = GetLastError();
    Check(!repair.valid() && repairError == ERROR_ACCESS_DENIED, "ACL_FIXTURE_DID_NOT_DENY_REPAIR");
    const auto probe = path_ / (L"must-not-create-" + sd::Uuid());
    sd::Handle creation(CreateFileW(probe.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr));
    const auto createError = GetLastError();
    Check(!creation.valid() && createError == ERROR_ACCESS_DENIED, "ACL_FIXTURE_DID_NOT_DENY_CREATION");
  }
 private:
  static HANDLE Open(const std::filesystem::path& path) {
    sd::RejectReparse(path);
    const auto value = CreateFileW(path.c_str(), READ_CONTROL | WRITE_DAC,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    Check(value != INVALID_HANDLE_VALUE, "ACL_FIXTURE_OPEN_FAILED");
    return value;
  }
  std::filesystem::path path_;
  sd::Handle handle_;
  std::unique_ptr<void, LocalDescriptor> descriptor_;
  PACL originalAcl_ = nullptr;
  bool protected_ = true, active_ = false;
};
void ReadOnly(const std::filesystem::path& path) {
  sd::RejectReparse(path);
  const auto sddl = L"D:P(A;;GRGX;;;" + sd::UserSid() + L")(A;;GA;;;SY)";
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  Check(ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1,
        &descriptor, nullptr) != FALSE, "READONLY_DESCRIPTOR_FAILED");
  const bool result = SetFileSecurityW(path.c_str(), DACL_SECURITY_INFORMATION |
                                     PROTECTED_DACL_SECURITY_INFORMATION, descriptor) != FALSE;
  LocalFree(descriptor);
  Check(result, "READONLY_ACL_FAILED");
}
void AssertNoWrite(const std::filesystem::path& file) {
  sd::Handle probe(CreateFileW(file.c_str(), GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                              nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  const DWORD error = GetLastError();
  Check(!probe.valid() && error == ERROR_ACCESS_DENIED, "EXE_FOLDER_IS_WRITABLE");
}
std::filesystem::path ProfileRoot() {
  PWSTR folder = nullptr;
  Check(SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &folder)), "PROFILE_QUERY_FAILED");
  const auto root = std::filesystem::path(folder) / L"ServerDeck";
  CoTaskMemFree(folder);
  return root;
}
void RequireUnlockedDesktop() {
  HDESK desktop = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
  Check(desktop != nullptr, "UNLOCKED_DESKTOP_REQUIRED");
  wchar_t name[256]{}; DWORD size = 0;
  const bool readable = GetUserObjectInformationW(desktop, UOI_NAME, name, sizeof(name), &size) != FALSE;
  CloseDesktop(desktop);
  Check(readable && _wcsicmp(name, L"Default") == 0, "UNLOCKED_DESKTOP_REQUIRED");
}
bool VirtualModel(std::wstring model) {
  std::transform(model.begin(), model.end(), model.begin(), [](wchar_t ch) { return static_cast<wchar_t>(towlower(ch)); });
  for (const auto* token : {L"virtual machine", L"vmware", L"virtualbox", L"kvm", L"qemu", L"xen", L"parallels"})
    if (model.find(token) != std::wstring::npos) return true;
  return false;
}
void RequireVirtualMachine(bool unjobbed = false) {
  const auto security = CoInitializeSecurity(nullptr, -1, nullptr, nullptr, RPC_C_AUTHN_LEVEL_DEFAULT,
      RPC_C_IMP_LEVEL_IMPERSONATE, nullptr, EOAC_NONE, nullptr);
  Check(SUCCEEDED(security) || security == RPC_E_TOO_LATE, "VM_IDENTITY_SECURITY_FAILED");
  ComPtr<IWbemLocator> locator;
  ComPtr<IWbemServices> services;
  Check(SUCCEEDED(CoCreateInstance(CLSID_WbemLocator, nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&locator))), "VM_IDENTITY_QUERY_FAILED");
  BSTR nameSpace = SysAllocString(L"ROOT\\CIMV2");
  Check(nameSpace != nullptr, "VM_IDENTITY_QUERY_FAILED");
  const auto connected = locator->ConnectServer(nameSpace, nullptr, nullptr, nullptr, 0, nullptr, nullptr, &services);
  SysFreeString(nameSpace);
  Check(SUCCEEDED(connected) && SUCCEEDED(CoSetProxyBlanket(services.Get(), RPC_C_AUTHN_WINNT,
      RPC_C_AUTHZ_NONE, nullptr, RPC_C_AUTHN_LEVEL_CALL, RPC_C_IMP_LEVEL_IMPERSONATE, nullptr, EOAC_NONE)),
      "VM_IDENTITY_QUERY_FAILED");
  BSTR language = SysAllocString(L"WQL");
  BSTR query = SysAllocString(L"SELECT Manufacturer, Model FROM Win32_ComputerSystem");
  if (!language || !query) {
    SysFreeString(language); SysFreeString(query); throw std::runtime_error("VM_IDENTITY_QUERY_FAILED");
  }
  ComPtr<IEnumWbemClassObject> enumeration;
  const auto executed = services->ExecQuery(language, query, WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
                                           nullptr, &enumeration);
  SysFreeString(language); SysFreeString(query);
  Check(SUCCEEDED(executed), "VM_IDENTITY_QUERY_FAILED");
  ComPtr<IWbemClassObject> computer;
  ULONG returned = 0;
  Check(SUCCEEDED(enumeration->Next(3000, 1, &computer, &returned)) && returned == 1, "VM_IDENTITY_QUERY_FAILED");
  std::wstring identity;
  for (const auto* key : {L"Manufacturer", L"Model"}) {
    VARIANT value{};
    const auto found = computer->Get(key, 0, &value, nullptr, nullptr);
    const bool valid = SUCCEEDED(found) && value.vt == VT_BSTR && value.bstrVal;
    if (valid) identity += std::wstring(value.bstrVal) + L" ";
    VariantClear(&value);
    Check(valid, "VM_IDENTITY_QUERY_FAILED");
  }
  Check(VirtualModel(identity), "DISPOSABLE_VM_REQUIRED");
  if (unjobbed) {
    BOOL inJob = FALSE;
    Check(IsProcessInJob(GetCurrentProcess(), nullptr, &inJob) && !inJob, "SHELL_FIXTURE_REQUIRES_UNJOBBED_DRIVER");
  }
}
void GuardDisposableUser() {
  const auto sid = sd::UserSid();
  PSID nativeSid = nullptr;
  Check(ConvertStringSidToSidW(sid.c_str(), &nativeSid) != FALSE, "TEST_ACCOUNT_QUERY_FAILED");
  wchar_t name[256]{}, domain[256]{};
  DWORD nameSize = 256, domainSize = 256; SID_NAME_USE use{};
  const bool found = LookupAccountSidW(nullptr, nativeSid, name, &nameSize, domain, &domainSize, &use) != FALSE;
  LocalFree(nativeSid);
  Check(found, "TEST_ACCOUNT_QUERY_FAILED");
  const std::wstring account(name), prefix(L"ServerDeckSmoke");
  Check(account.size() >= prefix.size() && _wcsnicmp(account.c_str(), prefix.c_str(), prefix.size()) == 0 &&
        (account.size() == prefix.size() || (account.size() > prefix.size() + 1 &&
         (account[prefix.size()] == L'-' || account[prefix.size()] == L'_'))), "DISPOSABLE_ACCOUNT_REQUIRED");
  HANDLE raw = nullptr;
  Check(OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &raw) != FALSE, "TOKEN_QUERY_FAILED");
  sd::Handle token(raw);
  TOKEN_ELEVATION elevation{}; DWORD size = 0;
  Check(GetTokenInformation(token.get(), TokenElevation, &elevation, sizeof(elevation), &size) &&
        elevation.TokenIsElevated == 0, "NON_ELEVATED_ACCOUNT_REQUIRED");
  RequireUnlockedDesktop();
  Check(!std::filesystem::exists(ProfileRoot()), "CLEAN_PROFILE_REQUIRED");
}
LRESULT Message(HWND window, UINT message, WPARAM wparam = 0, LPARAM lparam = 0) {
  DWORD_PTR result = 0;
  Check(SendMessageTimeoutW(window, message, wparam, lparam, SMTO_ABORTIFHUNG | SMTO_BLOCK,
                            2000, &result) != 0, "WINDOW_MESSAGE_FAILED");
  return static_cast<LRESULT>(result);
}
bool TrayRegistered(HWND window) {
  NOTIFYICONIDENTIFIER identifier{};
  identifier.cbSize = sizeof(identifier); identifier.hWnd = window; identifier.uID = 1;
  RECT unused{};
  return Shell_NotifyIconGetRect(&identifier, &unused) == S_OK;
}
void TrayPresent(HWND window) {
  Check(TrayRegistered(window), "TRAY_ICON_NOT_REGISTERED");
}
void Menu(Children::Child& child, HWND window, const wchar_t* command) {
  Check(child.Alive(), "OWNER_EXITED");
  TrayPresent(window);
  Check(PostMessageW(window, kTrayNotification, 1, WM_RBUTTONUP) != FALSE, "TRAY_CALLBACK_FAILED");
  Automation automation;
  ComPtr<IUIAutomationElement> item;
  Wait([&] {
    Check(child.Alive(), "OWNER_EXITED");
    const HWND popup = FindWindow(child.pid, L"#32768");
    if (popup) item = automation.Named(popup, command);
    return item != nullptr;
  }, 5000, "TRAY_MENU_ITEM_NOT_FOUND");
  automation.Invoke(item.Get());
}
HWND Ready(Children::Child& child, const std::filesystem::path& root) {
  Automation automation;
  HWND window = nullptr;
  Wait([&] {
    Check(child.Alive(), "OWNER_EXITED_BEFORE_READY");
    window = FindWindow(child.pid, kMainClass);
    return window && IsWindowVisible(window) && automation.Named(window, L"Приложение готово") &&
           std::filesystem::exists(root / L"data/CURRENT.json") && TrayRegistered(window);
  }, 30000, "PRODUCT_READY_TIMEOUT");
  TrayPresent(window);
  return window;
}
void OwnerLocked(const std::filesystem::path& root) {
  sd::Handle file(CreateFileW((root / L"owner.lock").c_str(), GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
      FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  const DWORD error = GetLastError();
  Check(!file.valid() && error == ERROR_SHARING_VIOLATION, "OWNER_LOCK_NOT_HELD");
}
std::filesystem::path ModulesInOwner(Children::Child& child) {
  HMODULE modules[1024]{}; DWORD needed = 0;
  Check(EnumProcessModulesEx(child.info.hProcess, modules, sizeof(modules), &needed, LIST_MODULES_64BIT) &&
        needed <= sizeof(modules), "OWNER_MODULE_QUERY_FAILED");
  bool host = false, flutter = false, isar = false;
  std::filesystem::path runtime;
  for (size_t index = 0; index < needed / sizeof(HMODULE); ++index) {
    wchar_t text[32768]{};
    Check(GetModuleFileNameExW(child.info.hProcess, modules[index], text, 32768) != 0,
          "OWNER_MODULE_PATH_FAILED");
    const auto name = std::filesystem::path(text).filename().wstring();
    host = host || _wcsicmp(name.c_str(), L"serverdeck_host.dll") == 0;
    if (_wcsicmp(name.c_str(), L"serverdeck_host.dll") == 0) runtime = std::filesystem::path(text).parent_path();
    flutter = flutter || _wcsicmp(name.c_str(), L"flutter_windows.dll") == 0;
    isar = isar || _wcsicmp(name.c_str(), L"libisar.dll") == 0;
  }
  Check(host && flutter && isar, "RUNTIME_NOT_IN_ORIGINAL_PID");
  return runtime;
}
void ValidateRuntime(const std::filesystem::path& runtime, const std::filesystem::path& root) {
  sd::RejectReparse(runtime);
  const auto parent = sd::ExtendedPath(root) / L"runtime";
  const auto name = runtime.filename().wstring();
  Check(_wcsicmp(sd::ExtendedPath(runtime.parent_path()).c_str(), parent.c_str()) == 0 &&
        name.size() == 64 && name.find_first_not_of(L"0123456789abcdef") == std::wstring::npos,
        "FIXTURE_RUNTIME_OUTSIDE_MANAGED_ROOT");
}
std::set<std::filesystem::path> RuntimeSiblings(const std::filesystem::path& runtime, const wchar_t* suffix) {
  std::set<std::filesystem::path> paths;
  const auto prefix = runtime.filename().wstring() + suffix;
  for (const auto& entry : std::filesystem::directory_iterator(runtime.parent_path())) {
    const auto name = entry.path().filename().wstring();
    if (name.rfind(prefix, 0) == 0) { sd::RejectReparse(entry.path()); paths.insert(entry.path()); }
  }
  return paths;
}
HWND StorageBlocked(Children::Child& child, const wchar_t* error) {
  Automation automation;
  HWND window = nullptr;
  Wait([&] {
    Check(child.Alive(), "OWNER_EXITED_INSTEAD_OF_STORAGE_ERROR");
    window = FindWindow(child.pid, kMainClass);
    return window && IsWindowVisible(window) && automation.Named(window, L"Данные недоступны") &&
           !automation.Named(window, L"Приложение готово") && automation.Contains(window, error) &&
           automation.Named(window, L"Повторить", UIA_ButtonControlTypeId);
  }, 30000, "STORAGE_ERROR_UI_TIMEOUT");
  TrayPresent(window);
  return window;
}
HWND NativeAccessError(Children::Child& child) {
  Automation automation;
  HWND dialog = nullptr;
  Wait([&] {
    Check(child.Alive(), "ACL_FAILURE_EXITED_WITHOUT_RECOVERY_DIALOG");
    // Native MessageBox uses dialog class #32770; no Flutter HWND is expected.
    dialog = FindWindow(child.pid, L"#32770");
    return dialog && IsWindowVisible(dialog) && automation.Contains(dialog, L"Не удалось открыть защищённые файлы") &&
           GetDlgItem(dialog, IDRETRY) && GetDlgItem(dialog, IDCANCEL);
  }, 30000, "NATIVE_ACCESS_ERROR_DIALOG_TIMEOUT");
  Check(FindWindow(child.pid, kMainClass) == nullptr, "ACL_FAILURE_CREATED_GUI_HOST");
  HMODULE modules[1024]{}; DWORD needed = 0;
  Check(EnumProcessModulesEx(child.info.hProcess, modules, sizeof(modules), &needed, LIST_MODULES_64BIT) &&
        needed <= sizeof(modules), "ACL_FAILURE_MODULE_QUERY_FAILED");
  for (size_t index = 0; index < needed / sizeof(HMODULE); ++index) {
    wchar_t path[32768]{};
    Check(GetModuleFileNameExW(child.info.hProcess, modules[index], path, 32768) != 0, "ACL_FAILURE_MODULE_PATH_FAILED");
    const auto name = std::filesystem::path(path).filename().wstring();
    Check(_wcsicmp(name.c_str(), L"serverdeck_host.dll") && _wcsicmp(name.c_str(), L"flutter_windows.dll") &&
          _wcsicmp(name.c_str(), L"libisar.dll"), "ACL_FAILURE_LOADED_RUNTIME");
  }
  return dialog;
}
void Exit(Children::Child& child, HWND window, const std::filesystem::path& root) {
  Menu(child, window, sd::kTrayExit);
  Check(WaitForSingleObject(child.info.hProcess, 10000) == WAIT_OBJECT_0 && child.ExitCode() == 0,
        "TRAY_EXIT_FAILED_OR_DEADLINE_EXCEEDED");
  Check(!std::filesystem::exists(root / L"owner.json"), "STALE_OWNER_DESCRIPTOR_AFTER_EXIT");
  sd::Handle lock(CreateFileW((root / L"owner.lock").c_str(), GENERIC_READ | GENERIC_WRITE,
      0, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  Check(lock.valid(), "OWNER_LOCK_NOT_RELEASED");
}
struct ProcessIdentity {
  DWORD pid = 0, session = 0;
  uint64_t created = 0;
  std::wstring image, user;
};
ProcessIdentity InspectProcess(HANDLE process) {
  ProcessIdentity value;
  value.pid = GetProcessId(process);
  Check(value.pid && ProcessIdToSessionId(value.pid, &value.session), "SHELL_IDENTITY_QUERY_FAILED");
  value.image.resize(32768);
  DWORD size = static_cast<DWORD>(value.image.size());
  Check(QueryFullProcessImageNameW(process, 0, value.image.data(), &size) != FALSE, "SHELL_IMAGE_QUERY_FAILED");
  value.image.resize(size);
  HANDLE raw = nullptr;
  Check(OpenProcessToken(process, TOKEN_QUERY, &raw) != FALSE, "SHELL_TOKEN_QUERY_FAILED");
  sd::Handle token(raw);
  size = 0;
  GetTokenInformation(token.get(), TokenUser, nullptr, 0, &size);
  Check(size != 0, "SHELL_TOKEN_QUERY_FAILED");
  std::vector<uint8_t> bytes(size);
  Check(GetTokenInformation(token.get(), TokenUser, bytes.data(), size, &size) != FALSE, "SHELL_TOKEN_QUERY_FAILED");
  LPWSTR sid = nullptr;
  Check(ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid, &sid) != FALSE,
        "SHELL_TOKEN_QUERY_FAILED");
  value.user = sid; LocalFree(sid);
  FILETIME creation{}, exited{}, kernel{}, user{};
  Check(GetProcessTimes(process, &creation, &exited, &kernel, &user) != FALSE, "SHELL_TIME_QUERY_FAILED");
  value.created = (static_cast<uint64_t>(creation.dwHighDateTime) << 32) | creation.dwLowDateTime;
  return value;
}
bool ShellMatches(const ProcessIdentity& process, const std::wstring& image, const std::wstring& user, DWORD session) {
  return process.pid && process.created && process.session == session && process.user == user &&
         _wcsicmp(process.image.c_str(), image.c_str()) == 0;
}
class ExplorerFixture {
 public:
  ExplorerFixture() : window_(GetShellWindow()), process_(OpenShell(window_)) {
    wchar_t windows[32768]{};
    const auto length = GetWindowsDirectoryW(windows, 32768);
    Check(length > 0 && length < 32768, "WINDOWS_PATH_QUERY_FAILED");
    image_ = (std::filesystem::path(windows) / L"explorer.exe").wstring();
    user_ = sd::UserSid();
    Check(ProcessIdToSessionId(GetCurrentProcessId(), &session_) != FALSE, "SESSION_QUERY_FAILED");
    before_ = InspectProcess(process_.get());
    Check(ShellMatches(before_, image_, user_, session_), "SHELL_IDENTITY_NOT_OWN_DESKTOP_EXPLORER");
  }
  ~ExplorerFixture() {
    // Best-effort desktop recovery on an ordinary C++ failure. A force-killed
    // driver/VM is handled by the VM snapshot/operator, never claimed recovered.
    if (terminated_ && !restored_) { try { RestoreShell(); } catch (...) {} }
  }
  const ProcessIdentity& Before() const { return before_; }
  const ProcessIdentity& After() const { return after_; }
  void Restart(uint64_t runStarted) {
    RequireUnlockedDesktop();
    // Leave a wide margin before the wrapper's 300s watchdog. Do not begin a
    // destructive shell fixture after a slow baseline has consumed the budget.
    Check(GetTickCount64() - runStarted < 120000, "SHELL_FIXTURE_START_BUDGET_EXCEEDED");
    DWORD pid = 0;
    GetWindowThreadProcessId(window_, &pid);
    Check(GetShellWindow() == window_ && pid == before_.pid &&
          WaitForSingleObject(process_.get(), 0) == WAIT_TIMEOUT, "SHELL_CHANGED_BEFORE_TERMINATION");
    Check(TerminateProcess(process_.get(), 92) != FALSE, "SHELL_TERMINATION_FAILED");
    terminated_ = true;
    DWORD code = 0;
    Check(WaitForSingleObject(process_.get(), 5000) == WAIT_OBJECT_0 &&
          GetExitCodeProcess(process_.get(), &code) && code == 92, "SHELL_TERMINATION_NOT_OBSERVED");
    RestoreShell();
  }
 private:
  static HANDLE OpenShell(HWND window) {
    DWORD pid = 0;
    Check(window && GetWindowThreadProcessId(window, &pid) && pid, "DESKTOP_SHELL_NOT_FOUND");
    const auto process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_TERMINATE | SYNCHRONIZE, FALSE, pid);
    Check(process != nullptr, "SHELL_PROCESS_OPEN_FAILED");
    return process;
  }
  void StartExplorer() {
    auto command = L"\"" + image_ + L"\"";
    std::wstring desktop = L"winsta0\\default";
    STARTUPINFOW startup{}; startup.cb = sizeof(startup); startup.lpDesktop = desktop.data();
    PROCESS_INFORMATION process{};
    Check(CreateProcessW(image_.c_str(), command.data(), nullptr, nullptr, FALSE, 0, nullptr,
          std::filesystem::path(image_).parent_path().c_str(), &startup, &process) != FALSE, "SHELL_RESTART_FAILED");
    sd::Handle handle(process.hProcess), thread(process.hThread);
  }
  void RestoreShell() {
    const auto started = GetTickCount64();
    bool launched = false;
    while (GetTickCount64() - started < 20000) {
      const auto shell = GetShellWindow();
      DWORD pid = 0;
      if (shell && GetWindowThreadProcessId(shell, &pid) && pid != before_.pid) {
        sd::Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid));
        if (process.valid() && WaitForSingleObject(process.get(), 0) == WAIT_TIMEOUT) {
          auto identity = InspectProcess(process.get());
          Check(ShellMatches(identity, image_, user_, session_) && identity.created != before_.created,
                "RESTORED_SHELL_IDENTITY_MISMATCH");
          after_ = std::move(identity); restored_ = true; return;
        }
      }
      if (!launched && GetTickCount64() - started >= 1500) { StartExplorer(); launched = true; }
      Sleep(25);
    }
    throw std::runtime_error("SHELL_RESTART_TIMEOUT");
  }
  HWND window_;
  sd::Handle process_;
  std::wstring image_, user_;
  DWORD session_ = 0;
  ProcessIdentity before_, after_;
  bool terminated_ = false, restored_ = false;
};
void OwnerReleased(const std::filesystem::path& root) {
  Check(!std::filesystem::exists(root / L"owner.json"), "SESSION_END_STALE_DESCRIPTOR");
  sd::Handle lock(CreateFileW((root / L"owner.lock").c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
      OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  Check(lock.valid(), "SESSION_END_OWNER_LOCK_NOT_RELEASED");
}
int Run(const std::filesystem::path& product, const std::filesystem::path& evidence, bool recovery, bool shell, bool acl) {
  const auto runStarted = GetTickCount64();
  GuardDisposableUser();
  if (shell || acl) RequireVirtualMachine(shell);
  Check(product.is_absolute() && evidence.is_absolute(), "ABSOLUTE_PATH_REQUIRED");
  sd::RejectReparse(product); sd::RejectReparse(evidence.parent_path());
  Journal journal(evidence);
  journal.Write("{\"schemaVersion\":1,\"scope\":\"real EXE lifecycle/recovery; incomplete VM acceptance\",\"recoveryEnabled\":" +
                std::string(recovery ? "true" : "false") + ",\"shellEnabled\":" +
                std::string(shell ? "true" : "false") + ",\"aclEnabled\":" +
                std::string(acl ? "true" : "false") + ",\"fullVmAcceptance\":false}");
  auto step = [&](const char* name, const std::function<void()>& action) {
    const auto started = GetTickCount64();
    journal.Write("{\"event\":\"started\",\"scenario\":" + Quote(sd::Wide(name)) + "}");
    try {
      action();
      journal.Write("{\"event\":\"passed\",\"scenario\":" + Quote(sd::Wide(name)) +
                    ",\"elapsedMs\":" + std::to_string(GetTickCount64() - started) + "}");
    } catch (const std::exception& error) {
      journal.Write("{\"event\":\"failed\",\"scenario\":" + Quote(sd::Wide(name)) +
                    ",\"error\":" + Quote(sd::Wide(error.what())) + "}");
      throw;
    }
  };
  const auto root = ProfileRoot();
  const auto directory = evidence.parent_path() / (L"readonly-exe-" + sd::Uuid());
  const auto exe = directory / L"ServerDeck.exe";
  step("readonly-executable", [&] {
    sd::SecureDirectory(directory);
    Check(CopyFileW(product.c_str(), exe.c_str(), TRUE) != FALSE, "PRODUCT_COPY_FAILED");
    ReadOnly(exe); ReadOnly(directory); AssertNoWrite(exe);
    const auto probe = directory / L"must-not-be-created";
    sd::Handle denied(CreateFileW(probe.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, 0, nullptr));
    const DWORD error = GetLastError();
    Check(!denied.valid() && error == ERROR_ACCESS_DENIED, "EXE_FOLDER_IS_WRITABLE");
  });
  Children children;
  auto& owner = children.Launch(exe);
  HWND window = nullptr;
  std::vector<uint8_t> current, descriptor;
  step("cold-start-original-pid", [&] {
    window = Ready(owner, root); OwnerLocked(root); ModulesInOwner(owner);
    current = ReadSmall(root / L"data/CURRENT.json"); descriptor = ReadSmall(root / L"owner.json");
    journal.Write("{\"event\":\"owner\",\"pid\":" + std::to_string(owner.pid) +
                  ",\"exePath\":" + Quote(exe.wstring()) + "}");
  });
  step("close-keeps-owner", [&] {
    Message(window, WM_CLOSE);
    Wait([&] { Check(owner.Alive(), "CLOSE_TERMINATED_OWNER"); return !IsWindowVisible(window); },
          3000, "CLOSE_DID_NOT_HIDE");
    OwnerLocked(root);
    Check(ReadSmall(root / L"data/CURRENT.json") == current, "CLOSE_REPLACED_STORE");
  });
  step("tray-open-menu", [&] {
    Menu(owner, window, sd::kTrayOpen);
    Wait([&] { return IsWindowVisible(window) && !IsIconic(window); }, 3000, "TRAY_OPEN_DID_NOT_RESTORE");
    Check(FindWindow(owner.pid, kMainClass) == window, "TRAY_OPEN_REPLACED_WINDOW");
  });
  step("system-close-and-double-click", [&] {
    Message(window, WM_SYSCOMMAND, SC_CLOSE);
    Wait([&] { Check(owner.Alive(), "SYSTEM_CLOSE_TERMINATED_OWNER"); return !IsWindowVisible(window); },
          3000, "SYSTEM_CLOSE_DID_NOT_HIDE");
    Check(PostMessageW(window, kTrayNotification, 1, WM_LBUTTONDBLCLK) != FALSE, "TRAY_CALLBACK_FAILED");
    Wait([&] { return IsWindowVisible(window) && !IsIconic(window); }, 3000, "DOUBLE_CLICK_DID_NOT_RESTORE");
  });
  step("concurrent-duplicate-launches", [&] {
    Message(window, WM_CLOSE);
    auto& first = children.CreateSuspended(exe); auto& second = children.CreateSuspended(exe);
    children.Resume(first); children.Resume(second);
    Check(first.Alive() && second.Alive(), "CONCURRENT_OVERLAP_NOT_OBSERVED");
    journal.Write("{\"event\":\"duplicate-overlap\",\"firstPid\":" + std::to_string(first.pid) +
                  ",\"secondPid\":" + std::to_string(second.pid) + "}");
    Check(WaitForSingleObject(first.info.hProcess, 5000) == WAIT_OBJECT_0 && first.ExitCode() == 0 &&
          WaitForSingleObject(second.info.hProcess, 5000) == WAIT_OBJECT_0 && second.ExitCode() == 0,
          "DUPLICATE_DID_NOT_ACTIVATE_AND_EXIT");
    Wait([&] { return IsWindowVisible(window); }, 3000, "DUPLICATE_DID_NOT_RESTORE");
    Check(owner.Alive() && ReadSmall(root / L"owner.json") == descriptor &&
          ReadSmall(root / L"data/CURRENT.json") == current, "DUPLICATE_REPLACED_OWNER_OR_STORE");
    OwnerLocked(root);
  });
  step("minimized-tray-restore", [&] {
    ShowWindow(window, SW_MINIMIZE);
    Check(IsIconic(window) != FALSE, "MINIMIZE_FAILED");
    Menu(owner, window, sd::kTrayOpen);
    Wait([&] { return IsWindowVisible(window) && !IsIconic(window); }, 3000, "MINIMIZE_RESTORE_FAILED");
  });
  step("tray-exit", [&] { Exit(owner, window, root); });
  step("warm-reopen-preserves-store", [&] {
    auto& reopened = children.Launch(exe);
    const auto reopenedWindow = Ready(reopened, root);
    Check(ReadSmall(root / L"data/CURRENT.json") == current, "REOPEN_REPLACED_STORE");
    ModulesInOwner(reopened); OwnerLocked(root); Exit(reopened, reopenedWindow, root);
  });
  if (acl) {
    step("startup-acl-cancel-preserves-data", [&] {
      children.AssertStopped();
      const auto baseline = DataHashes(root);
      DirectoryAclFault fault(root);
      auto& denied = children.Launch(exe);
      const auto dialog = NativeAccessError(denied);
      Check(DataHashes(root) == baseline && ReadSmall(root / L"data/CURRENT.json") == current,
            "ACL_STARTUP_FAILURE_CHANGED_STORE");
      OwnerReleased(root);
      journal.Write("{\"event\":\"startup-acl-denied\",\"pid\":" + std::to_string(denied.pid) +
                    ",\"scenario\":\"startup-acl-cancel-preserves-data\",\"hashedEntries\":" + std::to_string(baseline.size()) + "}");
      RequireUnlockedDesktop(); Automation automation; automation.Button(dialog, IDCANCEL);
      Check(WaitForSingleObject(denied.info.hProcess, 10000) == WAIT_OBJECT_0 && denied.ExitCode() == 1,
            "ACL_STARTUP_CANCEL_FAILED");
      Check(DataHashes(root) == baseline && ReadSmall(root / L"data/CURRENT.json") == current,
            "ACL_CANCEL_CHANGED_STORE");
      fault.Restore();
      auto& reopened = children.Launch(exe);
      const auto reopenedWindow = Ready(reopened, root);
      Check(ReadSmall(root / L"data/CURRENT.json") == current, "ACL_CANCEL_REOPEN_REPLACED_STORE");
      Exit(reopened, reopenedWindow, root);
    });
    step("startup-acl-retry-same-pid", [&] {
      children.AssertStopped();
      const auto baseline = DataHashes(root);
      DirectoryAclFault fault(root);
      auto& denied = children.Launch(exe);
      const auto dialog = NativeAccessError(denied);
      Check(DataHashes(root) == baseline && ReadSmall(root / L"data/CURRENT.json") == current,
            "ACL_RETRY_INITIAL_FAILURE_CHANGED_STORE");
      OwnerReleased(root);
      fault.Restore();
      RequireUnlockedDesktop(); Automation automation; automation.Button(dialog, IDRETRY);
      const auto recoveredWindow = Ready(denied, root);
      Check(ReadSmall(root / L"data/CURRENT.json") == current, "ACL_RETRY_REPLACED_STORE");
      ModulesInOwner(denied); OwnerLocked(root); Exit(denied, recoveredWindow, root);
    });
  }
  if (shell) {
    step("explorer-restart-preserves-owner", [&] {
      auto& active = children.Launch(exe);
      const auto activeWindow = Ready(active, root);
      const auto originalOwner = ReadSmall(root / L"owner.json");
      Message(activeWindow, WM_CLOSE);
      Wait([&] { Check(active.Alive(), "SHELL_TEST_OWNER_EXITED"); return !IsWindowVisible(activeWindow); },
           3000, "SHELL_TEST_WINDOW_DID_NOT_HIDE");
      ExplorerFixture explorer;
      const auto& old = explorer.Before();
      journal.Write("{\"event\":\"explorer-before\",\"pid\":" + std::to_string(old.pid) +
                    ",\"creationTime100ns\":\"" + std::to_string(old.created) + "\",\"sessionId\":" +
                    std::to_string(old.session) + ",\"userSid\":" + Quote(old.user) + ",\"imagePath\":" + Quote(old.image) + "}");
      explorer.Restart(runStarted);
      const auto& fresh = explorer.After();
      journal.Write("{\"event\":\"explorer-restarted\",\"oldPid\":" + std::to_string(old.pid) +
                    ",\"newPid\":" + std::to_string(fresh.pid) + ",\"creationTime100ns\":\"" +
                    std::to_string(fresh.created) + "\"}");
      Check(Ready(active, root) == activeWindow && ReadSmall(root / L"owner.json") == originalOwner &&
            ReadSmall(root / L"data/CURRENT.json") == current, "SHELL_RESTART_REPLACED_OWNER_WINDOW_OR_STORE");
      OwnerLocked(root); Menu(active, activeWindow, sd::kTrayOpen); Exit(active, activeWindow, root);
    });
    step("session-query-native-shutdown", [&] {
      auto& active = children.Launch(exe);
      const auto activeWindow = Ready(active, root);
      Check(Message(activeWindow, WM_QUERYENDSESSION, 0, ENDSESSION_LOGOFF) == TRUE, "SESSION_QUERY_WAS_VETOED");
      Check(WaitForSingleObject(active.info.hProcess, 10000) == WAIT_OBJECT_0 && active.ExitCode() == 0,
            "SESSION_QUERY_DID_NOT_DRAIN_AND_EXIT");
      OwnerReleased(root);
      Check(ReadSmall(root / L"data/CURRENT.json") == current, "SESSION_QUERY_REPLACED_STORE");
    });
    step("session-confirmed-native-shutdown", [&] {
      auto& active = children.Launch(exe);
      const auto activeWindow = Ready(active, root);
      Message(activeWindow, WM_ENDSESSION, TRUE, ENDSESSION_LOGOFF);
      Check(WaitForSingleObject(active.info.hProcess, 10000) == WAIT_OBJECT_0 && active.ExitCode() == 0,
            "SESSION_CONFIRMED_DID_NOT_DRAIN_AND_EXIT");
      OwnerReleased(root);
      auto& reopened = children.Launch(exe);
      const auto reopenedWindow = Ready(reopened, root);
      Check(ReadSmall(root / L"data/CURRENT.json") == current, "SESSION_END_REOPEN_REPLACED_STORE");
      Exit(reopened, reopenedWindow, root);
    });
  }
  if (recovery) {
    std::filesystem::path runtime;
    step("owned-crash-reopen-store-identity", [&] {
      auto& crashing = children.Launch(exe);
      Ready(crashing, root);
      const auto before = ReadSmall(root / L"owner.json");
      children.Crash(crashing);
      journal.Write("{\"event\":\"forced-crash\",\"pid\":" + std::to_string(crashing.pid) + ",\"exitCode\":91}");
      auto& reopened = children.Launch(exe);
      const auto nextWindow = Ready(reopened, root);
      Check(ReadSmall(root / L"data/CURRENT.json") == current && ReadSmall(root / L"owner.json") != before,
            "CRASH_REOPEN_LOST_STORE_OR_OWNER_IDENTITY");
      runtime = ModulesInOwner(reopened); ValidateRuntime(runtime, root);
      OwnerLocked(root); Exit(reopened, nextWindow, root);
    });
    step("corrupt-cache-quarantine-and-reopen", [&] {
      children.AssertStopped(); ValidateRuntime(runtime, root);
      const auto cacheFile = runtime / L"data/icudtl.dat";
      const auto originalHash = HashFile(cacheFile);
      const auto before = RuntimeSiblings(runtime, L".quarantine-");
      FlipFirstByte(cacheFile);
      Check(HashFile(cacheFile) != originalHash, "CACHE_CORRUPTION_NOT_APPLIED");
      auto& reopened = children.Launch(exe);
      const auto nextWindow = Ready(reopened, root);
      const auto after = RuntimeSiblings(runtime, L".quarantine-");
      size_t added = 0;
      for (const auto& path : after) if (!before.count(path)) {
        Check(HashFile(path / L"data/icudtl.dat") != originalHash, "QUARANTINE_DID_NOT_PRESERVE_CORRUPTION");
        ++added;
      }
      Check(added == 1 && HashFile(cacheFile) == originalHash && ReadSmall(root / L"data/CURRENT.json") == current,
            "CACHE_RECOVERY_FAILED_OR_REPLACED_STORE");
      Exit(reopened, nextWindow, root);
    });
    step("interrupted-extraction-and-reopen", [&] {
      children.AssertStopped(); ValidateRuntime(runtime, root);
      const auto saved = runtime.wstring() + L".saved-fixture-" + sd::Uuid();
      Check(MoveFileExW(runtime.c_str(), saved.c_str(), MOVEFILE_WRITE_THROUGH) != FALSE, "CACHE_FIXTURE_RENAME_FAILED");
      const auto oldStages = RuntimeSiblings(runtime, L".staging-");
      auto& interrupted = children.Launch(exe);
      std::filesystem::path captured;
      const auto start = GetTickCount64();
      while (interrupted.Alive() && GetTickCount64() - start < 30000) {
        const auto stages = RuntimeSiblings(runtime, L".staging-");
        for (const auto& path : stages) if (!oldStages.count(path)) { captured = path; break; }
        if (!captured.empty()) break;
        Sleep(1);
      }
      Check(!captured.empty(), "INTERRUPTED_STAGE_NOT_OBSERVED");
      children.Crash(interrupted);
      Check(std::filesystem::exists(captured) && !std::filesystem::exists(runtime), "INTERRUPTION_MISSED_PUBLICATION");
      journal.Write("{\"event\":\"interrupted-stage\",\"pid\":" + std::to_string(interrupted.pid) +
                    ",\"stage\":" + Quote(captured.wstring()) + ",\"exitCode\":91}");
      auto& reopened = children.Launch(exe);
      const auto nextWindow = Ready(reopened, root);
      Check(ReadSmall(root / L"data/CURRENT.json") == current && std::filesystem::exists(captured),
            "INTERRUPTED_RECOVERY_REPLACED_STORE_OR_REMOVED_EVIDENCE");
      const auto loaded = ModulesInOwner(reopened); ValidateRuntime(loaded, root);
      Check(_wcsicmp(loaded.c_str(), runtime.c_str()) == 0, "INTERRUPTED_RECOVERY_LOADED_WRONG_RUNTIME");
      Exit(reopened, nextWindow, root);
    });
    auto metadataCase = [&](const char* name, const std::vector<uint8_t>& injected, const wchar_t* expectedError, bool missing) {
      step(name, [&] {
        children.AssertStopped();
        const auto baseline = DataHashes(root);
        const auto metadata = root / L"data/CURRENT.json";
        const auto backup = root / (L"CURRENT.fixture-backup-" + sd::Uuid() + L".json");
        Check(ReadSmall(metadata) == current, "CURRENT_FIXTURE_EXPECTED_ORIGINAL");
        if (missing) Check(MoveFileExW(metadata.c_str(), backup.c_str(), MOVEFILE_WRITE_THROUGH) != FALSE,
                           "CURRENT_FIXTURE_RENAME_FAILED");
        else {
          Check(CopyFileW(metadata.c_str(), backup.c_str(), TRUE) && ReadSmall(backup) == current,
                "CURRENT_FIXTURE_BACKUP_FAILED");
          sd::AtomicFile(metadata, injected);
        }
        auto& blocked = children.Launch(exe);
        const auto blockedWindow = StorageBlocked(blocked, expectedError);
        OwnerLocked(root);
        Check(DataHashes(root) == baseline && (missing ? !std::filesystem::exists(metadata) : ReadSmall(metadata) == injected),
              "BLOCKED_START_CHANGED_DATA_OR_CURRENT");
        journal.Write("{\"event\":\"blocked-data-unchanged\",\"scenario\":" + Quote(sd::Wide(name)) +
                      ",\"hashedEntries\":" + std::to_string(baseline.size()) + ",\"backup\":" + Quote(backup.wstring()) + "}");
        sd::AtomicFile(metadata, current);
        Automation automation;
        const auto retry = automation.Named(blockedWindow, L"Повторить", UIA_ButtonControlTypeId);
        Check(retry != nullptr, "STORAGE_RETRY_ACTION_MISSING");
        automation.Invoke(retry.Get());
        Check(Ready(blocked, root) == blockedWindow && ReadSmall(metadata) == current, "STORAGE_RETRY_REPLACED_WINDOW_OR_STORE");
        Exit(blocked, blockedWindow, root);
      });
    };
    metadataCase("future-current-block-and-retry", FutureCurrent(current), L"INCOMPATIBLE_STORE", false);
    metadataCase("invalid-current-block-and-retry", {'{', '!'}, L"INCOMPATIBLE_STORE", false);
    metadataCase("missing-current-block-and-retry", {}, L"UNPUBLISHED_STORE", true);
  }
  journal.Write("{\"event\":\"completed\",\"fullVmAcceptance\":false}");
  std::cout << "Lifecycle scenarios completed; remaining VM/fault acceptance is not claimed\n";
  return 0;
}
int SelfTest() {
  Check(VirtualModel(L"Microsoft Corporation Virtual Machine") && VirtualModel(L"VMware Virtual Platform") &&
        !VirtualModel(L"Micro-Star International MS-7E07"), "VM_MODEL_CLASSIFIER_FAILED");
  const ProcessIdentity synthetic{10, 2, 1234, L"C:\\Windows\\explorer.exe", L"S-1-5-21-1"};
  Check(ShellMatches(synthetic, L"c:\\WINDOWS\\EXPLORER.EXE", synthetic.user, 2) &&
        !ShellMatches(synthetic, synthetic.image, L"S-1-5-21-2", 2) &&
        !ShellMatches(synthetic, synthetic.image, synthetic.user, 3) &&
        !ShellMatches(synthetic, L"C:\\other\\explorer.exe", synthetic.user, 2), "SHELL_IDENTITY_VALIDATION_FAILED");
  const auto self = InspectProcess(GetCurrentProcess());
  Check(self.pid == GetCurrentProcessId() && self.user == sd::UserSid() && self.created != 0,
        "SELF_PROCESS_IDENTITY_FAILED");
  wchar_t temporary[32768]{};
  Check(GetTempPathW(32768, temporary) > 0, "TEMP_PATH_FAILED");
  const auto root = std::filesystem::path(temporary) / (L"ServerDeckLifecycleFixture-" + sd::Uuid());
  sd::SecureDirectory(root);
  const auto file = root / L"synthetic.txt";
  { std::ofstream output(file); output << "synthetic"; }
  try {
    ReadOnly(file); ReadOnly(root); AssertNoWrite(file);
    Journal journal(root.parent_path() / (root.filename().wstring() + L".jsonl"));
    journal.Write("{\"scope\":\"synthetic lifecycle helper self-test\"}");
    Check(Quote(L"a\n\"\\") == "\"a\\u000a\\\"\\\\\"", "JSON_ESCAPE_FAILED");
  } catch (...) { sd::SecureDirectory(root); sd::SecureFile(file); throw; }
  sd::SecureDirectory(root); sd::SecureFile(file);
  {
    DirectoryAclFault fault(root);
    bool rejected = false;
    try { sd::SecureDirectory(root); } catch (const std::exception&) { rejected = true; }
    Check(rejected, "ACL_FIXTURE_DID_NOT_REJECT_NATIVE_REPAIR");
    Check(ReadSmall(file) == std::vector<uint8_t>({'s','y','n','t','h','e','t','i','c'}), "ACL_FIXTURE_CHANGED_FILE_BYTES");
    fault.Restore();
  }
  sd::SecureDirectory(root);
  const auto data = root / L"data";
  const auto stores = data / L"stores";
  const auto store = stores / L"synthetic";
  sd::SecureDirectory(data); sd::SecureDirectory(stores); sd::SecureDirectory(store);
  const auto metadata = data / L"CURRENT.json";
  const auto database = store / L"synthetic.bin";
  const std::string original = "{\"formatVersion\":1,\"other\":\"preserve\"}";
  const std::vector<uint8_t> originalBytes(original.begin(), original.end());
  sd::AtomicFile(metadata, originalBytes); sd::AtomicFile(database, {'d', 'a', 't', 'a'});
  const auto future = FutureCurrent(originalBytes);
  Check(std::string(future.begin(), future.end()) == "{\"formatVersion\":2147483647,\"other\":\"preserve\"}",
        "FUTURE_CURRENT_FIXTURE_CHANGED_OTHER_FIELDS");
  bool rejected = false;
  try { FutureCurrent(future); } catch (const std::runtime_error& error) {
    rejected = std::string(error.what()) == "FIXTURE_EXPECTED_FORMAT_ONE_CURRENT";
  }
  Check(rejected, "FUTURE_CURRENT_FIXTURE_ACCEPTED_WRONG_INPUT");
  const auto baseline = DataHashes(root);
  sd::AtomicFile(metadata, future);
  Check(DataHashes(root) == baseline, "DATA_HASHES_DID_NOT_EXCLUDE_CURRENT");
  FlipFirstByte(database);
  Check(DataHashes(root) != baseline, "DATA_HASHES_MISSED_CHANGED_FILE");
  FlipFirstByte(database);
  Check(DataHashes(root) == baseline, "DATA_HASHES_RESTORATION_FAILED");
  sd::SecureDirectory(data / L"staging-synthetic");
  Check(DataHashes(root) != baseline, "DATA_HASHES_MISSED_ADDED_DIRECTORY");
  std::filesystem::remove(data / L"staging-synthetic");
  std::filesystem::remove(database); std::filesystem::remove(metadata);
  std::filesystem::remove(store); std::filesystem::remove(stores); std::filesystem::remove(data);
  // Only this newly created direct child of the known temp directory is removed.
  Check(std::filesystem::equivalent(root.parent_path(), std::filesystem::path(temporary)), "FIXTURE_PATH_FAILED");
  std::filesystem::remove(file); std::filesystem::remove(root);
  std::filesystem::remove(root.parent_path() / (root.filename().wstring() + L".jsonl"));
  wchar_t image[32768]{};
  const DWORD imageLength = GetModuleFileNameW(nullptr, image, 32768);
  Check(imageLength > 0 && imageLength < 32768, "SELF_IMAGE_QUERY_FAILED");
  std::vector<std::unique_ptr<sd::Handle>> probes;
  {
    Children children;
    auto& first = children.CreateSuspended(image, L"--fixture-wait");
    auto& second = children.CreateSuspended(image, L"--fixture-wait");
    children.Resume(first); children.Resume(second);
    Check(first.Alive() && second.Alive(), "FIXTURE_CONCURRENT_OVERLAP_FAILED");
    for (const auto* child : {&first, &second}) {
      HANDLE copy = nullptr;
      Check(DuplicateHandle(GetCurrentProcess(), child->info.hProcess, GetCurrentProcess(),
            &copy, SYNCHRONIZE, FALSE, 0) != FALSE, "FIXTURE_HANDLE_DUPLICATION_FAILED");
      probes.push_back(std::make_unique<sd::Handle>(copy));
    }
  }
  for (const auto& probe : probes)
    Check(WaitForSingleObject(probe->get(), 5000) == WAIT_OBJECT_0, "JOB_CLOSE_LEFT_CHILD_RUNNING");
  std::cout << "lifecycle helper self-test passed\n";
  return 0;
}
}
int wmain(int count, wchar_t** args) {
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(com)) return 1;
  int result = 2;
  try {
    if (count == 2 && std::wstring(args[1]) == L"--fixture-wait") { Sleep(30000); result = 0; }
    else if (count == 2 && std::wstring(args[1]) == L"--self-test") result = SelfTest();
    else if (count == 2 && std::wstring(args[1]) == L"--probe-vm") {
      RequireVirtualMachine(true); std::cout << "VM_GUARD_ACCEPTED\n"; result = 0;
    }
    else if (count == 6 && (std::wstring(args[1]) == L"--run" || std::wstring(args[1]) == L"--run-recovery" ||
             std::wstring(args[1]) == L"--run-shell" || std::wstring(args[1]) == L"--run-acl") &&
             std::wstring(args[2]) == L"--exe" && std::wstring(args[4]) == L"--output")
      result = Run(args[3], args[5], std::wstring(args[1]) == L"--run-recovery", std::wstring(args[1]) == L"--run-shell",
                   std::wstring(args[1]) == L"--run-acl");
    else std::cerr << "INVALID_ARGUMENTS\n";
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; result = 1; }
  CoUninitialize();
  return result;
}

