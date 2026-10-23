import 'dart:async';

import 'package:serverdeck_protocol/mcp/handshake.dart';

import '../api/operational_auth.dart';
import '../api/owner_api.dart';
import '../api/owner_grants.dart';
import '../api/owner_profiles.dart';
import '../api/owner_trust_mutations.dart';
import '../api/owner_trust_probes.dart';
import '../api/trusted_owner_foundation.dart';
import '../automation/profiles.dart';
import '../mcp/profile_services.dart';
import '../mcp/router.dart';
import '../profiles/mutation_coordinator.dart';
import '../remote/ssh_transport.dart';
import '../remote/trust_probes.dart';
import '../storage/key_custody.dart';
import '../storage/state_store.dart';

/// One internal format3 service owner. Successful creation transfers the native
/// registry; the outer runtime still owns channels, store, key and writer mutex.
/// This component does not select startup, publish discovery or assert readiness.
final class TrustedControlServices implements TrustedOwnerApi {
  TrustedControlServices._({
    required StateStore store,
    required this.sessions,
    required this.authority,
    required this.router,
    required TrustedOwnerApiGroup owner,
    required TrustedFoundationOwnerApi foundation,
    required TrustedProfileOwnerApi profileOwner,
    required TrustMutationOwnerApi trustWrites,
    required TrustedAutomationProfileService catalog,
    required HostTrustProbeService probes,
    required SshTransportPool pool,
  }) : _store = store,
       _owner = owner,
       _foundation = foundation,
       _profileOwner = profileOwner,
       _trustWrites = trustWrites,
       _catalog = catalog,
       _probes = probes,
       _pool = pool;

  // Weak object identity claims cannot be supplied or grown by wire payloads.
  static final _stores = Expando<bool>();
  static final _registries = Expando<bool>();

  static Future<TrustedControlServices> create({
    required StateStore store,
    required KeyCustody custody,
    required ReceiptKeyMaterial receiptKey,
    required TrustedSessions sessions,
  }) async {
    if (!sessions.hasNativePublicationGate) throw StateError('NOT_READY');
    if (_stores[store] == true || _registries[sessions] == true)
      throw StateError('NOT_READY');
    store.trustedOperational;
    store.assertAutomationCustody(custody, receiptKey);
    _stores[store] = true;
    _registries[sessions] = true;
    final pool = SshTransportPool();
    TrustedMutationCoordinator? coordinator;
    TrustedMcpAuthority? authority;
    TrustedAutomationProfileService? catalog;
    HostTrustProbeService? probes;
    TrustedFoundationOwnerApi? foundation;
    TrustMutationOwnerApi? trustWrites;
    TrustedProfileOwnerApi? profileOwner;
    TrustedMcpRouter? router;
    try {
      coordinator = TrustedMutationCoordinator(store, custody, receiptKey);
      authority = TrustedMcpAuthority(store);
      catalog = TrustedAutomationProfileService(
        store: store,
        custody: custody,
        receiptKey: receiptKey,
        sessions: sessions,
        authority: authority,
      );
      probes = HostTrustProbeService(
        store: store,
        sessions: sessions,
        transports: pool,
      );
      foundation = TrustedFoundationOwnerApi(
        store: store,
        coordinator: coordinator,
        sessions: sessions,
      );
      trustWrites = TrustMutationOwnerApi(
        service: probes,
        coordinator: coordinator,
      );
      profileOwner = TrustedProfileOwnerApi(catalog);
      router = TrustedMcpRouter(
        sessions: sessions,
        authority: authority,
        services: TrustedProfileCatalogMcpServices(catalog),
      );
      return TrustedControlServices._(
        store: store,
        sessions: sessions,
        authority: authority,
        router: router,
        owner: TrustedOwnerApiGroup([
          foundation,
          TrustedGrantOwnerApi(store: store, sessions: sessions),
          profileOwner,
          TrustProbeOwnerApi(probes),
          trustWrites,
        ]),
        foundation: foundation,
        profileOwner: profileOwner,
        trustWrites: trustWrites,
        catalog: catalog,
        probes: probes,
        pool: pool,
      );
    } catch (error, stack) {
      // No caller can see the partial composition or admit its work. In
      // particular, rollback must not stop the caller's borrowed registry.
      final failed = await _settleAll([
        () => router?.close(),
        () => profileOwner?.close(),
        () => foundation?.close(),
        () => trustWrites?.close(),
        () => coordinator?.close(),
        () => catalog?.close(),
        () => probes?.close(),
        () => authority?.closeAndDrain(),
      ]);
      final poolFailed = await _settleAll([pool.close]);
      if (failed || poolFailed) throw StateError('SERVICE_UNAVAILABLE');
      _stores[store] = null;
      _registries[sessions] = null;
      Error.throwWithStackTrace(error, stack);
    }
  }

  final StateStore _store;
  final TrustedSessions sessions;
  final TrustedMcpAuthority authority;
  final TrustedMcpRouter router;
  final TrustedOwnerApiGroup _owner;
  final TrustedFoundationOwnerApi _foundation;
  final TrustedProfileOwnerApi _profileOwner;
  final TrustMutationOwnerApi _trustWrites;
  final TrustedAutomationProfileService _catalog;
  final HostTrustProbeService _probes;
  final SshTransportPool _pool;
  final _prepared = <TrustedOwnerInvocation>{};
  final _executing = <Future<Map<String, Object?>>>{};
  bool _closed = false;
  Future<void>? _closing;

  @override
  bool supports(String method) => _owner.supports(method);

  @override
  TrustedOwnerInvocation prepare(
    TrustedSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    if (!request.belongsTo(sessions) ||
        request.role != OperationalRole.owner ||
        request.method != method)
      throw StateError('FORBIDDEN');
    if (_closed) throw StateError('SERVICE_UNAVAILABLE');
    final inner = _owner.prepare(request, method, params, requestId: requestId);
    late final TrustedOwnerInvocation invocation;
    invocation = TrustedOwnerInvocation(
      request,
      () {
        if (_closed) throw StateError('SERVICE_UNAVAILABLE');
        final actual = inner.execute();
        _executing.add(actual);
        actual.then<void>(
          (_) => _executing.remove(actual),
          onError: (Object _, StackTrace __) => _executing.remove(actual),
        );
        return actual;
      },
      onClose: () {
        _prepared.remove(invocation);
        inner.close();
      },
    );
    _prepared.add(invocation);
    return invocation;
  }

  Future<void> close() {
    final previous = _closing;
    if (previous != null) return previous;
    final done = Completer<void>();
    _closing = done.future;
    done.future.ignore();
    _closed = true;
    var failed = false;
    void stop(void Function() action) {
      try {
        action();
      } catch (_) {
        failed = true;
      }
    }

    stop(sessions.stop);
    stop(router.close);
    stop(_profileOwner.close);
    for (final invocation in _prepared.toList()) {
      stop(invocation.close);
    }
    // Every drain starts before awaiting another service. Running writes may
    // hold probe claims/native leases needed by other services' close paths.
    () async {
      final drainsFailed = await _settleAll([
        _foundation.close,
        _trustWrites.close,
        _catalog.close,
        _probes.close,
        authority.closeAndDrain,
        sessions.close,
        for (final actual in _executing.toList())
          () =>
              actual.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      ]);
      final poolFailed = await _settleAll([_pool.close]);
      if (failed || drainsFailed || poolFailed)
        throw StateError('SERVICE_UNAVAILABLE');
      _stores[_store] = null;
    }().then<void>(
      (_) => done.complete(),
      onError: (Object _, StackTrace __) =>
          done.completeError(StateError('SERVICE_UNAVAILABLE')),
    );
    return done.future;
  }
}

/// Start all cleanup steps and observe all failures; never an early-error race.
Future<bool> _settleAll(Iterable<FutureOr<void> Function()> actions) async {
  var failed = false;
  await Future.wait<void>([
    for (final action in actions)
      Future<void>.sync(
        action,
      ).then<void>((_) {}, onError: (Object _, StackTrace __) => failed = true),
  ]);
  return failed;
}
