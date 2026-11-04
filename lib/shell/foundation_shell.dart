import 'package:flutter/material.dart';

import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';
import '../ui/deck_components.dart';

enum ReadinessState { ready, unavailable }

/// C17: the host supplies server navigation and the current workspace.
class FoundationShell extends StatelessWidget {
  const FoundationShell({
    super.key,
    required this.state,
    required this.sidebar,
    required this.child,
    this.status,
    this.recoveryAction,
    this.onRetry,
    this.retryInProgress = false,
  });
  final ReadinessState state;
  final Widget sidebar, child;
  final Widget? status, recoveryAction;
  final VoidCallback? onRetry;
  final bool retryInProgress;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final colors = Theme.of(context).extension<BrandColors>()!;
          final width = constraints.maxWidth < 700
              ? constraints.maxWidth * .34
              : 244.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('foundation-sidebar'),
                width: width,
                child: ColoredBox(
                  color: colors['surface'],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Image.asset(
                            BrandAssets.logo(Theme.of(context).brightness),
                            height: 32,
                            semanticLabel: 'ServerDeck',
                          ),
                        ),
                        Expanded(
                          child: state == ReadinessState.ready
                              ? sidebar
                              : const SizedBox.shrink(),
                        ),
                        if (status != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: status!,
                          ),
                        if (recoveryAction != null) recoveryAction!,
                      ],
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                key: const ValueKey('foundation-feature-slot'),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: state == ReadinessState.ready
                      ? child
                      : DeckCollectionState(
                          state: DeckDataState.unavailable,
                          onRetry: retryInProgress ? null : onRetry,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
