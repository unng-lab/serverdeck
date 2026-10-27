const product = 'serverdeck-next';
const apiMajor = 1;
const apiMinor = 0;
const workspaceSlot = 'default';

abstract interface class ProtocolCodec {
  Map<String, Object?> decode(List<int> bytes, {int maxBytes});
  List<int> encode(Map<String, Object?> document, {int maxBytes});
  List<int> canonical(Object? value);
}

const maxRequestBytes = 256 * 1024;
const maxResponseBytes = 8 * 1024 * 1024;
const maxHandshakeBytes = 8 * 1024;
const maxDepth = 16;
const maxPendingPerSession = 16;
const maxSessions = 8;
const maxMutationQueue = 32;
const rpcDeadline = Duration(seconds: 5);
const startupDeadline = Duration(seconds: 30);
const heartbeatInterval = Duration(seconds: 20);
const sessionLease = Duration(seconds: 60);
const shutdownGrace = Duration(seconds: 2);
