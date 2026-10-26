import 'package:flutter/material.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

import '../theme/brand_assets.dart';
import '../theme/brand_tokens.dart';
import '../theme/motion.dart';
import '../ui/deck_components.dart';
import '../shell/error_view.dart';
import 'profile_controller.dart';
import 'profile_form.dart';
import 'profile_delete.dart';
import '../servers/server_panel.dart';
import '../automation/automation_panel.dart';

class ProfileList extends StatelessWidget {
  const ProfileList({super.key, required this.controller, this.controlClient});
  final ProfileController controller;
  final TrustedApiClient? controlClient;
  @override
  Widget build(BuildContext context) {
    if (!controller.loaded) {
      final error = controller.error;
      if (error != null) {
        return ReadErrorView(
          code: error,
          onReadAgain: () => controller.refresh().ignore(),
          onCheckService: () => controller.bootstrap.retry().ignore(),
        );
      }
      return const Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(BrandSpacing.space24),
          child: DeckStatus(
            label: 'Загрузка локальных профилей',
            pending: true,
          ),
        ),
      );
    }
    final empty = controller.profiles.isEmpty;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: BrandSpacing.space16),
      itemCount: controller.profiles.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: BrandSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DeckSectionHeader(
                  title: empty
                      ? 'Добро пожаловать в ServerDeck'
                      : 'Локальные профили',
                  description: empty
                      ? 'Создайте профиль, чтобы сохранить адрес и параметры доступа к серверу.'
                      : 'Адреса и параметры доступа хранятся в локальном пространстве. Откройте профиль для доступных действий.',
                ),
                const SizedBox(height: BrandSpacing.space16),
                DeckActions(
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => showMotionDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => ProfileForm(model: controller),
                      ),
                      child: const Text('Создать профиль'),
                    ),
                    if (controlClient != null)
                      OutlinedButton(
                        onPressed: () => showMotionDialog<void>(
                          context: context,
                          builder: (dialog) => DeckDialogLayout(
                            title: 'ИИ-доступ и Ansible-профили',
                            maxWidth: 900,
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialog),
                                child: const Text('Закрыть'),
                              ),
                            ],
                            child: ListenableBuilder(
                              listenable: controller,
                              builder: (context, _) => AutomationPanel(
                                client: controlClient!,
                                serverProfiles: controller.loaded
                                    ? controller.profiles
                                    : const [],
                              ),
                            ),
                          ),
                        ),
                        child: const Text('ИИ-доступ и Ansible-профили'),
                      ),
                  ],
                ),
                if (empty) ...[
                  const SizedBox(height: BrandSpacing.space24),
                  const DeckNotice(
                    message: 'Локальных профилей пока нет',
                    tone: DeckTone.neutral,
                    nextStep: 'Создание профиля сохраняет параметры. Подключение выполняется отдельным действием.',
                  ),
                ],
              ],
            ),
          );
        }
        final profile = controller.profiles[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: BrandSpacing.space12),
          child: DeckSurface(
            selected: controller.selected?.id == profile.id,
            padding: EdgeInsets.zero,
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(BrandGeometry.radiusCard),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                key: ValueKey(profile.id),
                title: DeckFocusLabel(child: Text(profile.name)),
                subtitle: Text(
                  profile.address.contains(':')
                      ? '[${profile.address}]:${profile.port}'
                      : '${profile.address}:${profile.port}',
                  style: const TextStyle(fontFamily: BrandAssets.monoFont),
                ),
                childrenPadding: const EdgeInsets.all(BrandSpacing.space16),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Пользователь SSH: ${profile.sshUser}'),
                  if (profile.tags.isNotEmpty) ...[
                    const SizedBox(height: BrandSpacing.space8),
                    Text('Метки: ${profile.tags.join(', ')}'),
                  ],
                  const SizedBox(height: BrandSpacing.space8),
                  DeckStatus(
                    label: profile.credentialConfigured
                        ? 'Секрет доступа сохранён; содержимое не отображается'
                        : 'Секрет доступа не задан',
                  ),
                  const SizedBox(height: BrandSpacing.space16),
                  if (controlClient != null)
                    ServerPanel(client: controlClient!, profile: profile)
                  else
                    const DeckNotice(
                      message: 'Подключение к серверу пока недоступно',
                      tone: DeckTone.neutral,
                      nextStep:
                          'Локальный профиль можно редактировать и удалить.',
                    ),
                  const SizedBox(height: BrandSpacing.space16),
                  if (controlClient != null) ...[
                    AutomationPanel(
                      client: controlClient!,
                      serverId: profile.id,
                      serverProfiles: controller.profiles,
                    ),
                    const SizedBox(height: BrandSpacing.space16),
                  ],
                  DeckActions(
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () => showMotionDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) =>
                              ProfileForm(model: controller, initial: profile),
                        ),
                        child: const Text('Редактировать профиль'),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () => showMotionDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => ProfileDelete(
                            model: controller,
                            initial: profile,
                          ),
                        ),
                        child: const Text('Удалить профиль'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
