# Credential data model

[Spec](spec.md), [contract](contracts/credentials.md).

`SshCredential.password(material)` содержит password; `SshCredential.key(material,
passphrase)` — приватный SSH-ключ и необязательную passphrase. `_secretFields`
сериализует только kind/material/passphrase для системного credential blob.
`toString()` выводит только вид доступа и отметку protected.

Reference: `[a-z0-9_-]{1,80}`. Target: `serverdeck-credential-<reference>`.
Тип Windows credential — generic, persistence — local-machine для сохранения
между сессиями текущей учётной записи. Секретные значения в target не допускаются.

Payload: UTF-8 JSON. Схема зависит от kind:

| kind | material | passphrase |
| --- | --- | --- |
| password | String | поле отсутствует либо null; строка отклоняется |
| key | String | поле отсутствует, null либо String |

Password с непустой или пустой строковой passphrase не нормализуется и не
теряет поле молча: read выдаёт фиксированный FormatException. Constructor
password и writer всегда формируют passphrase=null. Key сохраняет строковое
значение passphrase точно, включая пустую строку.
Лимит адаптера — 2560 bytes включая JSON и многобайтовые символы.
Read отсутствующей записи → null; write заменяет запись; delete удаляет запись.
Некорректное содержимое → фиксированный FormatException без исходных bytes/JSON.

Reference общий для account; два write заменяют весь payload, без слияния полей.
Delete не создаёт tombstone. Порядок и границы гарантий заданы в contract.
