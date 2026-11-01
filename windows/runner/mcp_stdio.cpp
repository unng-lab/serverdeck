#include "mcp_stdio.h"

#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <array>
#include <condition_variable>
#include <cstdint>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <deque>
#include <functional>
#include <mutex>
#include <variant>

namespace {
using Value = flutter::EncodableValue;
using Reply = std::shared_ptr<flutter::MethodResult<Value>>;
constexpr size_t kChunk = 65536;
constexpr size_t kFrame = 8388609;
[[noreturn]] void Finish(DWORD code) {
  // No domain Host lives here. Avoid DLL/CRT detach locks on uncertain I/O.
  ::TerminateProcess(::GetCurrentProcess(), code);
  ::ExitProcess(code);
}
[[noreturn]] void Fail() { Finish(1); }
void Error(const Reply& reply) { reply->Error("STDIO_UNAVAILABLE"); }
void Wipe(std::vector<uint8_t>& bytes) {
  if (!bytes.empty()) ::SecureZeroMemory(bytes.data(), bytes.size());
}

bool ResetInheritedCrt() {
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  ::GetStartupInfoW(&startup);
  if (startup.cbReserved2 == 0) return true;
  // libuv/UCRT inheritance ABI: int count, byte flags[count], intptr handles[count].
  // The runner CRT already consumed it. Prevent a delayed private SDK CRT from
  // reopening original stdio behind the quarantined Win32 standard handles.
  DWORD count = 0;
  SIZE_T copied = 0;
  if (!startup.lpReserved2 || startup.cbReserved2 < sizeof(count) ||
      !::ReadProcessMemory(::GetCurrentProcess(), startup.lpReserved2, &count,
                           sizeof(count), &copied) || copied != sizeof(count) ||
      count > 2048 || sizeof(count) + count * (1 + sizeof(HANDLE)) >
                          startup.cbReserved2) return false;
  count = 0;
  if (!::WriteProcessMemory(::GetCurrentProcess(), startup.lpReserved2, &count,
                            sizeof(count), &copied) || copied != sizeof(count))
    return false;
  DWORD check = 1;
  return ::ReadProcessMemory(::GetCurrentProcess(), startup.lpReserved2, &check,
                             sizeof(check), &copied) &&
         copied == sizeof(check) && check == 0;
}

bool IsOverlapped(HANDLE handle, bool* result) {
  // FileModeInformation is the same Windows native file-mode query used by
  // libuv. Both synchronous and overlapped inherited stdio are supported.
  struct IoStatus { ULONG_PTR status; ULONG_PTR information; } status{};
  using Query = LONG(NTAPI*)(HANDLE, IoStatus*, void*, ULONG, ULONG);
  const auto address = ::GetProcAddress(::GetModuleHandleW(L"ntdll.dll"),
                                        "NtQueryInformationFile");
  if (!address) return false;
  Query query = nullptr;
  static_assert(sizeof(query) == sizeof(address));
  std::memcpy(&query, &address, sizeof(query));
  ULONG mode = 0;
  if (query(handle, &status, &mode, sizeof(mode), 16) < 0) return false;
  *result = (mode & (0x10 | 0x20)) == 0;
  return true;
}
}  // namespace

struct McpStdio::State {
  struct Port {
    State* owner = nullptr;
    size_t index = 0;
    HANDLE io = nullptr, event = nullptr, thread = nullptr;
    bool pending = false, asynchronous = false;
    Reply request;
    std::vector<uint8_t> bytes;
  };
  std::array<Port, 3> ports{};
  HANDLE nul = nullptr, wake = nullptr, watch = nullptr;
  std::mutex mutex;
  std::condition_variable changed;
  std::deque<std::function<void()>> completions;
  std::unique_ptr<flutter::MethodChannel<Value>> channel;
  Reply close_reply;
  bool attached = false, closing = false, failed_close = false;
  bool clean_closed = false;
  bool watch_stop = false;
  ULONGLONG deadline = 0;
  size_t diagnostic_count = 0;

  bool Stop() {
    std::lock_guard<std::mutex> lock(mutex);
    return closing;
  }
  void CheckedClose(HANDLE& handle) {
    if (handle && !::CloseHandle(handle)) failed_close = true;
    handle = nullptr;
  }
  static DWORD WINAPI Watch(void* context) {
    auto& s = *static_cast<State*>(context);
    std::unique_lock<std::mutex> lock(s.mutex);
    while (!s.watch_stop) {
      if (s.deadline == 0) {
        s.changed.wait(lock);
      } else {
        const auto now = ::GetTickCount64();
        if (now >= s.deadline) Fail();
        s.changed.wait_for(lock, std::chrono::milliseconds(s.deadline - now));
      }
    }
    ::SetEvent(s.wake);
    return 0;
  }
  static DWORD WINAPI Worker(void* context) {
    auto& p = *static_cast<Port*>(context);
    p.owner->Work(p);
    return 0;
  }
  void Work(Port& p) {
    for (;;) {
      Reply reply;
      std::vector<uint8_t> bytes;
      {
        std::unique_lock<std::mutex> lock(mutex);
        changed.wait(lock, [&] { return closing || p.request; });
        if (!p.request && closing) break;
        reply = std::move(p.request);
        bytes = std::move(p.bytes);
      }
      bool ok = !Stop();
      bool eof = false;
      size_t offset = 0;
      if (p.index == 0) bytes.resize(kChunk);
      while (ok && offset < bytes.size()) {
        if (Stop()) { ok = false; break; }
        OVERLAPPED overlapped{};
        overlapped.hEvent = p.event;
        ::ResetEvent(p.event);
        DWORD transferred = 0;
        const auto size = static_cast<DWORD>(
            std::min(kChunk, bytes.size() - offset));
        auto* operation = p.asynchronous ? &overlapped : nullptr;
        auto* count = p.asynchronous ? nullptr : &transferred;
        const BOOL issued = p.index == 0
            ? ::ReadFile(p.io, bytes.data(), size, count, operation)
            : ::WriteFile(p.io, bytes.data() + offset, size, count, operation);
        DWORD error = issued ? ERROR_SUCCESS : ::GetLastError();
        if (p.asynchronous && (issued || error == ERROR_IO_PENDING)) {
          if (::GetOverlappedResult(p.io, &overlapped, &transferred, TRUE)) {
            error = ERROR_SUCCESS;
          } else { error = ::GetLastError(); }
        }
        if (p.index == 0 && (error == ERROR_BROKEN_PIPE ||
                             error == ERROR_HANDLE_EOF)) {
          eof = true;
          break;
        }
        if (error != ERROR_SUCCESS || transferred > size) {
          ok = false;
          break;
        }
        if (p.index == 0) {
          eof = transferred == 0;
          offset = transferred;
          break;
        }
        if (transferred == 0) { ok = false; break; }
        offset += transferred;
      }
      if (p.index == 0 && ok) {
        // Do not copy unread bytes into a method envelope.
        if (eof) offset = 0;
        ::SecureZeroMemory(bytes.data() + offset, bytes.size() - offset);
        bytes.resize(offset);
      }
      {
        std::lock_guard<std::mutex> lock(mutex);
        completions.push_back([&p, reply, bytes = std::move(bytes), ok]() mutable {
          p.pending = false;
          if (!ok) Error(reply);
          else if (p.index == 0) reply->Success(Value(bytes));
          else reply->Success(Value(true));
          Wipe(bytes);
        });
        ::SetEvent(wake);
      }
    }
    // Main cancellation and worker disposal share the lock: no cancellation of
    // a reused HANDLE value after this worker has closed its own handle.
    std::lock_guard<std::mutex> lock(mutex);
    CheckedClose(p.io);
    CheckedClose(p.event);
    ::SetEvent(wake);
  }
  void Close(const Reply& reply) {
    std::lock_guard<std::mutex> lock(mutex);
    if (closing) { Error(reply); return; }
    closing = true;
    close_reply = reply;
    deadline = ::GetTickCount64() + 5000;
    for (auto& p : ports) {
      if (p.io) ::CancelIoEx(p.io, nullptr);
      if (p.thread) ::CancelSynchronousIo(p.thread);
    }
    changed.notify_all();
    ::SetEvent(wake);
  }
  void Call(const flutter::MethodCall<Value>& call, const Reply& reply) {
    const auto& method = call.method_name();
    const auto* arg = call.arguments();
    if (method == "finish") {
      const auto* code = arg ? std::get_if<int32_t>(arg) : nullptr;
      if (!code || *code < 0 || *code > 255 || (*code == 0 && !clean_closed)) {
        Error(reply); return;
      }
      if (*code == 0) {
        CheckedClose(nul);
        CheckedClose(wake);
        if (failed_close) Fail();
      }
      Finish(static_cast<DWORD>(*code));
    }
    if (method == "close" && (!arg || std::holds_alternative<std::monostate>(*arg))) {
      Close(reply); return;
    }
    if (closing) { Error(reply); return; }
    if (method == "attach") {
      const auto* version = arg ? std::get_if<int32_t>(arg) : nullptr;
      if (attached || !version || *version != 1) { Error(reply); return; }
      attached = true;
      reply->Success(Value(int32_t{1}));
      return;
    }
    if (!attached) { Error(reply); return; }
    size_t index;
    std::vector<uint8_t> bytes;
    if (method == "read" && (!arg || std::holds_alternative<std::monostate>(*arg))) {
      index = 0;
    } else if (method == "write") {
      const auto* value = arg ? std::get_if<std::vector<uint8_t>>(arg) : nullptr;
      if (!value || value->empty() || value->size() > kFrame) { Error(reply); return; }
      index = 1;
      bytes = *value;
    } else if (method == "diagnostic") {
      const auto* value = arg ? std::get_if<std::string>(arg) : nullptr;
      if (!value || value->size() < 6 || value->size() > 69 ||
          value->compare(0, 4, "MCP:") != 0 || value->back() != '\n' ||
          (*value)[4] < 'A' || (*value)[4] > 'Z') { Error(reply); return; }
      for (size_t i = 4; i + 1 < value->size(); ++i) {
        const char c = (*value)[i];
        if (!(c >= 'A' && c <= 'Z') && !(c >= '0' && c <= '9') && c != '_') {
          Error(reply); return;
        }
      }
      index = 2;
      bytes.assign(value->begin(), value->end());
    } else { Error(reply); return; }
    std::lock_guard<std::mutex> lock(mutex);
    auto& p = ports[index];
    if (p.pending || closing || (index == 2 && diagnostic_count >= 32)) {
      Wipe(bytes); Error(reply); return;
    }
    if (index == 0) deadline = 0;  // Bootstrap completed before server input.
    if (index == 2) ++diagnostic_count;
    p.pending = true;
    p.request = reply;
    p.bytes = std::move(bytes);
    changed.notify_all();
  }
};

McpStdio::McpStdio() : state_(std::make_unique<State>()) {}
McpStdio::~McpStdio() {
  auto& s = *state_;
  // A bound messenger and live I/O must never be freed under a worker. This
  // process has no application Host; its terminal fallback owns only itself.
  if (s.channel || s.watch) Fail();
  for (auto& p : s.ports) {
    if (p.thread) Fail();
    s.CheckedClose(p.io); s.CheckedClose(p.event);
  }
  s.CheckedClose(s.nul); s.CheckedClose(s.wake);
  if (s.failed_close) Fail();
}

std::unique_ptr<McpStdio> McpStdio::Capture() {
  if (::GetModuleHandleW(L"flutter_windows.dll")) return nullptr;
  auto owner = std::unique_ptr<McpStdio>(new McpStdio());
  auto& s = *owner->state_;
  s.wake = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!s.wake) return nullptr;
  s.deadline = ::GetTickCount64() + 30000;
  s.watch = ::CreateThread(nullptr, 0, State::Watch, &s, 0, nullptr);
  if (!s.watch) return nullptr;
  const std::array<DWORD, 3> ids{STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE};
  for (size_t i = 0; i < s.ports.size(); ++i) {
    auto& p = s.ports[i];
    const auto original = ::GetStdHandle(ids[i]);
    const bool absent = !original || original == INVALID_HANDLE_VALUE;
    const bool merged = i == 2 && !absent && ::CompareObjectHandles(
        original, ::GetStdHandle(STD_OUTPUT_HANDLE));
    if (i == 2 && (absent || merged)) {
      p.io = ::CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                           nullptr, OPEN_EXISTING, 0, nullptr);
      if (p.io == INVALID_HANDLE_VALUE) { p.io = nullptr; return nullptr; }
    } else {
      if (absent || (i < 2 && ::GetFileType(original) != FILE_TYPE_PIPE) ||
          !::DuplicateHandle(::GetCurrentProcess(), original, ::GetCurrentProcess(),
                             &p.io, 0, FALSE, DUPLICATE_SAME_ACCESS)) return nullptr;
    }
    if (::GetFileType(p.io) != FILE_TYPE_CHAR &&
        !IsOverlapped(p.io, &p.asynchronous)) return nullptr;
    p.owner = &s; p.index = i;
    p.event = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!p.event) return nullptr;
  }
  s.nul = ::CreateFileW(L"NUL", GENERIC_READ | GENERIC_WRITE,
                       FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
                       0, nullptr);
  if (s.nul == INVALID_HANDLE_VALUE) { s.nul = nullptr; return nullptr; }
  for (const auto id : ids) if (!::SetStdHandle(id, s.nul)) return nullptr;
  FILE* unused = nullptr;
  if (freopen_s(&unused, "NUL", "rb", stdin) != 0 ||
      freopen_s(&unused, "NUL", "wb", stdout) != 0 ||
      freopen_s(&unused, "NUL", "wb", stderr) != 0 || !ResetInheritedCrt())
    return nullptr;
  return owner;
}

void McpStdio::Bind(flutter::BinaryMessenger* messenger) {
  auto& s = *state_;
  for (auto& p : s.ports) {
    p.thread = ::CreateThread(nullptr, 0, State::Worker, &p, 0, nullptr);
    if (!p.thread) Fail();
  }
  s.channel = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "serverdeck/mcp_stdio", &flutter::StandardMethodCodec::GetInstance());
  s.channel->SetMethodCallHandler([&s](const auto& call, auto reply) {
    s.Call(call, Reply(std::move(reply)));
  });
}

HANDLE McpStdio::wake_event() const { return state_->wake; }
void McpStdio::Pump() {
  auto& s = *state_;
  std::deque<std::function<void()>> completed;
  {
    std::lock_guard<std::mutex> lock(s.mutex);
    ::ResetEvent(s.wake);
    completed.swap(s.completions);
  }
  for (auto& reply : completed) reply();
  std::lock_guard<std::mutex> lock(s.mutex);
  bool drained = s.closing && s.completions.empty();
  for (auto& p : s.ports) {
    if (p.thread && ::WaitForSingleObject(p.thread, 0) == WAIT_OBJECT_0)
      s.CheckedClose(p.thread);
    if (p.thread || p.pending) drained = false;
  }
  if (drained) { s.watch_stop = true; s.changed.notify_all(); }
  if (s.watch && ::WaitForSingleObject(s.watch, 0) == WAIT_OBJECT_0)
    s.CheckedClose(s.watch);
  if (drained && !s.watch && s.close_reply) {
    const auto reply = std::move(s.close_reply);
    if (s.failed_close) Error(reply);
    else { s.clean_closed = true; reply->Success(Value(true)); }
  }
}

int RunMcpStdio(std::vector<std::string> arguments) {
  ::SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
  const auto carrier = McpStdio::Capture();
  if (!carrier) return EXIT_FAILURE;
  // Fail without a loader dialog or searching the caller's working directory.
  std::array<wchar_t, 32768> image{};
  const auto length = ::GetModuleFileNameW(nullptr, image.data(),
                                          static_cast<DWORD>(image.size()));
  if (length == 0 || length >= image.size()) Fail();
  const std::wstring executable(image.data(), length);
  const auto separator = executable.find_last_of(L"\\/");
  if (separator == std::wstring::npos) Fail();
  const auto library = executable.substr(0, separator + 1) + L"flutter_windows.dll";
  if (!::LoadLibraryExW(library.c_str(), nullptr,
        LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)) Fail();
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(std::move(arguments));
  flutter::FlutterEngine engine(project);
  carrier->Bind(engine.messenger());
  if (!engine.Run()) Fail();
  for (;;) {
    const auto delay = engine.ProcessMessages();
    carrier->Pump();
    MSG message{};
    while (::PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      if (message.message == WM_QUIT) Fail();
      ::TranslateMessage(&message); ::DispatchMessageW(&message);
    }
    const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(delay);
    // Rounding down may wake early; never sleep past Flutter's deadline.
    const DWORD wait = static_cast<DWORD>(std::clamp<int64_t>(ms.count(), 0, 100));
    const HANDLE wake = carrier->wake_event();
    if (::MsgWaitForMultipleObjectsEx(1, &wake, wait, QS_ALLINPUT,
                                     MWMO_INPUTAVAILABLE) == WAIT_FAILED) Fail();
  }
}
