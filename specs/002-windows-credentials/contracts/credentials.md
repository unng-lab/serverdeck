# OsCredentialStore contract

[Spec](../spec.md), [model](../data-model.md).

| Operation | Success | Failure |
| --- | --- | --- |
| read(reference) | SshCredential или null для отсутствующей записи | Invalid reference, unsupported platform, OS error, safe invalid-payload error |
| write(reference, credential) | запись/замена generic credential | Invalid reference, >2560 UTF-8 bytes, unsupported platform, OS error |
| delete(reference) | текущая запись удалена; повторное удаление допустимо | Invalid reference, unsupported platform, OS error |

Системные ошибки содержат операцию и числовой error code. Parse errors не
содержат исходного payload. Read buffer освобождается CredFree; выделенные
FFI buffers освобождаются, write blob очищается перед освобождением.
Managed strings существуют в памяти во время использования доступа.

Неподдерживаемый размер отклоняется до CredWrite и эта операция не меняет credential. При отсутствии других изменений предыдущая запись сохраняется.
Каждая native fixture использует уникальную reference и удаляет её в finally.

Password payload со строковой passphrase отклоняется фиксированным
FormatException; schema по каждому kind задана в model. Поле не удаляется
молча при чтении.

ERROR_NOT_FOUND — единственный системный отказ, означающий допустимое
отсутствие для read/delete. Остальные отказы read/write/delete дают StateError
с операцией и numeric system error code. Отказ read не возвращает null;
отказ write не подтверждает замену; отказ delete не подтверждает удаление.
Отказавшая операция сама не меняет credential и не откатывает изменения другого caller. При отсутствии конкурирующих изменений предыдущий credential сохраняется. Retry и plaintext fallback не выполняются.

Для AC-08..10 используется test-only constructor withNativeApi: он заменяет
только call boundary; reference validation, сериализация, обработка ошибок,
очистка и освобождение buffers остаются в OsCredentialStore. Default constructor
всегда использует Windows API. Injection имитирует ERROR_ACCESS_DENIED, а исходное
и оставшееся значение проверяются настоящим Windows Credential Manager.
## Конкурентный доступ одной reference (FR-006 / AC-11)

Reference общий для текущей Windows account, включая другие экземпляры и
процессы. Конкурентные операции разрешены. Адаптер не добавляет очередь, lock,
revision check или compare-and-swap и не объединяет два credential payload.

- Если A успешно завершилась до начала B, B применяется к состоянию после A.
  Последний успешный write заменяет credential целиком, delete удаляет текущую запись.
- Для перекрывающихся write/write порядок начала, подготовки и Future callbacks
  не определяет победителя. После завершения обеих операций, без новых изменений,
  допустим целый payload любого из двух write; сохранение обоих редактирований не обещано.
- Для перекрывающихся write/delete после завершения обеих операций допустимы
  отсутствие либо целый payload write. Read не гарантирует, что другое изменение
  не произойдёт после полученного значения.
- Delete не создаёт tombstone: подготовленный ранее write, применённый после
  завершения delete, может создать credential снова. Это допустимый успешный write.
- Отказ read/write/delete описывает только этот вызов. Другой процесс может
  успешно изменить reference до, во время или после отказа; старое значение
  гарантируется только при отсутствии таких изменений.

Для AC-01..10 предусловие — нет других изменяющих caller этой reference. Если
вызывающей стороне требуется предотвращение lost update или повторного создания
после delete, она обязана организовать общий порядок/единственного владельца
изменений над этой reference, включая процессы. Адаптер такую гарантию не предоставляет.

AC-11 проверяется двумя настоящими процессами текущей Windows account. Оба
готовят операции до применения; barriers задают оба порядка write/write и
write/delete, а также одновременную отправку разрешения на применение. После
завершения процессов независимый native reader проверяет допустимое целое
значение либо отсутствие. Barriers — тестовый механизм, а не runtime lock.