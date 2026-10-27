import 'package:serverdeck/bootstrap/bootstrap_controller.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';

BootstrapController dormantBootstrap() => BootstrapController(
  client: LocalApiClient(connect: () => throw StateError('NOT_STARTED')),
  prepare: () async {},
  ensureService: () async {},
);
