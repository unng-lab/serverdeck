# Текущий поток профилей и доверия

Действующая навигация определена [server workspace](server-workspace.md).
Утверждение пользователем2026-11-04 заменяет подробности в C12 на правую область
выбранного сервера. C12 остаётся для ProfileForm, consent, passphrase и delete.

ProfileSaveOutcome содержит profileId и requiresConnection только после commit.
Новый/connection-affecting save запускает manual verification, name-only — нет.
First/replace/retain и phrase автоматически предлагаются только внутри своего
onboarding. Актуальный trust challenge рассматривается прежде terminal connected/
failed состояния; connected retain тоже требует актуального явного решения.
Нормальная навигация и background monitoring не открывают prompts.

Route-owned phrase controller очищается на submit/cancel/dispose и живёт до unmount.
Один prompt одновременно, ledger latest64 profile/attempt/nonce tokens. Actor,
revision и nonce backend fences остаются обязательными; никакого autoaccept.

VerificationLease переживает retired workspace до late admission: callback exact
attempt до refresh; cleanup не блокируется UI pending и никогда не отменяет новую
попытку/готовый SSH. Navigation generation/controller/profile checks до и после
save refresh не позволяют late A перенести prompts или selection на B. Выбор
другого сервера, deletion, global settings/controller change/dispose retire session.

Current-only APIs обновляются напрямую; старые constructors/aliases не сохраняются.
Поддержка двух пользовательских input formats не разрешает app-version BC.
