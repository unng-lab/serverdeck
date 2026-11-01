part of 'router.dart';

/// Fixed typed bindings. Wire inputs cannot create a router context or authority.

final class TrustedMcpRouter extends _McpRouter {
  TrustedMcpRouter({
    required this.sessions,
    required this.authority,
    required this.services,
    super.elapsed,
  }) : super(
         onDetach: sessions.onSessionDetached,
         onGrant: authority.onGrantPublished,
       );
  final EngineSessions sessions;
  final TrustedMcpAuthority authority;
  final TrustedMcpToolServices services;
  static const workspaceLimit = _McpRouter.workspaceLimit;
  static const sessionLimit = _McpRouter.sessionLimit;
  static const operationLifetime = _McpRouter.operationLifetime;
  static const completionLifetime = _McpRouter.completionLifetime;
  Future<McpInvokeReply> invoke(SessionRequest request, Object? params) =>
      _invoke(_RouterRequest.capture(request, this), params);
}

abstract interface class TrustedMcpToolServices {
  McpServiceOperation start(
    TrustedMcpContext context,
    McpToolDefinition tool,
    Map<String, Object?> arguments,
  );
}

final class _RouterRequest {
  _RouterRequest._(
    this.requireBinding,
    this.mcpContextWhenStable,
    this._budget,
    this._remaining,
    this.isAuthorityPublicationPause,
  );
  final void Function() requireBinding;
  final Future<_RouterContext> Function() mcpContextWhenStable;
  final Duration Function() _budget;
  final Duration Function() _remaining;
  final bool Function(Object) isAuthorityPublicationPause;
  Duration get rpcBudgetRemaining => _budget();
  Duration get rpcRemaining => _remaining();

  factory _RouterRequest.capture(
    SessionRequest request,
    TrustedMcpRouter router,
  ) => _RouterRequest._(
    () =>
        request.requireMcpInvocationBinding(router.sessions, router.authority),
    () async =>
        _RouterContext.capture(await request.mcpContextWhenStable(), router),
    () => request.rpcBudgetRemaining,
    () => request.rpcRemaining,
    request.isAuthorityPublicationPause,
  );
}

final class _RouterContext {
  _RouterContext._({
    required this.sessionId,
    required this.grantId,
    required this.revision,
    required this.belongs,
    required this.start,
    required this.revalidate,
    required this.authorize,
    required this.authorizeWhenStable,
    required this.policyWhenStable,
    required Duration Function() untilExpiry,
  }) : _untilExpiry = untilExpiry;
  final String sessionId, grantId;
  final int revision;
  final bool Function() belongs;
  final McpServiceOperation Function(McpToolDefinition, Map<String, Object?>)
  start;
  final Future<void> Function({required Duration deadline}) revalidate;
  final void Function() authorize;
  final Future<void> Function({
    McpScope? scope,
    String? serverId,
    required Duration deadline,
  })
  authorizeWhenStable;
  final Future<GrantScopePolicy> Function({required Duration deadline})
  policyWhenStable;
  final Duration Function() _untilExpiry;
  Duration get untilExpiry => _untilExpiry();

  factory _RouterContext.capture(
    TrustedMcpContext context,
    TrustedMcpRouter router,
  ) => _RouterContext._(
    sessionId: context.sessionId,
    grantId: context.grantId,
    revision: context.revision,
    belongs: () => context.belongsTo(router.sessions, router.authority),
    start: (tool, arguments) => router.services.start(context, tool, arguments),
    revalidate: ({required deadline}) => context.revalidate(deadline: deadline),
    authorize: () => context.authorize(),
    authorizeWhenStable: ({scope, serverId, required deadline}) =>
        context.authorizeWhenStable(
          scope: scope,
          serverId: serverId,
          deadline: deadline,
        ),
    policyWhenStable: ({required deadline}) =>
        context.policyWhenStable(deadline: deadline),
    untilExpiry: () => context.untilExpiry,
  );
}
