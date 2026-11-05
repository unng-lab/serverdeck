# Compatible store format — 2026-11-04

User rule: increment database format only for demonstrated incompatibility,
not merely adding fields/collections. Database format2 remains current.
No compatibility aliases, application migrations, backfill, reset or record
conversion are introduced. Existing user database remains untouched during tests.
Constitution2.0.0 redefines principleVI accordingly; other principles unchanged.

Single currentStorageFormat2/isCompatibleStorageFormat policy serves manifest,
AppSettings default and settings guard. New MonitoringHistoryRecord/JournalSource
collections extend Isar schema without changing existing persisted fields or data
semantics. Absent new collections are empty and handled by ordinary Isar open.
Official Isar schema behavior is linked in the storage contract. Unknown or
incompatible formats and all existing integrity/security failures still reject.

Tasks002/T047 and004/T036 implement FR-221/222 and AC-221/222. Tests use synthetic
files and fake Isar backend; they do not open the real database or prove native
durability. Existing data/settings/security/metadata preservation is asserted
through the owner adapter. Mandatory checks and independent review pending after
this final user clarification. No commit/publication or user-data reset.


Actual final-clarification checks: output/current-format2-unit-2.log exit0:
exactformat377files0changes,flutter analyze0issues,boundary89files,724Flutter units,
2offline MCPschema and5build-tooling Python units. Current-format fixture preserves
storeId,CURRENT bytes,settings revisions/theme and security on the same backend,
without replacement publication; invalid/unknown formats reject. Previous transient
analyzer error was corrected before this successful complete run.
output/current-format2-links.log exactglobal lychee exit0,236total230OK6excluded0errors.
No product process or real Isar opened by tests. Independent review pending.
