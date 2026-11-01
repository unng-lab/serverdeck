# Текущие unit-проверки

По последнему указанию пользователя прежний набор тестов, fixtures, harness и
coverage-конвейер удалены. Исторические метрики не являются текущей приёмкой.
Дизайн, widgets, native/integration и UI automation сейчас не тестируются.

Для текущей задачи выполняется `./tools/test-unit.ps1`: обязательные format и
Flutter analysis, полный root unit suite, analysis всех Dart packages и полные
имеющиеся новые package unit suites. Отсутствие тестов у пакета явно сообщается,
не засчитывается как успешный test run. CI использует тот же runner.

Новые unit tests проверяют режим запуска, строгий schema3 manifest, MCP credential
custody и полномочия host через in-memory providers. Они не доказывают работу
Windows DPAPI, tray, Isar, stdio runner или SSH. Общая реализация ещё продолжается.
