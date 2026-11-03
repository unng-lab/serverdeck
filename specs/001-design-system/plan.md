# План 001

Flutter 3.47.7 / Dart 3.13.5. Единственный root package serverdeck. Зависимости: Flutter, flutter_localizations; тесты: flutter_test. Версии resolution закрепляет pubspec.lock. Движок, native плагины и серверные пакеты удалены из активного дерева.

- `lib/theme/`, `assets/brand/`, `docs/brandbook/`: темы, токены, шрифты, графика и брендбук.
- `lib/ui/`: общие элементы; `lib/shell/foundation_shell.dart`: C17. Его ready/unavailable — локальные presentation values, не факт доступности службы.
- `tool/component_catalog.dart` и примеры: Flutter-витрина.
- `docs/design/source/`, `docs/design/components/registry.json`: HTML-витрина компонентов. `tools/build-design-atlas.py` встраивает локальные assets в автономный HTML.
- `tools/generate-component-metadata.py`: компилирует метаданные для Flutter-витрины.
- `test/`: функциональные проверки. `test_design/components/`: отдельная приёмка общих элементов. Съёмка только по opt-in.

Входы, события, варианты и приёмка каждого семейства — [контракт](component-library.md). Владельцы данных, авторизация и runtime будущего приложения определяются отдельно. Каталоги не содержат credentials и реальных подключений.

Среда и проверки: [quickstart](quickstart.md). История прежних задач и страниц сохранена целиком во внешнем архиве из [RESET](../../RESET.md).
