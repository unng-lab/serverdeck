# Synthetic SSH unit inputs

Public test vectors from pinned dartssh2 4.1.0 MIT archive; hashes in sources.json.
These are not user secrets and never connect to a server. The source license is
third_party/dartssh2/LICENSE. Encrypted vectors use only a documented test passphrase.


Current RSA PEM input fixtures are synthetic conversions of repository rsa2048.txt, generated offline with Python cryptography. AES128/192/256CBC and DES-EDE3CBC use fixed test-only IV bytes and the public synthetic phrase serverdeck-unit-passphrase, never user keys. Fixture preparation is not a runtime dependency.
