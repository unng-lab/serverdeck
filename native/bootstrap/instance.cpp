#include "instance.h"
#include <sddl.h>
#include <fstream>
#include <sstream>
#include <stdexcept>

namespace sd {
namespace {
uint64_t Creation(HANDLE process) {
  FILETIME created{}, exited{}, kernel{}, user{};
  if (!GetProcessTimes(process, &created, &exited, &kernel, &user)) return 0;
  return (static_cast<uint64_t>(created.dwHighDateTime) << 32) | created.dwLowDateTime;
}
std::wstring ProcessSid(HANDLE process, bool logon) {
  HANDLE raw = nullptr;
  if (!OpenProcessToken(process, TOKEN_QUERY, &raw)) return L"";
  Handle token(raw);
  const auto type = logon ? TokenGroups : TokenUser;
  DWORD size = 0;
  GetTokenInformation(raw, type, nullptr, 0, &size);
  std::vector<uint8_t> bytes(size);
  if (!GetTokenInformation(raw, type, bytes.data(), size, &size)) return L"";
  PSID sid = nullptr;
  if (!logon) sid = reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid;
  else {
    const auto* groups = reinterpret_cast<TOKEN_GROUPS*>(bytes.data());
    for (DWORD i = 0; i < groups->GroupCount; ++i)
      if ((groups->Groups[i].Attributes & SE_GROUP_LOGON_ID) == SE_GROUP_LOGON_ID)
        sid = groups->Groups[i].Sid;
  }
  LPWSTR text = nullptr;
  if (!sid || !ConvertSidToStringSidW(sid, &text)) return L"";
  const std::wstring result(text); LocalFree(text); return result;
}
void ActivateExisting(const std::filesystem::path& root) {
  const auto path = root / L"owner.json";
  RejectReparse(path);
  if (!std::filesystem::exists(path) || std::filesystem::file_size(path) > 8192)
    throw std::runtime_error("OWNER_UNAVAILABLE");
  std::ifstream input(path, std::ios::binary);
  std::string text((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
  std::istringstream fields(text);
  std::string protocol, epoch, pidText, creationText, user, logon, pipe, exe;
  if (!std::getline(fields, protocol) || protocol != "SDOWNER001" ||
      !std::getline(fields, epoch) || !std::getline(fields, pidText) ||
      !std::getline(fields, creationText) || !std::getline(fields, user) ||
      !std::getline(fields, logon) || !std::getline(fields, pipe) ||
      !std::getline(fields, exe) || epoch.size() != 36 ||
      pipe != "\\\\.\\pipe\\ServerDeck.Activation." + epoch || Wide(user) != UserSid())
    throw std::runtime_error("OWNER_UNAVAILABLE");
  if (Wide(logon) != LogonSid()) throw std::runtime_error("OWNER_OTHER_LOGON");
  const auto pidValue = std::stoull(pidText);
  if (pidValue > MAXDWORD) throw std::runtime_error("OWNER_UNAVAILABLE");
  const auto start = GetTickCount64();
  if (!WaitNamedPipeW(Wide(pipe).c_str(), 3000)) throw std::runtime_error("OWNER_UNAVAILABLE");
  Handle connection(CreateFileW(Wide(pipe).c_str(), GENERIC_READ | GENERIC_WRITE,
    0, nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr));
  if (!connection.valid() || !PeerIdentity(connection.get(), true, Wide(user), Wide(logon),
       static_cast<DWORD>(pidValue), std::stoull(creationText)))
    throw std::runtime_error("OWNER_IDENTITY_FAILED");
  DWORD mode = PIPE_READMODE_MESSAGE;
  if (!SetNamedPipeHandleState(connection.get(), &mode, nullptr, nullptr))
    throw std::runtime_error("OWNER_UNAVAILABLE");
  ActivationRequest request{};
  request.version = 1;
  wcscpy_s(request.epoch, Wide(epoch).c_str());
  wcscpy_s(request.requestId, Uuid().c_str());
  ActivationAck ack{};
  Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr));
  OVERLAPPED operation{}; operation.hEvent = event.get();
  DWORD received = 0;
  BOOL ok = TransactNamedPipe(connection.get(), &request, sizeof(request),
                             &ack, sizeof(ack), &received, &operation);
  if (!ok && GetLastError() == ERROR_IO_PENDING) {
    const auto elapsed = GetTickCount64() - start;
    if (elapsed < 3000 && WaitForSingleObject(event.get(), static_cast<DWORD>(3000 - elapsed)) == WAIT_OBJECT_0)
      ok = GetOverlappedResult(connection.get(), &operation, &received, FALSE);
    else {
      CancelIoEx(connection.get(), &operation);
      GetOverlappedResult(connection.get(), &operation, &received, TRUE);
    }
  }
  if (!ok || received != sizeof(ack) || ack.version != 1 || ack.status < 1 || ack.status > 3)
    throw std::runtime_error("OWNER_UNAVAILABLE");
  if (ack.status == 2) MessageBoxW(nullptr, L"Приложение завершает работу", L"ServerDeck", MB_OK | MB_ICONINFORMATION);
}
}
bool PeerIdentity(HANDLE pipe, bool serverPeer, const std::wstring& user,
                  const std::wstring& logon, DWORD expectedPid, uint64_t expectedCreation) {
  ULONG pid = 0;
  if (!(serverPeer ? GetNamedPipeServerProcessId(pipe, &pid) : GetNamedPipeClientProcessId(pipe, &pid))) return false;
  if (expectedPid && pid != expectedPid) return false;
  Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid));
  return process.valid() && (!expectedCreation || Creation(process.get()) == expectedCreation) &&
    ProcessSid(process.get(), false) == user && ProcessSid(process.get(), true) == logon;
}
OwnerLease::~OwnerLease() {
  if (lock && lock->valid()) DeleteFileW((root / L"owner.json").c_str());
}
std::unique_ptr<OwnerLease> AcquireOwner(const std::filesystem::path& root,
                                      const std::filesystem::path& exe) {
  auto owner = std::make_unique<OwnerLease>();
  owner->root = root;
  const auto lockPath = root / L"owner.lock";
  RejectReparse(lockPath);
  owner->lock = std::make_unique<Handle>(CreateFileW(lockPath.c_str(), GENERIC_READ | GENERIC_WRITE | WRITE_DAC,
    0, nullptr, OPEN_ALWAYS, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  if (!owner->lock->valid()) {
    if (GetLastError() != ERROR_SHARING_VIOLATION) throw std::runtime_error("OWNER_LOCK_FAILED");
    ActivateExisting(root);
    return nullptr;
  }
  SecureFileHandle(owner->lock->get());
  owner->epoch = Uuid();
  const auto user = UserSid();
  const auto sidBytes = Utf8(user);
  const auto mutexName = L"Local\\ServerDeck.Owner." + Wide(Sha256(
    reinterpret_cast<const uint8_t*>(sidBytes.data()), sidBytes.size()));
  owner->mutex = std::make_unique<Handle>(CreateMutexW(nullptr, TRUE, mutexName.c_str()));
  if (!owner->mutex->valid()) throw std::runtime_error("OWNER_LOCK_FAILED");
  const auto pipeName = L"\\\\.\\pipe\\ServerDeck.Activation." + owner->epoch;
  const auto sddl = L"D:P(A;;GA;;;" + user + L")(A;;GA;;;SY)";
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1,
      &descriptor, nullptr)) throw std::runtime_error("OWNER_PIPE_FAILED");
  SECURITY_ATTRIBUTES attrs{sizeof(SECURITY_ATTRIBUTES), descriptor, FALSE};
  owner->pipe = std::make_unique<Handle>(CreateNamedPipeW(pipeName.c_str(),
    PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
    PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
    1, sizeof(ActivationAck), sizeof(ActivationRequest), 3000, &attrs));
  LocalFree(descriptor);
  if (!owner->pipe->valid()) throw std::runtime_error("OWNER_PIPE_FAILED");
  std::ostringstream data;
  data << "SDOWNER001\n" << Utf8(owner->epoch) << '\n' << GetCurrentProcessId() << '\n'
       << Creation(GetCurrentProcess()) << '\n' << Utf8(user) << '\n' << Utf8(LogonSid())
       << '\n' << Utf8(pipeName) << '\n' << Utf8(exe.wstring()) << '\n';
  const auto bytes = data.str();
  AtomicFile(root / L"owner.json", std::vector<uint8_t>(bytes.begin(), bytes.end()));
  return owner;
}
}
