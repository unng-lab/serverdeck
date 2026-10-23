import '../../lib/bootstrap/local_api_client.dart';
import '../../lib/bootstrap/trusted_native_bootstrap_host.dart';
import '../../packages/serverdeck_locald/test/support/owner_result_client.dart';

export '../../packages/serverdeck_locald/test/support/owner_result_client.dart'
    show OwnerResultFaults;

/// UI result-interest fixture using the real format3 bootstrap and RPC client.
class LossClient {
  LossClient() {
    client = OwnerResultFaultClient(
      _host.client,
      transport,
      closeOwner: _host.close,
    );
  }
  final _host = TrustedNativeBootstrapHost();
  final transport = OwnerResultFaults();
  late final LocalApiClient client;
  Future<void> prepare() => _host.prepare();
}
