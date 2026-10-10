# Technical notes: Windows Credential Manager

[Plan](plan.md), [contract](contracts/credentials.md).

Windows generic credentials дают приложению системное хранение паролей и ключей
текущего пользователя. Прямой win32 adapter использует CredWrite, CredRead,
CredDelete и CredFree. Фактический интерфейс проверяется native тестами.

Сериализованный payload ограничен 2560 bytes до системной записи. Unicode
учитывается по UTF-8 bytes. Слишком большой ключ отклоняется явно. Native read
возвращает отдельный buffer, освобождаемый после decode; parse failure использует
фиксированное сообщение. Диагностика не включает material/passphrase.
