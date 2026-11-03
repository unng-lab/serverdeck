#include "security.h"
#include <psapi.h>
#include <sddl.h>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>

// Read-only facts for the disposable-VM smoke runner. This helper never sends
// window input, opens Isar, terminates a process or changes the product profile.
namespace {
struct WindowFact {
  HWND handle;
  std::wstring className;
  bool visible;
  bool minimized;
};
struct Snapshot {
  DWORD pid;
  DWORD session;
  ULONGLONG created;
  std::wstring image;
  std::wstring sid;
  std::vector<std::wstring> modules;
  std::vector<WindowFact> windows;
};
std::wstring ImagePath(HANDLE process) {
  std::wstring value(32768, L'\0');
  DWORD size = static_cast<DWORD>(value.size());
  if (!QueryFullProcessImageNameW(process, 0, value.data(), &size))
    throw std::runtime_error("IMAGE_QUERY_FAILED");
  value.resize(size);
  return value;
}
std::wstring OwnerSid(HANDLE process) {
  HANDLE raw = nullptr;
  if (!OpenProcessToken(process, TOKEN_QUERY, &raw))
    throw std::runtime_error("TOKEN_QUERY_FAILED");
  sd::Handle token(raw);
  DWORD size = 0;
  GetTokenInformation(token.get(), TokenUser, nullptr, 0, &size);
  if (!size) throw std::runtime_error("TOKEN_USER_FAILED");
  std::vector<BYTE> bytes(size);
  if (!GetTokenInformation(token.get(), TokenUser, bytes.data(), size, &size))
    throw std::runtime_error("TOKEN_USER_FAILED");
  LPWSTR text = nullptr;
  if (!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid, &text))
    throw std::runtime_error("SID_CONVERSION_FAILED");
  const std::wstring sid(text);
  LocalFree(text);
  return sid;
}
struct WindowQuery {
  DWORD pid;
  bool failed = false;
  std::vector<WindowFact> facts;
};
BOOL CALLBACK CollectWindow(HWND window, LPARAM parameter) {
  auto& query = *reinterpret_cast<WindowQuery*>(parameter);
  DWORD pid = 0;
  GetWindowThreadProcessId(window, &pid);
  if (pid != query.pid) return TRUE;
  try {
    wchar_t name[256]{};
    if (!GetClassNameW(window, name, 256)) {
      query.failed = true;
      return FALSE;
    }
    query.facts.push_back({window, name, IsWindowVisible(window) != FALSE,
                           IsIconic(window) != FALSE});
    return TRUE;
  } catch (...) {
    query.failed = true;
    return FALSE;
  }
}
Snapshot Observe(DWORD pid, const std::wstring& expectedImage) {
  sd::Handle process(OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ | SYNCHRONIZE,
                                FALSE, pid));
  if (!process.valid()) throw std::runtime_error("PROCESS_OPEN_FAILED");
  if (WaitForSingleObject(process.get(), 0) != WAIT_TIMEOUT)
    throw std::runtime_error("PROCESS_NOT_RUNNING");
  Snapshot result{};
  result.pid = pid;
  result.image = ImagePath(process.get());
  if (_wcsicmp(result.image.c_str(), expectedImage.c_str()) != 0)
    throw std::runtime_error("PROCESS_IMAGE_MISMATCH");
  result.sid = OwnerSid(process.get());
  if (result.sid != sd::UserSid()) throw std::runtime_error("PROCESS_USER_MISMATCH");
  if (!ProcessIdToSessionId(pid, &result.session))
    throw std::runtime_error("PROCESS_SESSION_FAILED");
  FILETIME creation{}, exit{}, kernel{}, user{};
  if (!GetProcessTimes(process.get(), &creation, &exit, &kernel, &user))
    throw std::runtime_error("PROCESS_TIME_FAILED");
  result.created = (static_cast<ULONGLONG>(creation.dwHighDateTime) << 32) | creation.dwLowDateTime;
  std::vector<HMODULE> modules(256);
  for (;;) {
    DWORD needed = 0;
    if (!EnumProcessModulesEx(process.get(), modules.data(),
          static_cast<DWORD>(modules.size() * sizeof(HMODULE)), &needed, LIST_MODULES_64BIT))
      throw std::runtime_error("MODULE_QUERY_FAILED");
    if (needed <= modules.size() * sizeof(HMODULE)) {
      modules.resize(needed / sizeof(HMODULE));
      break;
    }
    if (needed > 16384 * sizeof(HMODULE)) throw std::runtime_error("MODULE_LIMIT_EXCEEDED");
    modules.resize(needed / sizeof(HMODULE) + 16);
  }
  for (const auto module : modules) {
    std::wstring path(32768, L'\0');
    const auto size = GetModuleFileNameExW(process.get(), module, path.data(),
                                          static_cast<DWORD>(path.size()));
    if (!size || size >= path.size()) throw std::runtime_error("MODULE_PATH_FAILED");
    path.resize(size);
    result.modules.push_back(std::move(path));
  }
  WindowQuery query{pid};
  if (!EnumWindows(CollectWindow, reinterpret_cast<LPARAM>(&query)) || query.failed)
    throw std::runtime_error("WINDOW_QUERY_FAILED");
  result.windows = std::move(query.facts);
  if (WaitForSingleObject(process.get(), 0) != WAIT_TIMEOUT)
    throw std::runtime_error("PROCESS_EXITED_DURING_OBSERVATION");
  return result;
}
std::string Json(const std::wstring& value) {
  std::ostringstream output;
  output << '"';
  for (const unsigned char byte : sd::Utf8(value)) {
    if (byte == '"' || byte == '\\') output << '\\' << byte;
    else if (byte < 0x20) {
      constexpr char hex[] = "0123456789abcdef";
      output << "\\u00" << hex[byte >> 4] << hex[byte & 15];
    } else output << byte;
  }
  output << '"';
  return output.str();
}
std::string Serialize(const Snapshot& value) {
  std::ostringstream output;
  output << "{\"schemaVersion\":1,\"scope\":\"read-only process snapshot; no acceptance conclusion\","
         << "\"pid\":" << value.pid << ",\"sessionId\":" << value.session
         << ",\"creationTime100ns\":\"" << value.created << "\",\"imagePath\":" << Json(value.image)
         << ",\"userSid\":" << Json(value.sid) << ",\"modules\":[";
  bool comma = false;
  for (const auto& path : value.modules) {
    if (comma) output << ',';
    output << Json(path);
    comma = true;
  }
  output << "],\"windows\":[";
  comma = false;
  for (const auto& window : value.windows) {
    if (comma) output << ',';
    output << "{\"handle\":\"" << reinterpret_cast<UINT_PTR>(window.handle)
           << "\",\"className\":" << Json(window.className)
           << ",\"visible\":" << (window.visible ? "true" : "false")
           << ",\"minimized\":" << (window.minimized ? "true" : "false") << '}';
    comma = true;
  }
  output << "]}";
  return output.str();
}
void Require(bool condition) {
  if (!condition) throw std::runtime_error("OBSERVER_SELF_TEST_FAILED");
}
int SelfTest() {
  const auto image = ImagePath(GetCurrentProcess());
  const auto self = Observe(GetCurrentProcessId(), image);
  Require(self.pid == GetCurrentProcessId() && self.created != 0 && self.sid == sd::UserSid());
  Require(!self.modules.empty());
  Require(Json(L"a\"\\\n\t\x01") == "\"a\\\"\\\\\\u000a\\u0009\\u0001\"");
  Require(Json(L"Открыть") == "\"\xd0\x9e\xd1\x82\xd0\xba\xd1\x80\xd1\x8b\xd1\x82\xd1\x8c\"");
  bool rejected = false;
  try { Observe(GetCurrentProcessId(), image + L".wrong"); }
  catch (const std::runtime_error& error) { rejected = std::string(error.what()) == "PROCESS_IMAGE_MISMATCH"; }
  Require(rejected);
  rejected = false;
  try { Observe(0, image); }
  catch (const std::runtime_error& error) { rejected = std::string(error.what()) == "PROCESS_OPEN_FAILED"; }
  Require(rejected);
  const HWND window = CreateWindowExW(0, L"STATIC", L"synthetic observer input", WS_OVERLAPPED,
                                    0, 0, 1, 1, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  Require(window != nullptr);
  try {
    const auto snapshot = Observe(GetCurrentProcessId(), image);
    bool found = false;
    for (const auto& item : snapshot.windows) {
      if (item.handle == window) { found = true; Require(!item.visible && !item.minimized); }
    }
    Require(found);
    const auto json = Serialize(snapshot);
    Require(json.find("\"className\":\"Static\"") != std::string::npos);
  } catch (...) { DestroyWindow(window); throw; }
  DestroyWindow(window);
  std::cout << "release observer self-test passed\n";
  return 0;
}
DWORD ParsePid(const std::wstring& value) {
  if (value.empty()) throw std::invalid_argument("INVALID_ARGUMENTS");
  ULONGLONG pid = 0;
  for (const auto digit : value) {
    if (digit < L'0' || digit > L'9') throw std::invalid_argument("INVALID_ARGUMENTS");
    pid = pid * 10 + static_cast<unsigned>(digit - L'0');
    if (pid > std::numeric_limits<DWORD>::max()) throw std::invalid_argument("INVALID_ARGUMENTS");
  }
  if (!pid) throw std::invalid_argument("INVALID_ARGUMENTS");
  return static_cast<DWORD>(pid);
}
}
int wmain(int count, wchar_t** args) {
  try {
    if (count == 2 && std::wstring(args[1]) == L"--self-test") return SelfTest();
    if (count != 5 || std::wstring(args[1]) != L"--pid" || std::wstring(args[3]) != L"--exe")
      throw std::invalid_argument("INVALID_ARGUMENTS");
    const std::filesystem::path image(args[4]);
    if (!image.is_absolute()) throw std::invalid_argument("INVALID_ARGUMENTS");
    std::cout << Serialize(Observe(ParsePid(args[2]), image.wstring())) << '\n';
    return 0;
  } catch (const std::invalid_argument&) {
    std::cerr << "{\"error\":\"INVALID_ARGUMENTS\"}\n";
    return 2;
  } catch (const std::exception& error) {
    std::cerr << "{\"error\":" << Json(sd::Wide(error.what())) << "}\n";
    return 1;
  }
}
