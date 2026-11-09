import '../domain/models.dart';

/// Copyable task for an external AI client; this function performs no I/O.
String softwareAnalysisPrompt(ProfileView profile, String requestedSoftware) =>
    '''
Обследуй установленное ПО на сервере ${profile.host}:${profile.port}, пользователь ${profile.username}.
Профиль ServerDeck: ${profile.profileId}.
Используй существующее SSH-подключение и общую консоль console.* через MCP.
Интересующее ПО: ${requestedSoftware.trim().isEmpty ? 'установленное ПО, которое удастся обнаружить' : requestedSoftware.trim()}.
Предложи карточки: название, версия, служба, пути данных и конфигов.
Различай отдельные экземпляры. Неизвестные версия/служба — null, пути — пустые списки.
Обсуди найденные карточки со мной. После согласования сохрани их обычным software.save.
Карточка — локальный учёт. Не устанавливай и не изменяй ПО в ходе обследования.
Не включай пароли, токены или содержимое конфигов в карточки и сообщения истории.
'''
        .trim();
