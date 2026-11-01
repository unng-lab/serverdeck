import 'package:flutter/material.dart';

import '../theme/brand_tokens.dart';
import 'deck_components.dart';

/// Shared presentation slots. Privacy/navigation remain with the hosting owner.
class DeckPageBody extends StatelessWidget {
  const DeckPageBody({
    super.key,
    required this.title,
    required this.child,
    this.target,
    this.status,
    this.focusNode,
    this.contextHeight = 180,
    this.titleKey,
    this.contextKey,
    this.featureKey,
  });
  final String title;
  final String? target;
  final Widget? status;
  final Widget child;
  final FocusNode? focusNode;
  final double contextHeight;
  final Key? titleKey, contextKey, featureKey;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ConstrainedBox(
        key: contextKey,
        constraints: BoxConstraints(maxHeight: contextHeight),
        child: DeckBoundedTextView(
          text: target,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          leading: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  key: titleKey,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (status != null) ...[
                const SizedBox(height: 8),
                status!,
                if (target != null) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
      Expanded(
        child: Focus(
          key: featureKey,
          focusNode: focusNode,
          canRequestFocus: false,
          child: child,
        ),
      ),
    ],
  );
}

class DeckLogMessage extends StatelessWidget {
  const DeckLogMessage({
    super.key,
    required this.message,
    this.source,
    this.eventTime,
    this.observedAt,
    this.height = 200,
  });
  final String message;
  final String? source, eventTime, observedAt;
  final double height;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (source != null) DeckKeyValue(label: 'Источник', value: source!),
      if (eventTime != null)
        DeckKeyValue(label: 'Время события UTC', value: eventTime!),
      if (observedAt != null)
        DeckKeyValue(label: 'Время наблюдения UTC', value: observedAt!),
      SizedBox(
        height: height,
        child: DeckBoundedTextView(
          text: message,
          style: const TextStyle(
            fontFamily: 'Noto Sans Mono',
            fontSize: 13,
            height: 20 / 13,
          ),
        ),
      ),
    ],
  );
}

/// Controlled text values; schedule/DST validation belongs to the feature.
class DeckDateTimeInput extends StatelessWidget {
  const DeckDateTimeInput({
    super.key,
    required this.dateController,
    required this.timeController,
    required this.zone,
    required this.onZoneChanged,
    this.zones = const ['UTC', 'Europe/Moscow'],
    this.dateValidator,
    this.timeValidator,
    this.enabled = true,
  });
  final TextEditingController dateController, timeController;
  final String zone;
  final List<String> zones;
  final ValueChanged<String> onZoneChanged;
  final FormFieldValidator<String>? dateValidator, timeValidator;
  final bool enabled;
  @override
  Widget build(BuildContext context) => DeckFormSection(
    title: 'Дата и время',
    children: [
      DeckTextField(
        label: 'Дата (ГГГГ-ММ-ДД)',
        controller: dateController,
        validator: dateValidator,
        enabled: enabled,
      ),
      DeckTextField(
        label: 'Время (ЧЧ:ММ)',
        controller: timeController,
        validator: timeValidator,
        enabled: enabled,
      ),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: zone,
        decoration: const InputDecoration(labelText: 'Часовой пояс'),
        items: zones
            .map((z) => DropdownMenuItem(value: z, child: Text(z)))
            .toList(),
        onChanged: enabled
            ? (value) {
                if (value != null) onZoneChanged(value);
              }
            : null,
      ),
    ],
  );
}

class DeckLoadMore extends StatelessWidget {
  const DeckLoadMore({
    super.key,
    required this.hasMore,
    required this.onLoad,
    this.pending = false,
  });
  final bool hasMore, pending;
  final VoidCallback onLoad;
  @override
  Widget build(BuildContext context) => DeckButton(
    pending: pending,
    onPressed: hasMore ? onLoad : null,
    child: Text(hasMore ? 'Показать ещё' : 'Показана вся порция'),
  );
}

class DeckSkeleton extends StatelessWidget {
  const DeckSkeleton({super.key, this.lines = 3});
  final int lines;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Загрузка содержимого',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < lines; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const SizedBox(height: BrandGeometry.rowDefault),
            ),
          ),
      ],
    ),
  );
}
