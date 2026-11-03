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
  } catch (const std::exception& error) { std::cerr << error.what(); result = 6; }
  std::filesystem::remove_all(root);
  return result;
}
