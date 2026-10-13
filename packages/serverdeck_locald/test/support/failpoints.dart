/// Only imported by the separate test executable, never by normal locald.
enum InitializationFailpoint {
  afterKey,
  beforeDatabase,
  afterDatabase,
  beforePromotion,
  afterPromotion,
  beforeCommit,
  afterCommit,
  beforeReply,
}
