# Запуск и проверки

Flutter 3.47.7 (Dart 3.13.5), Python 3.12+, lychee должны быть доступны в PATH. Рабочий каталог — корень репозитория.

```powershell
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter test test_design/components
./tools/check-test-boundaries.ps1
lychee "specs/**/*.md"
python tools/generate-component-metadata.py
dart format tool/component_catalog/names.dart
python tools/build-design-atlas.py
```

Flutter-каталог: `flutter run -d windows -t tool/component_catalog.dart` после генерации стандартного runner командой `flutter create --platforms=windows .`. Runner прежнего приложения вынесен в архив. HTML: открыть `docs/design/ServerDeck-design.html`, сеть не нужна.

HTML-проверки: Node.js и Playwright с установленным Edge. Путь модуля задаётся PLAYWRIGHT_PATH. Команды: `node tools/test-component-interactions.cjs` и `node tools/test-design-components.cjs`. Проверяются только C01–C30. Flutter capture остаётся opt-in через COMPONENT_CAPTURE_DIR.

Снимки HTML создаются только при явном `node tools/test-design-components.cjs --capture`.
