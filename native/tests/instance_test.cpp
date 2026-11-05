#include "instance.h"
#include <thread>
#include <iostream>

int main() {
  wchar_t temp[MAX_PATH]{};
  if (!GetTempPathW(MAX_PATH, temp)) return 1;
  const auto root = std::filesystem::path(temp) / (L"ServerDeckInstanceTest-" + sd::Uuid());
  sd::SecureDirectory(root);
  int result = 0;
  try {
    auto owner = sd::AcquireOwner(root, L"C:\\synthetic\\ServerDeck.exe");
    if (!owner) return 2;
    std::thread peer([&] {
      sd::Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr));
      OVERLAPPED operation{}; operation.hEvent = event.get();
      DWORD transferred = 0;
      BOOL connected = ConnectNamedPipe(owner->pipe->get(), &operation);
      if (!connected && GetLastError() == ERROR_IO_PENDING) {
        if (WaitForSingleObject(event.get(), 5000) == WAIT_OBJECT_0)
          connected = GetOverlappedResult(owner->pipe->get(), &operation, &transferred, FALSE);
        else { CancelIoEx(owner->pipe->get(), &operation);
          GetOverlappedResult(owner->pipe->get(), &operation, &transferred, TRUE); }
      } else if (!connected) connected = GetLastError() == ERROR_PIPE_CONNECTED;
      if (!connected || !sd::PeerIdentity(owner->pipe->get(), false, sd::UserSid(), sd::LogonSid())) return;
      sd::ActivationRequest request{};
      operation = {}; operation.hEvent = event.get(); ResetEvent(event.get());
      BOOL read = ReadFile(owner->pipe->get(), &request, sizeof(request), &transferred, &operation);
      if (!read && GetLastError() == ERROR_IO_PENDING) {
        if (WaitForSingleObject(event.get(), 5000) == WAIT_OBJECT_0)
          read = GetOverlappedResult(owner->pipe->get(), &operation, &transferred, FALSE);
        else { CancelIoEx(owner->pipe->get(), &operation);
          GetOverlappedResult(owner->pipe->get(), &operation, &transferred, TRUE); }
      }
      if (read && transferred == sizeof(request) && request.epoch[36] == 0 &&
          std::wstring(request.epoch) == owner->epoch) {
        const sd::ActivationAck ack{1, 1};
        operation = {}; operation.hEvent = event.get(); ResetEvent(event.get());
        if (!WriteFile(owner->pipe->get(), &ack, sizeof(ack), &transferred, &operation) &&
            GetLastError() == ERROR_IO_PENDING)
          GetOverlappedResult(owner->pipe->get(), &operation, &transferred, TRUE);
      }
      FlushFileBuffers(owner->pipe->get());
      DisconnectNamedPipe(owner->pipe->get());
    });
    try {
      const auto duplicate = sd::AcquireOwner(root, L"D:\\other-copy\\ServerDeck.exe");
      if (duplicate) result = 3;
    } catch (...) { result = 4; }
    peer.join();
    owner.reset();
    auto reopened = sd::AcquireOwner(root, L"C:\\new-path\\ServerDeck.exe");
    if (!reopened) result = 5;
    reopened.reset();
    {
      const auto scenario = root / L"leased-startup"; sd::SecureDirectory(scenario);
      const sd::install::Paths paths{scenario / L"install", scenario / L"data", scenario / L"programs", sd::UserSid()};
      sd::install::Lease maintenance(paths, true);
      const auto original = maintenance.owner();
      if (std::filesystem::exists(paths.data / L"owner.json")) result = 7;
      auto published = sd::AcquireOwnerFromLease(maintenance, paths, paths.install / L"ServerDeck.exe");
      if (!published || published->lock->get() != original || maintenance.owner() != INVALID_HANDLE_VALUE ||
          maintenance.maintenance() == INVALID_HANDLE_VALUE || !std::filesystem::exists(paths.data / L"owner.json")) result = 8;
      maintenance.ReleaseMaintenance();
      bool refused = false;
      try { sd::install::Lease competitor(paths, true, 0); }
      catch (const sd::updates::Failure& error) { refused = std::string(error.what()) == "OWNER_RUNNING"; }
      if (!refused) result = 9;
      published.reset();
      sd::install::Lease afterExit(paths, true, 0);
      if (!afterExit.Owns(paths, true)) result = 10;
      bool invalid = false;
      sd::install::Paths other = paths; other.install = scenario / L"other-install";
      try { sd::AcquireOwnerFromLease(afterExit, other, other.install / L"ServerDeck.exe"); }
      catch (const std::runtime_error&) { invalid = true; }
      if (!invalid || !afterExit.Owns(paths, true)) result = 11;
    }
    {
      const auto scenario = root / L"activation-only"; sd::SecureDirectory(scenario);
      bool rejected = false; try { sd::ActivateOwner(scenario); } catch (const std::exception&) { rejected = true; }
      if (!rejected || std::filesystem::exists(scenario / L"owner.lock") || std::filesystem::exists(scenario / L"owner.json")) result = 12;
      const sd::install::Paths paths{scenario / L"install", scenario / L"data", scenario / L"programs", sd::UserSid()};
      sd::install::Lease onlyMaintenance(paths, false);
      rejected = false;
      try { sd::AcquireOwnerFromLease(onlyMaintenance, paths, paths.install / L"ServerDeck.exe"); }
      catch (const std::exception&) { rejected = true; }
      if (!rejected || !onlyMaintenance.Owns(paths, false) || std::filesystem::exists(paths.data / L"owner.json")) result = 13;
    }
  } catch (const std::exception& error) { std::cerr << error.what(); result = 6; }
  std::filesystem::remove_all(root);
  return result;
}
