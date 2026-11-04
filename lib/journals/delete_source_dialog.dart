import 'package:flutter/material.dart';

import '../ui/deck_components.dart';

/// Local confirmation owns only draft/error presentation, not deletion authority.
class DeleteJournalSourceDialog extends StatefulWidget {
  const DeleteJournalSourceDialog({
    super.key,
    required this.name,
    required this.onDelete,
  });
  final String name;
  final Future<void> Function() onDelete;
  @override
  State<DeleteJournalSourceDialog> createState() =>
      _DeleteJournalSourceDialogState();
}

class _DeleteJournalSourceDialogState extends State<DeleteJournalSourceDialog> {
  bool _pending = false;
  String? _error;
  Future<void> _delete() async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await widget.onDelete();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Не удалось удалить источник. Повторите действие.',
        );
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_pending,
    child: DeckDialogLayout(
      title: 'Удалить источник?',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Локальная история «${widget.name}» будет удалена. Файл на сервере сохраняется.',
          ),
          if (_error != null)
            DeckNotice(
              title: 'Удаление не выполнено',
              message: _error!,
              tone: DeckTone.error,
            ),
        ],
      ),
      actions: [
        DeckButton(
          child: const Text('Отмена'),
          onPressed: _pending ? null : () => Navigator.pop(context),
        ),
        DeckButton(
          kind: DeckButtonKind.danger,
          child: const Text('Удалить источник'),
          pending: _pending,
          onPressed: _delete,
        ),
      ],
    ),
  );
}
