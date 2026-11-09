import 'dart:typed_data';

import '../storage/domain_repository.dart';
import '../storage/records.dart';
import 'actor.dart';
import 'app_operations.dart';
import 'models.dart';
import 'mutation_receipts.dart';

enum ReceiptMethod {
  createProfile('profiles.create'),
  updateProfile('profiles.update'),
  acceptTrust('trust.accept'),
  replaceTrust('trust.replace'),
  retainTrust('trust.retain'),
  saveSoftware('software.save'),
  deleteSoftware('software.delete'),
  addSoftwareNote('software.history.add');

  const ReceiptMethod(this.wire);
  final String wire;
}

/// Private signed identity of one request. Contains no original input/secret.
final class ReceiptTicket {
  ReceiptTicket._(this.clientId, this.mutationId, this.method, this._hmac);
  final String clientId, mutationId;
  final ReceiptMethod method;
  final Uint8List _hmac;
  bool _disposed = false;
  void dispose() {
    _hmac.fillRange(0, _hmac.length, 0);
    _disposed = true;
  }

  void _check() {
    if (_disposed) throw const OperationFailure(FailureCode.conflict);
  }

  @override
  String toString() => 'ReceiptTicket(redacted)';
}

final class ReceiptBook {
  const ReceiptBook(this.signer, this.utcNow);
  final ReceiptSigner signer;
  final int Function() utcNow;
  static const maxReceipts = 100000;
  static const lifetimeMs = 24 * 60 * 60 * 1000;

  /// Compute outside the command gate. Raw typed payload keeps exact secret and
  /// field-presence spelling; router must reject noncanonical base64 beforehand.
  ReceiptTicket ticket(
    Actor actor,
    ReceiptMethod method,
    String mutationId,
    Map<String, Object?> payload,
  ) {
    if (mutationId.isEmpty ||
        mutationId.length > 128 ||
        !RegExp(r'^[!-~]+$').hasMatch(mutationId)) {
      throw const OperationFailure(
        FailureCode.invalidArgument,
        field: OperationField.mutationId,
      );
    }
    final client = switch (actor) {
      McpActor() => actor.clientId,
      UiActor() => 'ui:${actor.ownerEpoch}',
    };
    return ReceiptTicket._(
      client,
      mutationId,
      method,
      signer.sign(method.wire, payload),
    );
  }

  MutationValue? lookup(
    CommandContext context,
    DomainRead records,
    ReceiptTicket ticket,
  ) => context.read(() {
    ticket._check();
    final receipt = records.receipt(ticket.clientId, ticket.mutationId);
    if (receipt == null || receipt.expiresAt <= utcNow()) return null;
    if (receipt.payloadHmac.length != 32 ||
        receipt.resultCode != 'OK' ||
        receipt.entityIds.length != 1 ||
        receipt.entityRevisions.length != 1 ||
        !isCanonicalUuid(receipt.entityIds.single) ||
        receipt.entityRevisions.single < 1 ||
        receipt.entityRevisions.single > 9007199254740991) {
      throw const OperationFailure(FailureCode.storageUnavailable);
    }
    if (receipt.method != ticket.method.wire ||
        !sameReceiptHmac(receipt.payloadHmac, ticket._hmac)) {
      throw const OperationFailure(
        FailureCode.conflict,
        field: OperationField.mutationId,
      );
    }
    return MutationValue(
      entityId: receipt.entityIds.single,
      revision: receipt.entityRevisions.single,
      replayed: true,
    );
  });

  /// Inside the same actual writeTxnSync+linearize as the profile/trust effect.
  /// Conflict/capacity errors abort that entire transaction.
  void record(
    DomainTransaction records,
    ReceiptTicket ticket,
    MutationValue result,
    int dataRevision,
  ) {
    ticket._check();
    final now = utcNow();
    records.pruneExpiredReceipts(now);
    if (records.receipt(ticket.clientId, ticket.mutationId) != null) {
      throw const OperationFailure(
        FailureCode.conflict,
        field: OperationField.mutationId,
      );
    }
    if (records.unexpiredReceiptCount(now) >= maxReceipts) {
      throw const OperationFailure(
        FailureCode.resourceExhausted,
        retryable: true,
      );
    }
    records.putReceipt(
      MutationReceipt()
        ..clientId = ticket.clientId
        ..mutationId = ticket.mutationId
        ..method = ticket.method.wire
        ..payloadHmac = ticket._hmac.toList()
        ..createdAt = now
        ..expiresAt = now + lifetimeMs
        ..resultCode = 'OK'
        ..entityIds = [result.entityId]
        ..entityRevisions = [result.revision]
        ..committedDataRevision = dataRevision,
    );
  }
}
