# MCP client credential envelope

[MCP](mcp.md), [loading](loading.md), [tasks](../tasks.md), [model](../data-model.md).

## Responsibility

File layout, bounded custody and grant publication/recovery follow [credential files](credential-files.md).

T005 uses `packages/serverdeck_windows/lib/mcp_credentials.dart` for the same CurrentUser DPAPI envelope in locald and the verified bridge. It depends on the existing `UserProtection` interface and exact cryptography2.9.0 used elsewhere in the bundle. It never contains SSH, receipt-key or bootstrap material. This component handles encrypted bytes and a private in-memory key handle; file custody, grant policy, verified image role, challenge/session replay protection and transaction publication remain mandatory integrations. An envelope alone is never authority.

## Version1 and binding

The cleartext is strict UTF8 JSON, at most4096 bytes, exactly `{format:1,product:"serverdeck-next-mcp-client",workspaceId,grantId,secretRef,ownerSid,issuedAt,clientSecret}`. IDs are canonical UUIDv4, ownerSid matches the existing SID syntax, issuedAt is the common canonical UTC-millisecond timestamp. clientSecret is canonical padded standard base64 of exactly32 cryptographically random bytes. It is generated internally using the OS secure RNG on create; callers cannot choose/reuse key bytes. The envelope is protected with CurrentUser DPAPI/UI forbidden, never LocalMachine. Additional entropy is the UTF8 canonical foundation encoding of `{purpose:"serverdeck-next-mcp-client-v1",workspaceId,grantId,secretRef,ownerSid,issuedAt}`. Both entropy and the recovered cleartext bind all five identities/timestamp. Current mutable grant revision is deliberately absent: revocation increments metadata revision without rotating an issued secret. Replacement rotates secretRef/key and issuedAt; even a same-millisecond replacement has a new secretRef.

The immutable expected binding is captured and validated before asynchronous protection. On open, the caller supplies the binding obtained from the current retained grant (or the protected bridge lookup, subsequently checked by locald). Snapshot wrapper bytes before await, require ciphertext1..16384 bytes, strict byte values, exact recovered fields/types/binding and canonical secret encoding. Valid but unsupported integer format yields INCOMPATIBLE; malformed input, invalid binding, wrong user/entropy, unavailable protection and all other failures yield STORAGE_BLOCKED without private values/provider messages. Never expose cleartext or key bytes in public records, tools, configuration, errors or diagnostics.

## Key lifetime and MAC primitive

Before decoding clientSecret, check exact44-character standard base64 with one final `=` and zero unused padding bits (`^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$`). Arbitrary malformed text must never reach a decoder that can allocate a partial raw-key buffer and throw before returning it. Retain canonical encoded envelope bytes before checking plaintext size so an oversized failure also wipes the allocated cleartext. Allocation/cleanup order is assessed by source inspection plus malformed/boundary tests; no heap-erasure test is implied.

Creation returns an immutable ciphertext wrapper plus a private key handle. Opening returns that handle. Only HMAC-SHA256 over caller-supplied bytes1..4096 and comparison of an exact32-byte expected MAC are supported; no key getter/serialization. Snapshot transcript and expected MAC before await; invalid arguments fail with STORAGE_BLOCKED. Verification compares every MAC byte without content-dependent early return. Closed handles reject operations; close is idempotent and overwrites owned raw key bytes. A close during asynchronous MAC work must prevent its result being returned. Temporary owned raw byte/key buffers are overwritten/destroyed on success and failure. Dart immutable JSON strings and VM/DPAPI copies cannot promise physical zeroization; never persist cleartext. MAC bytes are authentication outputs, not key export.

This MAC primitive does not define the mcp.open transcript or provide a signing tool. T006 must build the exact authenticated session transcript, fresh nonce and replay/deadline/role checks before using it. No arbitrary MAC endpoint is exposed.

## Acceptance and integration gates

Tests must use real Windows CurrentUser DPAPI for successful create/open, independent random keys, same-key MAC agreement, each wrong binding dimension, ciphertext corruption, closed handles and bounded inputs. Injected providers additionally exercise malformed decrypted documents, unsupported formats, duplicate/unknown fields, noncanonical/invalid-size secrets, protection exceptions, input mutation across awaits, cleartext buffer cleanup and close-during-MAC. Injected cases supplement real DPAPI evidence; they cannot establish cross-user isolation or actual file ACL safety.

T005 file publication must retain owner-only ACL/reparse checks before decrypt and the staged/recovery/atomic grant receipt rules in MCP; T004 operational startup must open every referenced retained credential, including revoked metadata, without reviving permission. Protected lookup/pointer publication and DB recovery must be specified and tested before their integration, not invented by this envelope. T006/008 verified bundle/authentication and actual independent client tests remain release gates. No production startup is activated by adding this primitive.
