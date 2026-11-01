import 'package:serverdeck_protocol/executor_release.dart';

/// A platform-verified artifact binding, supplied by the trusted composition
/// root. This is not a JSON constructor, execution permission or live session.
/// Each access must recheck the retained manifest and artifact hash binding.
abstract interface class VerifiedExecutorRelease {
  ExecutorRelease get descriptor;
  void revalidate();
}
