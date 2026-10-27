import 'state_store_test.dart' as native;

void main() {
  for (final mode in [
    'mutation-limits',
    'mutation-allocation',
    'mutation-native-failure',
  ]) {
    native.registerRepositoryTest(mode: mode);
  }
}
