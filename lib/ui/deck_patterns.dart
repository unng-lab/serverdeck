import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/brand_theme.dart';
import 'deck_components.dart';

class DeckMenuEntry {
  const DeckMenuEntry(this.label, {this.enabled = true, this.reason});
  final String label;
  final bool enabled;
  final String? reason;
}

/// Native Material menu behavior, reachable by secondary click and Shift+F10.
class DeckContextMenu extends StatefulWidget {
  const DeckContextMenu({
    super.key,
    required this.entries,
    required this.onSelected,
    required this.child,
    this.enabled = true,
  });
  final List<DeckMenuEntry> entries;
  final ValueChanged<String> onSelected;
  final Widget child;
  final bool enabled;
  @override
  State<DeckContextMenu> createState() => _DeckContextMenuState();
}

class _DeckContextMenuState extends State<DeckContextMenu> {
  final _menu = MenuController();
  bool _focused = false;
  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _menu,
    menuChildren: [
      for (final entry in widget.entries)
        MenuItemButton(
          onPressed: widget.enabled && entry.enabled
              ? () => widget.onSelected(entry.label)
              : null,
          child: Text(
            entry.reason == null
                ? entry.label
                : '${entry.label} · ${entry.reason}',
          ),
        ),
    ],
    builder: (context, controller, child) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f10, shift: true): () {
          if (widget.enabled) controller.open();
        },
      },
      child: Focus(
        canRequestFocus: widget.enabled,
        onFocusChange: (value) => setState(() => _focused = value),
        child: GestureDetector(
          onSecondaryTapDown: !widget.enabled
              ? null
              : (details) => controller.open(position: details.localPosition),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: _focused
                    ? Theme.of(context).extension<BrandColors>()!['focus']
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

class DeckBreadcrumbs extends StatelessWidget {
  const DeckBreadcrumbs({
    super.key,
    required this.labels,
    required this.onSelected,
  });
  final List<String> labels;
  final ValueChanged<int>? onSelected;
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) const Text('/'),
        if (i == labels.length - 1)
          Text(labels[i])
        else
          TextButton(
            onPressed: onSelected == null ? null : () => onSelected!(i),
            child: Text(labels[i]),
          ),
      ],
    ],
  );
}

/// A shared list row. Its trailing actions remain independent of row selection.
class DeckListItem extends StatelessWidget {
  const DeckListItem({
    super.key,
    required this.title,
    this.description,
    this.leading,
    this.trailing,
    this.selected = false,
    this.onTap,
    this.compact = false,
    this.error = false,
    this.statusLabel,
  });
  final String title;
  final String? description;
  final Widget? leading, trailing;
  final bool selected;
  final bool compact, error;
  final String? statusLabel;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => DeckSurface(
    selected: selected,
    error: error,
    padding: compact ? const EdgeInsets.all(10) : const EdgeInsets.all(16),
    onTap: onTap,
    semanticLabel: onTap == null ? null : title,
    child: compact
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.labelLarge),
                    if (description != null)
                      Text(
                        description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (statusLabel != null)
                      Text(
                        statusLabel!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: error
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ],
          )
        : LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (leading != null) leading!,
                SizedBox(
                  width: (constraints.maxWidth - (leading == null ? 0 : 40))
                      .clamp(0, 320),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (description != null) Text(description!),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
  );
}

class DeckExpander extends StatelessWidget {
  const DeckExpander({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.childrenPadding = const EdgeInsets.all(16),
    this.tilePadding,
    this.expandedCrossAxisAlignment = CrossAxisAlignment.stretch,
    this.enabled = true,
  });
  final Widget title;
  final Widget? subtitle;
  final List<Widget> children;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final EdgeInsetsGeometry childrenPadding;
  final EdgeInsetsGeometry? tilePadding;
  final CrossAxisAlignment expandedCrossAxisAlignment;
  final bool enabled;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    enabled: enabled,
    title: DeckFocusLabel(child: title),
    subtitle: subtitle,
    initiallyExpanded: initiallyExpanded,
    onExpansionChanged: onExpansionChanged,
    childrenPadding: childrenPadding,
    tilePadding: tilePadding,
    expandedCrossAxisAlignment: expandedCrossAxisAlignment,
    children: children,
  );
}

class DeckTabs extends StatelessWidget {
  const DeckTabs({
    super.key,
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onSelected,
  });
  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int>? onSelected;
  @override
  Widget build(BuildContext context) {
    assert(icons.length == labels.length);
    return DeckActions(
      children: [
        for (var i = 0; i < labels.length; i++)
          Semantics(
            selected: i == selected,
            child: Tooltip(
              message: labels[i],
              excludeFromSemantics: true,
              child: DeckButton(
                kind: i == selected
                    ? DeckButtonKind.primary
                    : DeckButtonKind.text,
                onPressed: onSelected == null ? null : () => onSelected!(i),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(child: Icon(icons[i])),
                    const SizedBox(width: 8),
                    Flexible(child: Text(labels[i])),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class DeckMetric extends StatelessWidget {
  const DeckMetric({
    super.key,
    required this.label,
    this.value,
    this.unit,
    this.contextLabel,
    this.tone = DeckTone.neutral,
    this.compact = false,
    this.icon,
  });
  final String label;
  final String? value, unit, contextLabel;
  final DeckTone tone;
  final bool compact;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => compact && icon != null
      ? Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DeckStatus(
              label:
                  '$label: ${value ?? "Нет данных"}${value == null || unit == null ? "" : " $unit"}${contextLabel == null ? "" : ". $contextLabel"}',
              icon: icon,
              iconOnly: true,
              tone: tone,
            ),
            const SizedBox(width: 6),
            Text(
              value == null ? '—' : '$value${unit == null ? "" : " $unit"}',
              style: TextStyle(
                color: tone == DeckTone.error
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
          ],
        )
      : compact
      ? Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            Text(
              value == null
                  ? 'Нет данных'
                  : '$value${unit == null ? '' : ' $unit'}',
            ),
            if (contextLabel != null)
              DeckStatus(label: contextLabel!, tone: tone),
          ],
        )
      : DeckSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DeckSectionHeader(title: label),
              const SizedBox(height: 8),
              Text(
                value == null
                    ? 'Нет данных'
                    : '$value${unit == null ? '' : ' $unit'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (contextLabel != null)
                DeckStatus(label: contextLabel!, tone: tone),
            ],
          ),
        );
}

class DeckProgressStep {
  const DeckProgressStep(
    this.title, {
    this.description,
    this.tone = DeckTone.neutral,
  });
  final String title;
  final String? description;
  final DeckTone tone;
}

class DeckProgress extends StatelessWidget {
  const DeckProgress({
    super.key,
    required this.label,
    this.value,
    this.steps = const [],
    this.tone = DeckTone.running,
  });
  final String label;
  final double? value;
  final List<DeckProgressStep> steps;
  final DeckTone tone;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DeckStatus(
        label: label,
        tone: tone,
        pending: value == null && tone == DeckTone.running,
      ),
      if (value != null)
        LinearProgressIndicator(
          value: value!.clamp(0, 1),
          semanticsLabel: label,
        ),
      for (final step in steps)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: DeckListItem(
            title: step.title,
            description: step.description,
            trailing: DeckStatus(
              label: switch (step.tone) {
                DeckTone.success => 'Завершено',
                DeckTone.running => 'Выполняется',
                DeckTone.error => 'Ошибка',
                DeckTone.warning => 'Требует внимания',
                DeckTone.unknown => 'Неизвестно',
                DeckTone.unavailable => 'Недоступно',
                DeckTone.available => 'Готово к выполнению',
                DeckTone.neutral => 'Ожидает',
              },
              tone: step.tone,
            ),
          ),
        ),
    ],
  );
}

class DeckPlanSummary extends StatelessWidget {
  const DeckPlanSummary({
    super.key,
    required this.target,
    required this.effects,
    required this.scope,
    required this.deadline,
    this.warning,
    this.details,
    this.actions = const [],
  }) : content = null;
  const DeckPlanSummary.content({super.key, required List<Widget> children})
    : content = children,
      target = '',
      effects = '',
      scope = '',
      deadline = '',
      warning = null,
      details = null,
      actions = const [];
  final String target, effects, scope, deadline;
  final String? warning;
  final Widget? details;
  final List<Widget> actions;
  final List<Widget>? content;
  @override
  Widget build(BuildContext context) => DeckFormSection(
    title: 'Проверьте план',
    children:
        content ??
        [
          DeckKeyValue(label: 'Цель', value: target),
          DeckKeyValue(label: 'Последствия', value: effects),
          DeckKeyValue(label: 'Область действия', value: scope),
          DeckKeyValue(label: 'Действует до', value: deadline),
          if (warning != null) DeckNotice(message: warning!),
          if (details != null)
            DeckExpander(
              title: const Text('Технические сведения'),
              children: [details!],
            ),
          if (actions.isNotEmpty) DeckActions(children: actions),
        ],
  );
}

enum DeckChange { unchanged, added, removed, changed, conflict }

class DeckDifference {
  const DeckDifference({
    required this.label,
    this.before,
    this.after,
    required this.change,
  });
  final String label;
  final String? before, after;
  final DeckChange change;
}

class DeckDiff extends StatelessWidget {
  const DeckDiff({super.key, required this.entries});
  final List<DeckDifference> entries;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final entry in entries)
        DeckSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DeckStatus(
                label:
                    '${entry.label} · ${switch (entry.change) {
                      DeckChange.added => 'Добавлено',
                      DeckChange.removed => 'Удалено',
                      DeckChange.changed => 'Изменено',
                      DeckChange.conflict => 'Конфликт',
                      DeckChange.unchanged => 'Без изменений',
                    }}',
                tone: entry.change == DeckChange.conflict
                    ? DeckTone.warning
                    : DeckTone.neutral,
              ),
              DeckKeyValue(
                label: 'Было',
                value: entry.before ?? 'Нет данных',
                selectable: true,
              ),
              DeckKeyValue(
                label: 'Станет',
                value: entry.after ?? 'Нет данных',
                selectable: true,
              ),
            ],
          ),
        ),
    ],
  );
}

class DeckCode extends StatelessWidget {
  const DeckCode({
    super.key,
    required this.label,
    this.text,
    this.controller,
    this.onChanged,
    this.validator,
    this.error,
    this.readOnly = true,
    this.allowCopy = true,
    this.maxHeight = 240,
    this.enabled = true,
  }) : assert(maxHeight > 0);
  final String label;
  final String? text, error;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool readOnly, allowCopy, enabled;
  final double maxHeight;

  Widget _content(BuildContext context) {
    final value = controller?.text ?? text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckSectionHeader(title: label),
        const SizedBox(height: 8),
        SizedBox(
          height: maxHeight,
          child: readOnly
              ? DeckBoundedTextView(
                  text: value ?? 'Нет данных',
                  style: BrandTypography.log.copyWith(
                    color: Theme.of(
                      context,
                    ).extension<BrandColors>()![enabled ? 'text' : 'disabled'],
                  ),
                )
              : TextFormField(
                  enabled: enabled,
                  controller: controller,
                  initialValue: controller == null ? text : null,
                  onChanged: onChanged,
                  validator: validator,
                  style: BrandTypography.log.copyWith(
                    color: Theme.of(
                      context,
                    ).extension<BrandColors>()![enabled ? 'text' : 'disabled'],
                  ),
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  maxLines: null,
                  expands: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    errorText: error,
                    errorMaxLines: 20,
                  ),
                ),
        ),
        if (readOnly && error != null)
          DeckNotice(message: error!, tone: DeckTone.error),
        if (allowCopy && value != null)
          Align(
            alignment: Alignment.centerLeft,
            child: DeckCopyButton(
              value: value,
              label: 'Скопировать $label',
              enabled: enabled,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => controller == null && !readOnly
      ? _OwnedDeckCode(configuration: this)
      : controller == null
      ? _content(context)
      : ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller!,
          builder: (context, value, child) => _content(context),
        );
}

/// Text-only editable callers get a local controller with the widget lifecycle.
/// An explicit new text replaces that draft; theme/resize rebuilds preserve it.
class _OwnedDeckCode extends StatefulWidget {
  const _OwnedDeckCode({required this.configuration});
  final DeckCode configuration;
  @override
  State<_OwnedDeckCode> createState() => _OwnedDeckCodeState();
}

class _OwnedDeckCodeState extends State<_OwnedDeckCode> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.configuration.text,
  );
  @override
  void didUpdateWidget(covariant _OwnedDeckCode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configuration.text != widget.configuration.text) {
      _controller.text = widget.configuration.text ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.configuration;
    return DeckCode(
      label: value.label,
      controller: _controller,
      onChanged: value.onChanged,
      validator: value.validator,
      error: value.error,
      readOnly: false,
      allowCopy: value.allowCopy,
      maxHeight: value.maxHeight,
      enabled: value.enabled,
    );
  }
}

/// Display values only. Credentials must never be passed to this control.
class DeckCopyButton extends StatefulWidget {
  const DeckCopyButton({
    super.key,
    required this.value,
    this.label = 'Скопировать',
    this.enabled = true,
  });
  final String value, label;
  final bool enabled;
  @override
  State<DeckCopyButton> createState() => _DeckCopyButtonState();
}

class _DeckCopyButtonState extends State<DeckCopyButton> {
  String? _result;
  int _epoch = 0;
  @override
  void didUpdateWidget(covariant DeckCopyButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.label != widget.label ||
        oldWidget.enabled != widget.enabled) {
      _epoch++;
      _result = null;
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DeckButton(
        kind: DeckButtonKind.text,
        onPressed: !widget.enabled
            ? null
            : () async {
                final epoch = ++_epoch;
                try {
                  await Clipboard.setData(ClipboardData(text: widget.value));
                  if (mounted && epoch == _epoch)
                    setState(() => _result = 'Скопировано');
                } on Object {
                  if (mounted && epoch == _epoch)
                    setState(() => _result = 'Не удалось скопировать');
                }
              },
        child: Text(widget.label),
      ),
      if (_result != null) Semantics(liveRegion: true, child: Text(_result!)),
    ],
  );
}

class DeckPathNode {
  const DeckPathNode({
    required this.id,
    required this.label,
    this.children = const [],
    this.available = true,
    this.reason,
  });
  final String id, label;
  final List<DeckPathNode> children;
  final bool available;
  final String? reason;
}

class DeckPathTree extends StatelessWidget {
  const DeckPathTree({
    super.key,
    required this.path,
    required this.nodes,
    required this.expandedIds,
    required this.onExpansionChanged,
    this.selectedId,
    this.onSelected,
    this.enabled = true,
  });
  final List<String> path;
  final List<DeckPathNode> nodes;
  final Set<String> expandedIds;
  final ValueChanged<Set<String>> onExpansionChanged;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String>? onSelected;
  Widget _node(DeckPathNode node) => Column(
    key: ValueKey('deck-node-${node.id}'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DeckListItem(
        title: node.label,
        description: node.reason,
        selected: selectedId == node.id,
        trailing: DeckActions(
          children: [
            if (node.children.isNotEmpty)
              IconButton(
                tooltip: expandedIds.contains(node.id)
                    ? 'Свернуть ${node.label}'
                    : 'Раскрыть ${node.label}',
                onPressed: !enabled || !node.available
                    ? null
                    : () {
                        final next = Set<String>.of(expandedIds);
                        if (!next.remove(node.id)) next.add(node.id);
                        onExpansionChanged(Set.unmodifiable(next));
                      },
                icon: Icon(
                  expandedIds.contains(node.id)
                      ? Icons.expand_less
                      : Icons.expand_more,
                ),
              ),
            if (onSelected != null)
              TextButton(
                onPressed: enabled && node.available
                    ? () => onSelected!(node.id)
                    : null,
                child: const Text('Выбрать'),
              ),
          ],
        ),
      ),
      if (node.available && expandedIds.contains(node.id))
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Column(children: node.children.map(_node).toList()),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [Text(path.join(' / ')), ...nodes.map(_node)],
  );
}

class DeckTimestamp extends StatelessWidget {
  const DeckTimestamp({super.key, required this.label, this.value});
  final String label;
  final DateTime? value;
  @override
  Widget build(BuildContext context) => DeckKeyValue(
    label: label,
    value: value == null
        ? 'Время не указано'
        : '${value!.toUtc().toIso8601String()} · UTC',
  );
}

class DeckCapability extends StatelessWidget {
  const DeckCapability({
    super.key,
    required this.title,
    required this.reason,
    this.tone = DeckTone.unknown,
    this.nextStep,
    this.statusLabel,
  });
  final String title, reason;
  final DeckTone tone;
  final Widget? nextStep;
  final String? statusLabel;
  @override
  Widget build(BuildContext context) => DeckListItem(
    title: title,
    description: reason,
    trailing: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DeckStatus(
          label:
              statusLabel ??
              switch (tone) {
                DeckTone.available || DeckTone.success => 'Доступно',
                DeckTone.unavailable => 'Недоступно',
                DeckTone.unknown => 'Неизвестно',
                DeckTone.warning => 'Ограничено',
                DeckTone.error => 'Заблокировано',
                DeckTone.running => 'Проверяется',
                DeckTone.neutral => 'Сведения',
              },
          tone: tone,
        ),
        if (nextStep != null) nextStep!,
      ],
    ),
  );
}
