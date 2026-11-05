#include "setup_package.h"
#include "install_registration.h"
#include "build_identity.h"
#include "startup_update.h"
#include "uninstall.h"
#include <shellapi.h>

namespace {
std::wstring ErrorText(const std::string& code) {
  if (code == "OWNER_RUNNING" || code == "BUSY") return L"ServerDeck работает или уже обслуживается. Выйдите через меню трея и повторите.";
  if (code == "DISK_SPACE") return L"Недостаточно свободного места. Освободите место и повторите.";
  if (code == "INVALID_ARTIFACT" || code == "INVALID_CATALOG" || code == "SOURCE_UNTRUSTED")
    return L"Установочный файл повреждён или не прошёл проверку. Получите новый полный установщик из доверенного источника.";
  if (code == "RELEASE_INCOMPATIBLE") return L"Выпуск несовместим или установлена более новая версия. Понижение версии не выполняется.";
  if (code == "RECOVERY_REQUIRED") return L"Не удалось подтвердить целый комплект файлов. Используйте «ServerDeck — восстановление» или полный доверенный установщик. Данные не удалены.";
  if (code == "INSTALL_REQUIRED") return L"Удаление запускается через «Установленные приложения» Windows или установленный ServerDeckSetup.exe.";
  return L"Не удалось завершить обслуживание файлов или регистрацию. Проверьте права и свободное место; данные пользователя не удалены.";
}
int RunRemoval(const sd::install::Paths& paths, sd::install::Lease& lease,
    sd::install::Files& files, const std::filesystem::path& image, const sd::install::Package& package) {
  const auto ticket = sd::install::ReadRemovalCache(paths, image, package);
  sd::install::WindowsRegistration registration(paths);
  for (;;) {
    const auto result = sd::install::RemoveInstallation(files, lease, registration, ticket,
      [&] { registration.SetRemovalRetry(ticket.target, image); });
    if (result.complete()) {
      MessageBoxW(nullptr, L"ServerDeck удалён. Пользовательские данные и секреты сохранены.", L"ServerDeck — удаление", MB_OK | MB_ICONINFORMATION); return 0;
    }
    std::wstring message = L"Удаление завершено частично (UNINSTALL_PARTIAL). Не удалось удалить:\n";
    for (const auto& name : result.remaining) message += L"\n" + name;
    message += L"\n\nПользовательские данные сохранены. Можно повторить сейчас или позднее через «Установленные приложения» Windows.";
    if (MessageBoxW(nullptr, message.c_str(), L"ServerDeck — удаление", MB_RETRYCANCEL | MB_ICONERROR) != IDRETRY) return 1;
  }
}
}
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, wchar_t*, int) {
  int count = 0; auto* args = CommandLineToArgvW(GetCommandLineW(), &count); if (!args) return 2;
  const bool install = count == 1;
  const bool repair = count == 2 && std::wstring(args[1]) == L"--repair";
  const bool apply = count == 12 && std::wstring(args[1]) == L"--apply-pending";
  const bool uninstall = count == 2 && std::wstring(args[1]) == L"--uninstall";
  const bool removalRetry = count == 2 && std::wstring(args[1]) == L"--uninstall-retry";
  const bool removalHelper = count == 12 && std::wstring(args[1]) == L"--uninstall-helper";
  std::vector<std::wstring> transferArgs;
  if (apply || removalHelper) for (int i = 2; i < count; ++i) transferArgs.push_back(args[i]);
  LocalFree(args);
  if (!install && !repair && !apply && !uninstall && !removalRetry && !removalHelper) {
    MessageBoxW(nullptr, L"Неизвестная команда установщика.", L"ServerDeck", MB_OK | MB_ICONERROR); return 2;
  }
  try {
    const auto paths = sd::install::Paths::CurrentUser();
    if (removalHelper) {
      auto transfer = sd::install::AcceptTransfer(paths, sd::install::ParseTransfer(transferArgs), sd::install::ValidateRemovalParent);
      const auto image = sd::install::ModuleFile(); sd::install::ReadRemovalTicket(paths, image);
      transfer.Acknowledge(); transfer.AwaitParent();
      sd::install::LoadedSetup loaded(instance, image); sd::install::Files files(paths);
      return RunRemoval(paths, *transfer.lease, files, image, loaded.package());
    }
    if (apply) {
      {
        auto transfer = sd::install::AcceptTransfer(paths, sd::install::ParseTransfer(transferArgs));
        sd::install::Files files(paths);
        // The live canonical parent has already verified complete candidate
        // bytes under these same leases. Keep ACK bounded to handles + metadata;
        // repeat expensive verification only after it has exited, before mutation.
        const auto expected = sd::updates::DecodePending(files.ReadRecord(L"pending/consent.v1"));
        const auto expectedPath = files.Path(sd::updates::PendingPath(expected.slot, L"ServerDeckSetup.exe"));
        if (expected.sid != sd::Utf8(paths.sid) || !sd::install::SameInstallPath(sd::install::ModuleFile(), expectedPath) ||
            sd::updates::EncodePending(sd::updates::DecodePending(files.ReadRecord(sd::updates::PendingPath(expected.slot, L"owner.v1")))) != sd::updates::EncodePending(expected))
          throw sd::updates::Failure("SOURCE_CHANGED");
        transfer.Acknowledge(); transfer.AwaitParent();
        try {
          sd::install::MaintenanceStatus status;
          sd::install::LoadedSetup loaded(instance, sd::install::ModuleFile()); const auto package = loaded.package();
          sd::install::WindowsRegistration registration(paths);
          sd::install::Executor executor(files, *transfer.lease, registration, sd::install::ValidateEmbeddedSetup);
          const auto current = executor.PrepareStartup();
          const auto policy = sd::install::ReadFilePolicy(paths.install / L"ServerDeck.exe");
          if (!policy) throw sd::updates::Failure("UPDATE_NOT_CONFIGURED");
          sd::updates::PendingStore pending(paths, *policy, sd::install::ValidateEmbeddedSetup);
          const auto selected = pending.Read(*transfer.lease);
          if (!selected || sd::updates::EncodePending(selected->consent) != sd::updates::EncodePending(expected) ||
              !loaded.IsFile(files.Path(sd::updates::PendingPath(selected->consent.slot, L"ServerDeckSetup.exe"))))
            throw sd::updates::Failure("SOURCE_CHANGED");
          auto source = sd::updates::MakeWinHttpCatalogSource(*policy, current.version);
          sd::install::ApplySelectedPending(executor, pending, *transfer.lease, selected->consent, package, *policy, *source, {},
            [&](sd::install::MaintenanceStage stage) { status.Report(stage); });
        } catch (const std::exception& error) {
          sd::install::WindowsRegistration registration(paths);
          sd::install::Executor executor(files, *transfer.lease, registration, sd::install::ValidateEmbeddedSetup);
          sd::updates::PendingStore pending(paths, sd::updates::Policy{}, sd::install::ValidateEmbeddedSetup);
          sd::install::ResolvePendingFailure(executor, pending, *transfer.lease, expected, error);
        }
      }
      sd::install::LaunchCanonical(paths); return 0;
    }
    sd::install::LoadedSetup loaded(instance, sd::install::ModuleFile()); const auto package = loaded.package();
    if (install || repair) {
      std::optional<std::filesystem::path> interruptedRemoval;
      {
        sd::install::Lease lease(paths, true); sd::install::Files files(paths);
        interruptedRemoval = sd::install::FindInterruptedRemoval(files, lease, sd::install::ValidateEmbeddedSetup);
      }
      if (interruptedRemoval) { sd::install::LaunchRemovalRetry(paths, *interruptedRemoval); return 0; }
    }
    if (uninstall || removalRetry) {
      if (uninstall && !loaded.IsFile(paths.install / L"ServerDeckSetup.exe")) throw sd::updates::Failure("INSTALL_REQUIRED");
      if (removalRetry) sd::install::ReadRemovalCache(paths, sd::install::ModuleFile(), package);
      if (MessageBoxW(nullptr, L"Удалить ServerDeck для текущего пользователя? Профили серверов, настройки и секреты сохраняются.",
          L"ServerDeck — удаление", MB_OKCANCEL | MB_ICONQUESTION) != IDOK) return 0;
      sd::install::Lease lease(paths, true); sd::install::Files files(paths);
      if (removalRetry) return RunRemoval(paths, lease, files, sd::install::ModuleFile(), package);
      sd::install::WindowsRegistration registration(paths);
      std::filesystem::path helper;
      if (files.Exists(L"journal.v1") && sd::install::DecodeJournal(files.ReadRecord(L"journal.v1")).kind == sd::install::Operation::remove) {
        const auto journal = sd::install::DecodeJournal(files.ReadRecord(L"journal.v1"));
        helper = sd::install::RemovalCacheRoot(paths) / sd::Wide(journal.id) / L"ServerDeckSetup.exe";
        sd::install::ReadRemovalCache(paths, helper, package);
      } else {
        sd::install::Executor executor(files, lease, registration, sd::install::ValidateEmbeddedSetup);
        const auto current = executor.PrepareStartup();
        if (!(current.version == package.version) || current.setup.size != package.setup.size ||
            current.setup.hash != sd::Sha256(package.setup.data, package.setup.size)) throw sd::updates::Failure("RECOVERY_REQUIRED");
        helper = sd::install::PrepareRemovalCache(files, lease, current, package.setup);
      }
      auto process = sd::install::MakeWindowsHandoffPort(); sd::install::StartRemovalHandoff(lease, paths, helper, *process); return 0;
    }
    if (loaded.IsFile(paths.install / L"recovery" / L"ServerDeckSetup.exe")) {
      sd::install::Files files(paths);
      const auto record = sd::install::DecodeRecovery(files.ReadRecord(L"recovery/recovery.v1"));
      if (record.sid != sd::Utf8(paths.sid) || !(record.version == package.version) || record.setup.size != package.setup.size ||
          record.setup.hash != sd::Sha256(package.setup.data, package.setup.size)) throw sd::updates::Failure("RECOVERY_REQUIRED");
    }
    std::wstring existing;
    try {
      sd::install::Files preview(paths);
      if (preview.Exists(L"installation.v1")) {
        const auto current = sd::install::DecodeInstallation(preview.ReadRecord(L"installation.v1"));
        if (current.sid == sd::Utf8(paths.sid)) existing = L"\nОбнаружена установка: " + sd::Wide(current.version.text);
      }
    } catch (...) { existing = L"\nСостояние установки будет проверено перед изменениями."; }
    const auto message = repair ? std::wstring(L"Восстановить файлы и регистрацию ServerDeck? Пользовательские данные сохраняются.") :
      L"Установить ServerDeck " + sd::Wide(package.version.text) + L" для текущего пользователя?\n\n" + paths.install.wstring() +
      existing + L"\n\nБудут созданы ярлыки программы и восстановления в меню «Пуск» и запись удаления. Данные пользователя сохраняются.";
    if (MessageBoxW(nullptr, message.c_str(), L"ServerDeck — установка", MB_OKCANCEL | MB_ICONQUESTION) != IDOK) return 0;
    for (;;) {
      try {
        sd::install::Lease lease(paths, true); sd::install::Files files(paths);
        sd::install::WindowsRegistration registration(paths);
        sd::install::Executor executor(files, lease, registration, sd::install::ValidateEmbeddedSetup);
        if (repair) executor.Repair();
        else executor.Apply(package, true);
        MessageBoxW(nullptr, L"Готово. Запустите ServerDeck из меню «Пуск».", L"ServerDeck", MB_OK | MB_ICONINFORMATION); return 0;
      } catch (const std::exception& error) {
        const auto text = ErrorText(error.what());
        if (MessageBoxW(nullptr, text.c_str(), L"ServerDeck — обслуживание", MB_RETRYCANCEL | MB_ICONERROR) != IDRETRY) return 1;
      }
    }
  } catch (const std::exception& error) {
    const auto text = ErrorText(error.what()); MessageBoxW(nullptr, text.c_str(), L"ServerDeck — установка", MB_OK | MB_ICONERROR); return 1;
  }
}
