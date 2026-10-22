part of 'profiles.dart';

/// Fixed native 2 composition; never selected by a wire field.
final class AutomationProfileService extends _CatalogService {
  AutomationProfileService({
    required super.store,
    required super.custody,
    required super.receiptKey,
    required this.sessions,
    required this.authority,
    super.clock,
  });
  final OperationalSessions sessions;
  final OperationalMcpAuthority authority;
  @override
  bool get _hasGate => sessions.hasNativePublicationGate;
  @override
  bool get _authorityBelongs => authority.belongsTo(store);
  @override
  WorkspaceState get _foundation => store.operational.foundation.state;
  @override
  AutomationSnapshot get _snapshot => store.operational.automation;
  @override
  Future<Map<String, Object?>> _mutate(
    AutomationProfileCommand command, {
    required String? originGrantId,
    required int? expectedGrantRevision,
    required DateTime Function() clock,
  }) => store.mutateAutomationProfile(
    command,
    originGrantId: originGrantId,
    expectedGrantRevision: expectedGrantRevision,
    clock: clock,
  );
  @override
  Future<T> _runAuthority<T>(
    Future<T> Function() effect, {
    required Duration deadline,
    void Function(Future<void>)? observeNativeCompletion,
  }) => sessions.runAuthorityMutation(
    effect,
    deadline: deadline,
    observeNativeCompletion: observeNativeCompletion,
  );
  ProfileCatalogActor ownerActor(
    OperationalSessionRequest request,
    String operation,
  ) {
    final actor = ProfileCatalogActor._(
      this,
      operation,
      _CatalogProof.ownerOperational(request, this, operation),
    );
    actor._check();
    _ready();
    return actor;
  }

  ProfileCatalogActor mcpActor(
    OperationalMcpContext context,
    String operation,
  ) {
    final actor = ProfileCatalogActor._(
      this,
      operation,
      _CatalogProof.mcpOperational(context, this),
    );
    actor._identityCheck();
    _ready();
    return actor;
  }

  ProfileCatalogOperation start(
    ProfileCatalogActor actor,
    ProfileCatalogInput input,
  ) => _start(actor, input);
}

final class ProfileCatalogActor extends _CatalogActor {
  ProfileCatalogActor._(
    AutomationProfileService service,
    String operation,
    _CatalogProof proof,
  ) : super._(service, operation, proof);
}

/// Fixed native 3 composition; never selected by a wire field.
final class TrustedAutomationProfileService extends _CatalogService {
  TrustedAutomationProfileService({
    required super.store,
    required super.custody,
    required super.receiptKey,
    required this.sessions,
    required this.authority,
    super.clock,
  });
  final TrustedSessions sessions;
  final TrustedMcpAuthority authority;
  @override
  bool get _hasGate => sessions.hasNativePublicationGate;
  @override
  bool get _authorityBelongs => authority.belongsTo(store);
  @override
  WorkspaceState get _foundation =>
      store.trustedOperational.foundation.foundation;
  @override
  AutomationSnapshot get _snapshot => store.trustedOperational.automation;
  @override
  Future<Map<String, Object?>> _mutate(
    AutomationProfileCommand command, {
    required String? originGrantId,
    required int? expectedGrantRevision,
    required DateTime Function() clock,
  }) => store.mutateTrustedAutomationProfile(
    command,
    originGrantId: originGrantId,
    expectedGrantRevision: expectedGrantRevision,
    clock: clock,
  );
  @override
  Future<T> _runAuthority<T>(
    Future<T> Function() effect, {
    required Duration deadline,
    void Function(Future<void>)? observeNativeCompletion,
  }) => sessions.runAuthorityMutation(
    effect,
    deadline: deadline,
    observeNativeCompletion: observeNativeCompletion,
  );
  TrustedProfileCatalogActor ownerActor(
    TrustedSessionRequest request,
    String operation,
  ) {
    final actor = TrustedProfileCatalogActor._(
      this,
      operation,
      _CatalogProof.ownerTrusted(request, this, operation),
    );
    actor._check();
    _ready();
    return actor;
  }

  TrustedProfileCatalogActor mcpActor(
    TrustedMcpContext context,
    String operation,
  ) {
    final actor = TrustedProfileCatalogActor._(
      this,
      operation,
      _CatalogProof.mcpTrusted(context, this),
    );
    actor._identityCheck();
    _ready();
    return actor;
  }

  ProfileCatalogOperation start(
    TrustedProfileCatalogActor actor,
    ProfileCatalogInput input,
  ) => _start(actor, input);
}

final class TrustedProfileCatalogActor extends _CatalogActor {
  TrustedProfileCatalogActor._(
    TrustedAutomationProfileService service,
    String operation,
    _CatalogProof proof,
  ) : super._(service, operation, proof);
}

/// Bound closures are captured only by the four fixed typed factories below.
/// No caller can construct a proof, provide a role or swap its service binding.
final class _CatalogProof {
  _CatalogProof._({
    required this.identity,
    required this.authorize,
    required this.authorizeStable,
    required this.remaining,
    required this.origin,
    required this.revision,
    required this.revalidate,
  });
  final void Function() identity, authorize;
  final Future<void> Function(Duration) authorizeStable;
  final Duration? Function() remaining;
  final String? Function() origin;
  final int? Function() revision;
  final Future<void> Function(Duration, void Function(Future<void>)) revalidate;
  factory _CatalogProof.ownerOperational(
    OperationalSessionRequest request,
    AutomationProfileService service,
    String operation,
  ) => _CatalogProof._(
    identity: () {
      if (!request.belongsTo(service.sessions) ||
          request.role != OperationalRole.owner ||
          request.method != 'automation.profiles.$operation' ||
          !request.initialAdmissionProved)
        throw StateError('FORBIDDEN');
      request.rpcRemaining;
    },
    authorize: () {},
    authorizeStable: (_) async {},
    remaining: () => request.rpcRemaining,
    origin: () => null,
    revision: () => null,
    revalidate: (_, observe) =>
        request.revalidate(observeNativeCompletion: observe),
  );
  factory _CatalogProof.mcpOperational(
    OperationalMcpContext context,
    AutomationProfileService service,
  ) => _CatalogProof._(
    identity: () {
      if (!context.belongsTo(service.sessions, service.authority))
        throw StateError('FORBIDDEN');
    },
    authorize: () => context.authorize(scope: McpScope.author),
    authorizeStable: (deadline) =>
        context.authorizeWhenStable(scope: McpScope.author, deadline: deadline),
    remaining: () => null,
    origin: () => context.grantId,
    revision: () => context.revision,
    revalidate: (deadline, observe) => context.revalidate(
      deadline: deadline,
      observeNativeCompletion: observe,
    ),
  );
  factory _CatalogProof.ownerTrusted(
    TrustedSessionRequest request,
    TrustedAutomationProfileService service,
    String operation,
  ) => _CatalogProof._(
    identity: () {
      if (!request.belongsTo(service.sessions) ||
          request.role != OperationalRole.owner ||
          request.method != 'automation.profiles.$operation' ||
          !request.initialAdmissionProved)
        throw StateError('FORBIDDEN');
      request.rpcRemaining;
    },
    authorize: () {},
    authorizeStable: (_) async {},
    remaining: () => request.rpcRemaining,
    origin: () => null,
    revision: () => null,
    revalidate: (_, observe) =>
        request.revalidate(observeNativeCompletion: observe),
  );
  factory _CatalogProof.mcpTrusted(
    TrustedMcpContext context,
    TrustedAutomationProfileService service,
  ) => _CatalogProof._(
    identity: () {
      if (!context.belongsTo(service.sessions, service.authority))
        throw StateError('FORBIDDEN');
    },
    authorize: () => context.authorize(scope: McpScope.author),
    authorizeStable: (deadline) =>
        context.authorizeWhenStable(scope: McpScope.author, deadline: deadline),
    remaining: () => null,
    origin: () => context.grantId,
    revision: () => context.revision,
    revalidate: (deadline, observe) => context.revalidate(
      deadline: deadline,
      observeNativeCompletion: observe,
    ),
  );
}
