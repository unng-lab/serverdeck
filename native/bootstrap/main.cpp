#include "serverdeck_host.h"
#include "security.h"
#include "payload.h"
#include "instance.h"
#include "mcp_pipe.h"
#include "build_identity.h"
#include "startup_update.h"
#include "install_registration.h"
#include "setup_package.h"
#include <shellapi.h>
#include <cstdio>
#include <stdexcept>

namespace {
std::wstring StartupMessage(const std::string& code) {
  if (code == "INSTALL_REQUIRED") return L"Установите ServerDeck полным ServerDeckSetup.exe. Запуск отдельной копии программы вне каталога установки не поддерживается.";
  if (code == "BUSY") return L"Установка обслуживается другим процессом. Дождитесь завершения и повторите запуск.";
  if (code == "RECOVERY_REQUIRED" || code == "UNINSTALL_PARTIAL" || code == "INVALID_ARTIFACT")
    return L"Не удалось подтвердить целую установку. Используйте «ServerDeck — восстановление» или полный доверенный установщик. Данные не удалены.";
  if (code == "OWNER_OTHER_LOGON") return L"Приложение работает в другой сессии Windows. Завершите его в той сессии и повторите запуск.";
  if (code.rfind("OWNER_", 0) == 0) return L"Приложение уже запущено, но недоступно для активации. Дождитесь завершения запуска или выхода и повторите попытку.";
  if (code == "INSUFFICIENT_DISK_SPACE") return L"Недостаточно свободного места для запуска. Освободите место в пользовательском каталоге и повторите попытку.";
  if (code.rfind("HOST_", 0) == 0) return L"Не удалось запустить интерфейс приложения. Повторите запуск.";
  if (code.rfind("PAYLOAD_", 0) == 0 || code == "INVALID_PAYLOAD" || code == "EXTRACTION_FAILED")
    return L"Не удалось подготовить файлы приложения. Проверьте свободное место и доступ к пользовательскому каталогу, затем повторите попытку.";
  return L"Не удалось открыть защищённые файлы приложения. Проверьте доступ к пользовательскому каталогу и повторите попытку.";
}
bool CanonicalUuid(const std::wstring& value) {
  if (value.size() != 36 || value[14] != L'4' ||
      std::wstring(L"89ab").find(value[19]) == std::wstring::npos) return false;
  for (size_t i = 0; i < value.size(); ++i) {
    if (i == 8 || i == 13 || i == 18 || i == 23) { if (value[i] != L'-') return false; }
    else if (!((value[i] >= L'0' && value[i] <= L'9') || (value[i] >= L'a' && value[i] <= L'f'))) return false;
  }
  return true;
}
}
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, wchar_t*, int) {
  int count = 0;
  auto args = CommandLineToArgvW(GetCommandLineW(), &count);
  if (!args) return 2;
  const bool gui = count == 1;
  const bool bridge = count == 4 && std::wstring(args[1]) == L"--mcp-stdio" &&
      std::wstring(args[2]) == L"--client" && CanonicalUuid(args[3]);
  const auto clientId = bridge ? sd::Utf8(args[3]) : std::string();
  LocalFree(args);
  if (bridge) {
    return sd::mcp::RunStdio(clientId);
  }
  if (!gui) return 2;
  sd::install::StartupInvocation invocation;
  for (;;) {
    try {
      std::wstring exe(32768, L'\0');
      const DWORD length = GetModuleFileNameW(nullptr, exe.data(), static_cast<DWORD>(exe.size()));
      if (!length || length >= exe.size()) throw std::runtime_error("EXE_PATH_FAILED");
      exe.resize(length);
      const auto paths = sd::install::Paths::CurrentUser(); const auto root = paths.data;
      if (!sd::install::SameInstallPath(exe, paths.install / L"ServerDeck.exe")) throw std::runtime_error("INSTALL_REQUIRED");
      std::unique_ptr<sd::install::Lease> lease;
      try { lease = std::make_unique<sd::install::Lease>(paths, true); }
      catch (const sd::updates::Failure& error) {
        if (std::string(error.what()) != "OWNER_RUNNING") throw;
        sd::ActivateOwner(root); return 0;
      }
      sd::install::Files files(paths); sd::install::WindowsRegistration registration(paths);
      sd::install::Executor executor(files, *lease, registration, sd::install::ValidateEmbeddedSetup);
      const auto policy = sd::install::ReadEmbeddedPolicy(instance);
      sd::updates::PendingStore pending(paths, policy.value_or(sd::updates::Policy{}), sd::install::ValidateEmbeddedSetup);
      auto process = sd::install::MakeWindowsHandoffPort();
      const auto mappedVersion = sd::install::ReadBuildVersion(instance);
      const auto action = sd::install::PrepareGuiStartup(executor, pending, *lease, paths, mappedVersion, invocation, *process, policy.has_value());
      if (action == sd::install::StartupAction::handedOff) return 0;
      if (action == sd::install::StartupAction::relaunch) {
        const auto current = executor.Current();
        if (!current || !(sd::install::ReadFileBuildVersion(paths.install / L"ServerDeck.exe") == current->version))
          throw sd::updates::Failure("RECOVERY_REQUIRED");
        lease.reset(); sd::install::LaunchCanonical(paths); return 0;
      }
      auto owner = sd::AcquireOwnerFromLease(*lease, paths, exe); lease->ReleaseMaintenance();
      sd::SecureTree(root);
      HRSRC resource = FindResourceW(instance, L"SERVERDECK_PAYLOAD_V1", RT_RCDATA);
      if (!resource) throw std::runtime_error("PAYLOAD_MISSING");
      HGLOBAL loaded = LoadResource(instance, resource);
      const auto* bytes = static_cast<const uint8_t*>(LockResource(loaded));
      if (!bytes) throw std::runtime_error("PAYLOAD_MISSING");
      const auto payload = sd::ParsePayload(bytes, SizeofResource(instance, resource));
      const auto runtime = sd::ExtractPayload(payload, root);
      if (!SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32 | LOAD_LIBRARY_SEARCH_USER_DIRS))
        throw std::runtime_error("DLL_SEARCH_FAILED");
      const auto cookie = AddDllDirectory(runtime.c_str());
      if (!cookie) throw std::runtime_error("DLL_SEARCH_FAILED");
      const HMODULE host = LoadLibraryExW((runtime / L"serverdeck_host.dll").c_str(), nullptr,
        LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32 | LOAD_LIBRARY_SEARCH_USER_DIRS);
      if (!host) { RemoveDllDirectory(cookie); throw std::runtime_error("HOST_LOAD_FAILED"); }
      const auto run = reinterpret_cast<ServerDeckRunMainV1Fn>(GetProcAddress(host, "ServerDeckRunMainV1"));
      if (!run) { FreeLibrary(host); RemoveDllDirectory(cookie); throw std::runtime_error("HOST_ABI_FAILED"); }
      const auto runtimeText = runtime.wstring();
      const auto rootText = root.wstring();
      const ServerDeckHostArgsV1 hostArgs{sizeof(ServerDeckHostArgsV1), 1,
        runtimeText.c_str(), rootText.c_str(), exe.c_str(), owner->epoch.c_str(),
        owner->mutex->get(), owner->pipe->get(), 0};
      const int result = run(&hostArgs);
      FreeLibrary(host);
      RemoveDllDirectory(cookie);
      const auto outcome = ServerDeckClassifyHostResultV1(result);
      if (outcome == ServerDeckHostDisposition::updateRestart) {
        // The old Flutter host is gone. Keep owner.lock continuously held while
        // reacquiring maintenance and handing it to the existing pending helper.
        // This branch must never fall through to the normal startup/host retry.
        std::unique_ptr<sd::install::Lease> restartLease;
        for (;;) {
          try {
            if (!restartLease) restartLease = sd::install::Lease::Resume(paths, owner->lock);
            owner.reset();
            sd::install::Executor restartExecutor(files, *restartLease, registration, sd::install::ValidateEmbeddedSetup);
            sd::install::PrepareUpdateRestart(restartExecutor, pending, *restartLease, paths, mappedVersion, *process);
            return 0;
          } catch (const std::exception& error) {
            const auto message = L"Не удалось начать обновление после сохранения данных. "
              L"Повторите попытку или отмените и запустите ServerDeck позже.\n\n" + StartupMessage(error.what());
            if (MessageBoxW(nullptr, message.c_str(), L"ServerDeck — обновление", MB_RETRYCANCEL | MB_ICONERROR) != IDRETRY) return 1;
          }
        }
      }
      if (outcome == ServerDeckHostDisposition::startupFailure) {
        // Throw only after unloading the failed host. Owner handles unwind
        // before the outer native retry/cancel UI is presented.
        throw std::runtime_error("HOST_START_FAILED:" + std::to_string(result));
      }
      if (outcome == ServerDeckHostDisposition::runtimeFailure) {
        MessageBoxW(nullptr, L"Приложение завершилось с ошибкой. Повторный запуск возможен после закрытия этого сообщения.",
                    L"ServerDeck", MB_OK | MB_ICONERROR);
      }
      return result;
    } catch (const std::exception& error) {
      const auto message = StartupMessage(error.what());
      if (MessageBoxW(nullptr, message.c_str(), L"ServerDeck — ошибка запуска",
            MB_RETRYCANCEL | MB_ICONERROR) != IDRETRY) return 1;
    }
  }
}
