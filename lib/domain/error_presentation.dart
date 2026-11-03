import 'models.dart';

/// Fixed public text only. Never interpolate input, native errors or credentials.
final class OperationPresentation {
  const OperationPresentation(this.message, this.nextStep);
  final String message, nextStep;
  static OperationPresentation of(OperationFailure error) {
    if (error.code == FailureCode.storageUnavailable &&
        error.field == OperationField.authentication)
      return const OperationPresentation(
        'Не удалось прочитать файл ключа.',
        'Выберите доступный файл ключа или восстановите права чтения и повторите выбор. Сохранённый профиль не изменён.',
      );
    if (error.reason == FailureReason.clockRollback)
      return const OperationPresentation(
        'Доступ клиента отключён после перевода часов Windows назад.',
        'Обновите разрешение клиента в настройках MCP.',
      );
    if (error.reason == FailureReason.grantCleanup)
      return const OperationPresentation(
        'Закрытие прежних каналов клиента ещё не подтверждено.',
        'Нажмите «Повторить закрытие и сохранение» в настройках MCP.',
      );
    return switch (error.code) {
      FailureCode.invalidArgument => OperationPresentation(
        'Некорректное значение${error.field == null ? '' : ': ${field(error.field!)}'}.',
        'Исправьте указанное поле и повторите действие.',
      ),
      FailureCode.profileNotFound => const OperationPresentation(
        'Профиль уже удалён.',
        'Обновите список и выберите существующий профиль.',
      ),
      FailureCode.conflict => const OperationPresentation(
        'Данные или подтверждение уже изменились.',
        'Обновите профиль. Для доверия или passphrase используйте новый запрос.',
      ),
      FailureCode.authRequired => const OperationPresentation(
        'Авторизация MCP не подтверждена.',
        'Проверьте разрешение и заново подключите MCP-клиент.',
      ),
      FailureCode.accessRevoked => const OperationPresentation(
        'Доступ клиента отключён или заменён.',
        'Проверьте разрешение в настройках MCP и подключите клиент заново.',
      ),
      FailureCode.grantExpired => const OperationPresentation(
        'Срок разрешения MCP истёк.',
        'Обновите разрешение клиента в настройках MCP.',
      ),
      FailureCode.trustRequired => const OperationPresentation(
        'Ключ сервера ещё не принят.',
        'Сверьте показанный отпечаток с доверенным источником и подтвердите его либо отмените подключение.',
      ),
      FailureCode.hostKeyChanged => const OperationPresentation(
        'Ключ сервера отличается от доверенного.',
        'Сверьте старый и новый отпечатки. Для нового решения повторите подключение и подтвердите точный ключ.',
      ),
      FailureCode.authFailed => const OperationPresentation(
        'Сервер отклонил вход.',
        'Проверьте пользователя и выбранные учётные данные в профиле, затем подключитесь снова.',
      ),
      FailureCode.passphraseRequired => const OperationPresentation(
        'Для зашифрованного ключа нужна passphrase.',
        'Введите passphrase в текущем запросе. Она не будет сохранена.',
      ),
      FailureCode.passphraseInvalid => const OperationPresentation(
        'Passphrase не подошла к приватному ключу.',
        'Введите корректную passphrase; если попытка завершена, начните новое подключение.',
      ),
      FailureCode.unsupportedKey => const OperationPresentation(
        'Формат или тип ключа не поддерживается.',
        'Выберите приватный ключ OpenSSH Ed25519 либо RSA не менее 2048 бит, размером до 1 МиБ.',
      ),
      FailureCode.unsupportedServer => const OperationPresentation(
        'Сервер не поддерживает разрешённые SSH-алгоритмы или выбранный способ входа.',
        'Проверьте совместимость SSH-сервера и выбранные учётные данные. Скрытого перехода на другой способ входа нет.',
      ),
      FailureCode.networkError => const OperationPresentation(
        'Соединение с сервером потеряно или недоступно.',
        'Проверьте адрес, порт и сеть, затем явно повторите подключение.',
      ),
      FailureCode.timeout => const OperationPresentation(
        'Время ожидания подключения или ввода истекло.',
        'Начните новое подключение и используйте его актуальный запрос подтверждения.',
      ),
      FailureCode.storageUnavailable => const OperationPresentation(
        'Не удалось прочитать или сохранить локальные данные.',
        'Повторите чтение или сохранение. Существующие данные не заменяются пустым списком.',
      ),
      FailureCode.protectionUnavailable => const OperationPresentation(
        'Windows не смогла защитить учётные данные.',
        'Проверьте доступность текущей учётной записи Windows и повторите сохранение. Открытого хранения нет.',
      ),
      FailureCode.shuttingDown => const OperationPresentation(
        'Приложение завершает работу.',
        'Дождитесь завершения. Если выход приостановлен, повторите «Выход» в меню трея.',
      ),
      FailureCode.resourceExhausted => const OperationPresentation(
        'Достигнут допустимый предел ресурсов.',
        'Закройте ненужные подключения или клиенты и повторите действие.',
      ),
      FailureCode.cleanupRequired => const OperationPresentation(
        'Закрытие прежнего подключения ещё не подтверждено.',
        'Повторите «Отключиться» или «Отменить подключение» у профиля с незавершённым закрытием. Для MCP используйте повтор закрытия в настройках.',
      ),
    };
  }

  static String field(OperationField value) => switch (value) {
    OperationField.displayName => 'название',
    OperationField.host => 'хост',
    OperationField.port => 'порт',
    OperationField.username => 'пользователь',
    OperationField.authentication => 'учётные данные',
    OperationField.passphrase => 'passphrase',
    OperationField.profileId => 'профиль',
    OperationField.clientId => 'клиент',
    OperationField.limit => 'число записей',
    OperationField.cursor => 'позиция списка',
    OperationField.expectedRevision => 'версия профиля',
    OperationField.mutationId => 'идентификатор изменения',
    OperationField.attemptId => 'попытка подключения',
    OperationField.sessionId => 'сеанс',
    OperationField.nonce => 'подтверждение',
    OperationField.fingerprint => 'отпечаток',
    OperationField.oldFingerprint => 'прежний отпечаток',
    OperationField.newFingerprint => 'новый отпечаток',
    OperationField.acceptedFingerprint => 'доверенный отпечаток',
    OperationField.request => 'запрос',
  };
}
