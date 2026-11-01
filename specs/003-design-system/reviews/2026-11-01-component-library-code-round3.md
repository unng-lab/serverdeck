# Независимое ревью реализации 003.4, round 3

Найдено 1 замечание, которое стоит исправить.

Готовность к реализации: готов — новые обязательные решения не нужны.

Готовность реализации к приёмке: не готова — потеря данных в адаптивном HTML.

Reviewer `/root/review_components_code_round3`, `fork_turns="none"`, read-only проверил полный пакет/библиотеку/catalog/tests/adoption/theme/native linkage/HTML/tooling; посторонние изменения исключены. Четыре round2 fixes подтверждены. Полные gates прочитаны из логов, не повторены reviewer.

**P2 C06**: legacy `@container device (max-width:700px)` в style.css скрывает `th/td:nth-child(n+5)`. Reviewer фактически воспроизвёл viewport 1000×800/default frame: preview 724 px, CPU `24 %` display:none, первые четыре ячейки видны. Колонка selection сдвинула CPU на пятое место. Общий overflow gate не выявляет потерю полей. Нарушены FR-CL-04/AC-CL-02: значения колонок не отбрасываются.

Нужно удалить скрытие, проверить видимость каждой ячейки на промежуточной ширине и границах контейнера, пересобрать HTML, повторить применимые gates и fresh review. Native pixel/control-click scope по-прежнему не установлен; это не подменяется widget/UIA/process проверками.
