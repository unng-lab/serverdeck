import 'package:flutter/material.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

import '../theme/brand_assets.dart';
import '../theme/motion.dart';
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
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [const Text('Загрузка локальных профилей')],
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
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
                      builder: (dialog) => Dialog(
                        child: SizedBox(
                          width: 900,
                          height: MediaQuery.sizeOf(dialog).height * .8,
                          child: Column(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: AutomationPanel(
                                    client: controlClient!,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(dialog),
                                child: const Text('Закрыть'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    child: const Text('ИИ-доступ и Ansible-профили'),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: controller.profiles.isEmpty
              ? const Center(child: Text('Локальных профилей пока нет'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: controller.profiles.length,
                  itemBuilder: (context, index) {
                    final profile = controller.profiles[index];
                    return Card(
                      child: ExpansionTile(
                        key: ValueKey(profile.id),
                        title: Text(profile.name),
                        subtitle: Text(
                          '${profile.address}:${profile.port}',
                          style: const TextStyle(
                            fontFamily: BrandAssets.monoFont,
                          ),
                        ),
                        childrenPadding: const EdgeInsets.all(16),
                        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Пользователь SSH: ${profile.sshUser}'),
                          if (profile.tags.isNotEmpty)
                            Text('Метки: ${profile.tags.join(', ')}'),
                          Text(
                            profile.credentialConfigured
                                ? 'Секрет доступа сохранён; содержимое не отображается'
                                : 'Секрет доступа не задан',
                          ),
                          const SizedBox(height: 16),
                          if (controlClient != null)
                            ServerPanel(
                              client: controlClient!,
                              profileId: profile.id,
                            )
                          else
                            const Text('Подключение к серверу пока недоступно'),
                          const SizedBox(height: 16),
                          if (controlClient != null)
                            AutomationPanel(
                              client: controlClient!,
                              serverId: profile.id,
                            ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 48),
                            ),
                            onPressed: () => showMotionDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => ProfileForm(
                                model: controller,
                                initial: profile,
                              ),
                            ),
                            child: const Text('Редактировать профиль'),
                          ),
                          const SizedBox(height: 8),
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
                    );
                  },
                ),
        ),
      ],
    );
  }
}
