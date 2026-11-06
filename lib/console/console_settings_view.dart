import 'package:flutter/material.dart';

import '../domain/error_presentation.dart';
import '../ui/deck_components.dart';
import 'console_models.dart';
import 'console_settings.dart';

class ConsoleSettingsView extends StatefulWidget {
  const ConsoleSettingsView({
    super.key,
    required this.owner,
    required this.newId,
  });
  final ConsoleSettingsOwner owner;
  final String Function() newId;
  @override
  State<ConsoleSettingsView> createState() => _ConsoleSettingsViewState();
}

class _ConsoleSettingsViewState extends State<ConsoleSettingsView> {
  List<ConsoleShellProfile> _profiles = [];
  String _defaultId = 'login';
  int _revision = 1;
  String? _error;
  bool _loaded = false, _busy = false, _dirty = false;
  final _routes = <(DialogRoute<ConsoleShellProfile>, NavigatorState)>{};
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      final config = widget.owner.snapshot;
      _profiles = List.of(config.profiles);
      _defaultId = config.defaultId;
      _revision = config.revision;
      _loaded = true;
      _dirty = false;
      _error = null;
    } catch (_) {
      _loaded = false;
      _error =
          'Не удалось прочитать настройки терминала. Данные не были сброшены.';
    }
  }

  void _closeRoutes() {
    final routes = List.of(_routes);
    _routes.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final (route, navigator) in routes) {
        if (route.isActive && navigator.mounted) navigator.removeRoute(route);
      }
    });
  }

  @override
  void didUpdateWidget(ConsoleSettingsView old) {
    super.didUpdateWidget(old);
    if (old.owner != widget.owner) {
      _closeRoutes();
      _busy = false;
      _load();
    }
  }

  Future<void> _edit([ConsoleShellProfile? profile]) async {
    final owner = widget.owner;
    final navigator = Navigator.of(context);
    final profileId = profile?.id ?? widget.newId();
    final route = DialogRoute<ConsoleShellProfile>(
      context: context,
      builder: (_) => _ShellProfileForm(profile: profile, id: profileId),
    );
    _routes.add((route, navigator));
    ConsoleShellProfile? result;
    try {
      result = await navigator.push(route);
    } finally {
      _routes.remove((route, navigator));
    }
    if (!mounted || owner != widget.owner || result == null) return;
    setState(() {
      final index = _profiles.indexWhere((p) => p.id == result!.id);
      if (index < 0) {
        if (_profiles.length >= 16) {
          _error = 'Можно настроить не более 16 профилей.';
          return;
        }
        _profiles.add(result!);
      } else
        _profiles[index] = result!;
      _dirty = true;
      _error = null;
    });
  }

  void _delete(ConsoleShellProfile profile) => setState(() {
    _profiles.removeWhere((p) => p.id == profile.id);
    if (_defaultId == profile.id) _defaultId = 'login';
    _dirty = true;
    _error = null;
  });
  Future<void> _save() async {
    if (_busy || !_loaded) return;
    final owner = widget.owner;
    setState(() => _busy = true);
    final result = await owner.save(
      owner.actors.ui,
      ConsoleConfiguration(
        revision: _revision,
        defaultId: _defaultId,
        profiles: List.of(_profiles),
      ),
      expectedRevision: _revision,
    );
    if (!mounted || owner != widget.owner) return;
    setState(() {
      _busy = false;
      if (result.ok)
        _load();
      else
        _error = OperationPresentation.of(result.error!).message;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Терминал'),
      const Text(
        'Профили удалённых оболочек общие для всех серверов. Выбор используется при открытии новой консоли; работающие сессии не перезапускаются.',
      ),
      if (_error != null) DeckNotice(message: _error!, tone: DeckTone.error),
      if (_loaded) ...[
        DropdownButtonFormField<String>(
          key: ValueKey('terminal-default-$_defaultId'),
          initialValue: _defaultId,
          decoration: const InputDecoration(
            labelText: 'Профиль оболочки по умолчанию',
          ),
          items: [
            for (final p in [ConsoleShellProfile.login, ..._profiles])
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _defaultId = value!;
                  _dirty = true;
                }),
        ),
        const DeckNotice(message: 'Изменения сохраняются кнопкой «Сохранить».'),
        const DeckListItem(
          title: 'Оболочка входа сервера',
          description: 'Использовать оболочку учётной записи сервера',
        ),
        for (final profile in _profiles)
          DeckListItem(
            title: profile.name,
            description: profile.path,
            trailing: DeckActions(
              children: [
                DeckButton(
                  onPressed: _busy ? null : () => _edit(profile),
                  child: const Text('Изменить'),
                ),
                DeckButton(
                  onPressed: _busy ? null : () => _delete(profile),
                  kind: DeckButtonKind.danger,
                  child: const Text('Удалить'),
                ),
              ],
            ),
          ),
        DeckActions(
          children: [
            DeckButton(
              onPressed: _busy || _profiles.length >= 16 ? null : () => _edit(),
              disabledReason: _profiles.length >= 16
                  ? 'Максимум 16 пользовательских профилей.'
                  : null,
              child: const Text('Добавить профиль'),
            ),
            DeckButton(
              onPressed: _busy || !_dirty ? null : _save,
              pending: _busy,
              kind: DeckButtonKind.primary,
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ],
      DeckButton(
        onPressed: _busy ? null : () => setState(_load),
        child: const Text('Перечитать настройки (сбросить черновик)'),
      ),
    ],
  );
  @override
  void dispose() {
    _closeRoutes();
    super.dispose();
  }
}

class _ShellProfileForm extends StatefulWidget {
  const _ShellProfileForm({required this.id, this.profile});
  final String id;
  final ConsoleShellProfile? profile;
  @override
  State<_ShellProfileForm> createState() => _ShellProfileFormState();
}

class _ShellProfileFormState extends State<_ShellProfileForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile?.name ?? '');
  late final _path = TextEditingController(text: widget.profile?.path ?? '');
  @override
  Widget build(BuildContext context) => DeckDialogLayout(
    title: widget.profile == null
        ? 'Добавить профиль оболочки'
        : 'Изменить профиль оболочки',
    child: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DeckTextField(
            label: 'Название',
            controller: _name,
            validator: (value) => ConsoleSettingsCodec.nameError(value ?? ''),
          ),
          DeckTextField(
            label: 'Путь к оболочке на сервере',
            controller: _path,
            validator: (value) => ConsoleSettingsCodec.pathError(value ?? ''),
          ),
        ],
      ),
    ),
    actions: [
      DeckButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      DeckButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(
            context,
            ConsoleShellProfile(
              id: widget.id,
              name: _name.text.trim(),
              path: _path.text,
            ),
          );
        },
        kind: DeckButtonKind.primary,
        child: const Text('Применить к черновику'),
      ),
    ],
  );
  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    super.dispose();
  }
}
