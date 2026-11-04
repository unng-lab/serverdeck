import '../domain/actor.dart';
import '../domain/models.dart';
import '../runtime/owned_work.dart';
import 'journal_protocol.dart';

final class JournalJob {
  const JournalJob(this.result, this._cancel);
  final Future<JournalReply> result;
  final void Function() _cancel;
  void cancel() => _cancel();
}

abstract interface class JournalConnectionPort {
  Stream<void> get changes;
  ConnectionView connection(String profileId);
  JournalJob beginJournal(
    UiActor actor,
    String profileId,
    String sessionId, {
    required int expectedConnectionRevision,
    required JournalRequest request,
    required WorkCancellation cancellation,
  });
}

abstract interface class JournalSshConnection {
  Future<JournalReply> collectJournal(
    JournalRequest request,
    WorkCancellation cancellation, {
    Duration timeout = const Duration(seconds: 5),
  });
}
