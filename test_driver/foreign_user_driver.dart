import 'package:integration_test/integration_test_driver.dart';

// The foreign runner never writes response JSON into the shared checkout.
Future<void> main() => integrationDriver(responseDataCallback: null);
