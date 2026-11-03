import 'models.dart';

/// Context supplied by the composition root / verified MCP grant owner, never JSON.
sealed class CommandActor {
  const CommandActor._(this._issuer, this.ownerEpoch);
  final Object _issuer;
  final String ownerEpoch;
}

/// Public operations accept only UI or verified MCP context.
sealed class Actor extends CommandActor {
  const Actor._(super.issuer, super.ownerEpoch) : super._();
}

/// App-owned observations/liveness of established sessions, not user commands.
final class OwnerActor extends CommandActor {
  const OwnerActor._(super.issuer, super.ownerEpoch) : super._();
}

final class UiActor extends Actor {
  const UiActor._(super.issuer, super.ownerEpoch) : super._();
}

final class McpActor extends Actor {
  const McpActor._(
    super.issuer,
    super.ownerEpoch,
    this.clientId,
    this.grantVersion, [
    this._cancelled,
  ]) : super._();
  final String clientId;
  final int grantVersion;
  final bool Function()? _cancelled;
  bool get requestCancelled => _cancelled?.call() ?? false;

  /// Attenuates this authenticated context; cannot issue another identity.
  McpActor cancellable(bool Function() cancelled) => McpActor._(
    _issuer,
    ownerEpoch,
    clientId,
    grantVersion,
    () => requestCancelled || cancelled(),
  );
}

/// Keep this capability in the root and grant owner, not in the wire router.
/// Issuing MCP context does not authorize it: every operation checks canonical state.
final class ActorAuthority {
  ActorAuthority(this.ownerEpoch) {
    if (!isCanonicalUuid(ownerEpoch))
      throw ArgumentError('Invalid owner epoch');
  }
  final String ownerEpoch;
  final Object _identity = Object();
  late final UiActor ui = UiActor._(_identity, ownerEpoch);
  late final OwnerActor owner = OwnerActor._(_identity, ownerEpoch);

  McpActor mcp({required String clientId, required int grantVersion}) {
    if (!isCanonicalUuid(clientId) ||
        grantVersion < 1 ||
        grantVersion > 9007199254740991) {
      throw ArgumentError('Invalid grant context');
    }
    return McpActor._(_identity, ownerEpoch, clientId, grantVersion);
  }

  bool owns(CommandActor actor) =>
      identical(actor._issuer, _identity) && actor.ownerEpoch == ownerEpoch;
}
