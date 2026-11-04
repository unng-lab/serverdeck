#include "monitoring_run.h"
#include <iostream>

namespace {
void Require(bool value) { if (!value) throw std::runtime_error("unit assertion failed"); }
}
int main() {
  using namespace sd::monitoring;
  wchar_t temp[MAX_PATH]{};
  if (!GetTempPathW(MAX_PATH, temp)) return 1;
  const auto root = std::filesystem::path(temp) / (L"ServerDeckMonitoringUnit-" + sd::Uuid());
  try {
    sd::SecureDirectory(root);
    sd::SecureDirectory(root / L"data");
    auto read = [&] { return Read(root); };
    auto write = [&](const std::string& bytes) { Write(root, bytes); };
    RunState first;
    Require(first.Begin(read, write));
    Require(Read(root) == running);
    Require(first.Begin(read, write)); // Retry must not classify its own running marker.
    RunState afterCrash;
    Require(!afterCrash.Begin(read, write));
    afterCrash.Finish(write);
    Require(Read(root) == clean);
    RunState orderly;
    Require(orderly.Begin(read, write));
    orderly.Finish(write);
    Require(Read(root) == clean);
    for (const auto& invalid : {std::string{}, std::string("{}"), std::string(128, 'x'),
        std::string("{\"version\":2,\"state\":\"clean\"}"), clean + "\n"}) {
      Write(root, invalid);
      RunState corrupted;
      Require(!corrupted.Begin(read, write));
      Require(Read(root) == running);
    }
    Write(root, std::string(129, 'x'));
    RunState oversized;
    Require(!oversized.Begin(read, write));
    Require(Read(root) == running);
    Require(!SafeAttributes(FILE_ATTRIBUTE_REPARSE_POINT));
    Require(!SafeAttributes(FILE_ATTRIBUTE_DIRECTORY));
    Require(!SafeAttributes(INVALID_FILE_ATTRIBUTES));
    Require(SafeAttributes(FILE_ATTRIBUTE_NORMAL));
    {
      RunState io;
      int reads = 0;
      Require(!io.Begin([&]() -> std::optional<std::string> {
        ++reads; throw std::runtime_error("synthetic read failure");
      }, write));
      Require(!io.Begin(read, write));
      Require(reads == 1);
    }
    {
      RunState retry;
      int reads = 0, writes = 0;
      auto missing = [&]() -> std::optional<std::string> { ++reads; return std::nullopt; };
      auto failOnce = [&](const std::string& bytes) {
        ++writes;
        if (writes == 1) throw std::runtime_error("synthetic write failure");
        write(bytes);
      };
      bool failed = false;
      try { retry.Begin(missing, failOnce); } catch (...) { failed = true; }
      Require(failed && reads == 1 && writes == 1);
      Require(retry.Begin(missing, failOnce));
      Require(reads == 1 && writes == 2 && Read(root) == running);
      failed = false;
      try { retry.Finish([](const std::string&) { throw std::runtime_error("finish failure"); }); }
      catch (...) { failed = true; }
      Require(failed && Read(root) == running);
      retry.Finish(write);
      Require(Read(root) == clean);
    }
    // Actual native HANDLE-sharing read failure, not a live application/session.
    Write(root, clean);
    {
      sd::Handle locked(CreateFileW(sd::ExtendedPath(root / L"data/monitoring-run-v1.json").c_str(),
          GENERIC_READ, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
      Require(locked.valid());
      bool failed = false;
      try { Read(root); } catch (...) { failed = true; }
      Require(failed);
    }
    std::filesystem::remove_all(root);
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what();
    return 2;
  }
}
