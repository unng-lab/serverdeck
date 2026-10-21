# Трассировка сервиса и его расширений

[Сам сервис](001-service-foundation/spec.md) · [Состав](service-overview.md) · [Каталог](business-requirements.md) · [Очередь](README.md)

Каждый из 132 общих FR имеет одного владельца. LOCAL и FR-SVC дополняют их. ID не зависят от номера каталога: сохранённые FR-001-LOCAL относятся к нынешнему 002, FR-002-LOCAL/AC-002 — к основе 001. Перенос не даёт статуса реализации и не возвращает историю старого сервиса.

Цепочка Specify: компонент/обязанность → требование → этап → проверяемая приёмка. Plan/контракт/Tasks обязательны до кодирования и пока не созданы.

| FR | Владелец | Этап и AC |
| --- | --- | --- |
| FR-001 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-002 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-007 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-012 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-014 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-121 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-122 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-123 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-002-LOCAL-01 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-002-LOCAL-02 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-002-LOCAL-03 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-SVC-001 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-SVC-002 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-SVC-003 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-SVC-004 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-SVC-005 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-SVC-006 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-SVC-007 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-SVC-015 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-SVC-016 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-SVC-017 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-SVC-018 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-SVC-019 | [001](001-service-foundation/spec.md) | 001.1: AC-SVC-1A, AC-SVC-1B, AC-SVC-1C, AC-002-1A, AC-002-1B, AC-002-1C, AC-SVC-BOOT |
| FR-008 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-009 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-010 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-013 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-124 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-002-LOCAL-04 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-002-LOCAL-05 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-002-LOCAL-06 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-002-LOCAL-07 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-002-LOCAL-08 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-SVC-008 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-SVC-009 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-SVC-010 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-SVC-011 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-SVC-020 | [001](001-service-foundation/spec.md) | 001.2: AC-SVC-2A, AC-SVC-2B, AC-SVC-2C, AC-002-2A, AC-002-2B, AC-002-2C, AC-SVC-READ |
| FR-035 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-036 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-037 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-038 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-039 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-040 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-041 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-042 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-043 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-044 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-002-LOCAL-09 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-002-LOCAL-10 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-002-LOCAL-11 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-002-LOCAL-12 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-002-LOCAL-13 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-002-LOCAL-14 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-SVC-012 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-SVC-013 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-SVC-014 | [001](001-service-foundation/spec.md) | 001.3: AC-SVC-3A, AC-SVC-3B, AC-SVC-3C, AC-002-3A, AC-002-3B, AC-002-3C, AC-SVC-CLOSE |
| FR-001-LOCAL-01 | [002](002-security-storage/spec.md) | 002.1: AC-001-1A, AC-001-1B, AC-001-1C |
| FR-001-LOCAL-02 | [002](002-security-storage/spec.md) | 002.1: AC-001-1A, AC-001-1B, AC-001-1C |
| FR-001-LOCAL-03 | [002](002-security-storage/spec.md) | 002.1: AC-001-1A, AC-001-1B, AC-001-1C |
| FR-001-LOCAL-04 | [002](002-security-storage/spec.md) | 002.1: AC-001-1A, AC-001-1B, AC-001-1C |
| FR-001-LOCAL-07 | [002](002-security-storage/spec.md) | 002.1: AC-001-1A, AC-001-1B, AC-001-1C |
| FR-001-LOCAL-10 | [002](002-security-storage/spec.md) | 002.1: AC-001-1A, AC-001-1B, AC-001-1C |
| FR-001-LOCAL-05 | [002](002-security-storage/spec.md) | 002.2: AC-001-2A, AC-001-2B, AC-001-2C |
| FR-001-LOCAL-06 | [002](002-security-storage/spec.md) | 002.2: AC-001-2A, AC-001-2B, AC-001-2C |
| FR-001-LOCAL-08 | [002](002-security-storage/spec.md) | 002.2: AC-001-2A, AC-001-2B, AC-001-2C |
| FR-001-LOCAL-09 | [002](002-security-storage/spec.md) | 002.3: AC-001-3A, AC-001-3B, AC-001-3C |
| FR-125 | [003](003-design-system/spec.md) | 003.1: AC-003-1A, AC-003-1B, AC-003-1C |
| FR-003-LOCAL-01 | [003](003-design-system/spec.md) | 003.1: AC-003-1A, AC-003-1B, AC-003-1C |
| FR-003-LOCAL-02 | [003](003-design-system/spec.md) | 003.1: AC-003-1A, AC-003-1B, AC-003-1C |
| FR-003-LOCAL-03 | [003](003-design-system/spec.md) | 003.1: AC-003-1A, AC-003-1B, AC-003-1C |
| FR-126 | [003](003-design-system/spec.md) | 003.2: AC-003-2A, AC-003-2B, AC-003-2C |
| FR-003-LOCAL-04 | [003](003-design-system/spec.md) | 003.2: AC-003-2A, AC-003-2B, AC-003-2C |
| FR-003-LOCAL-05 | [003](003-design-system/spec.md) | 003.2: AC-003-2A, AC-003-2B, AC-003-2C |
| FR-003-LOCAL-06 | [003](003-design-system/spec.md) | 003.3: AC-003-3A, AC-003-3B, AC-003-3C |
| FR-003-LOCAL-07 | [003](003-design-system/spec.md) | 003.3: AC-003-3A, AC-003-3B, AC-003-3C |
| FR-022 | [004](004-server-workspace/spec.md) | 004.1: AC-004-1A, AC-004-1B, AC-004-1C |
| FR-004-LOCAL-01 | [004](004-server-workspace/spec.md) | 004.1: AC-004-1A, AC-004-1B, AC-004-1C |
| FR-023 | [004](004-server-workspace/spec.md) | 004.2: AC-004-2A, AC-004-2B, AC-004-2C |
| FR-024 | [004](004-server-workspace/spec.md) | 004.2: AC-004-2A, AC-004-2B, AC-004-2C |
| FR-004-LOCAL-02 | [004](004-server-workspace/spec.md) | 004.2: AC-004-2A, AC-004-2B, AC-004-2C |
| FR-004-LOCAL-03 | [004](004-server-workspace/spec.md) | 004.2: AC-004-2A, AC-004-2B, AC-004-2C |
| FR-004-LOCAL-05 | [004](004-server-workspace/spec.md) | 004.2: AC-004-2A, AC-004-2B, AC-004-2C |
| FR-004-LOCAL-04 | [004](004-server-workspace/spec.md) | 004.3: AC-004-3A, AC-004-3B, AC-004-3C |
| FR-004-LOCAL-06 | [004](004-server-workspace/spec.md) | 004.3: AC-004-3A, AC-004-3B, AC-004-3C |
| FR-004-LOCAL-07 | [004](004-server-workspace/spec.md) | 004.3: AC-004-3A, AC-004-3B, AC-004-3C |
| FR-004-LOCAL-08 | [004](004-server-workspace/spec.md) | 004.3: AC-004-3A, AC-004-3B, AC-004-3C |
| FR-005-LOCAL-01 | [005](005-client-distribution/spec.md) | 005.1: AC-005-1A, AC-005-1B, AC-005-1C |
| FR-005-LOCAL-02 | [005](005-client-distribution/spec.md) | 005.1: AC-005-1A, AC-005-1B, AC-005-1C |
| FR-005-LOCAL-03 | [005](005-client-distribution/spec.md) | 005.1: AC-005-1A, AC-005-1B, AC-005-1C |
| FR-127 | [005](005-client-distribution/spec.md) | 005.2: AC-005-2A, AC-005-2B, AC-005-2C |
| FR-005-LOCAL-04 | [005](005-client-distribution/spec.md) | 005.2: AC-005-2A, AC-005-2B, AC-005-2C |
| FR-005-LOCAL-05 | [005](005-client-distribution/spec.md) | 005.2: AC-005-2A, AC-005-2B, AC-005-2C |
| FR-005-LOCAL-06 | [005](005-client-distribution/spec.md) | 005.2: AC-005-2A, AC-005-2B, AC-005-2C |
| FR-005-LOCAL-07 | [005](005-client-distribution/spec.md) | 005.2: AC-005-2A, AC-005-2B, AC-005-2C |
| FR-005-LOCAL-08 | [005](005-client-distribution/spec.md) | 005.2: AC-005-2A, AC-005-2B, AC-005-2C |
| FR-005-LOCAL-09 | [005](005-client-distribution/spec.md) | 005.2: AC-005-2A, AC-005-2B, AC-005-2C |
| FR-005-LOCAL-10 | [005](005-client-distribution/spec.md) | 005.3: AC-005-3A, AC-005-3B, AC-005-3C |
| FR-005-LOCAL-11 | [005](005-client-distribution/spec.md) | 005.3: AC-005-3A, AC-005-3B, AC-005-3C |
| FR-005-LOCAL-12 | [005](005-client-distribution/spec.md) | 005.3: AC-005-3A, AC-005-3B, AC-005-3C |
| FR-045 | [006](006-software-installation/spec.md) | 006.1: AC-006-1A, AC-006-1B, AC-006-1C |
| FR-046 | [006](006-software-installation/spec.md) | 006.1: AC-006-1A, AC-006-1B, AC-006-1C |
| FR-047 | [006](006-software-installation/spec.md) | 006.1: AC-006-1A, AC-006-1B, AC-006-1C |
| FR-006-LOCAL-01 | [006](006-software-installation/spec.md) | 006.1: AC-006-1A, AC-006-1B, AC-006-1C |
| FR-006-LOCAL-02 | [006](006-software-installation/spec.md) | 006.1: AC-006-1A, AC-006-1B, AC-006-1C |
| FR-006-LOCAL-03 | [006](006-software-installation/spec.md) | 006.1: AC-006-1A, AC-006-1B, AC-006-1C |
| FR-006-LOCAL-04 | [006](006-software-installation/spec.md) | 006.1: AC-006-1A, AC-006-1B, AC-006-1C |
| FR-006-LOCAL-05 | [006](006-software-installation/spec.md) | 006.1: AC-006-1A, AC-006-1B, AC-006-1C |
| FR-006-LOCAL-06 | [006](006-software-installation/spec.md) | 006.2: AC-006-2A, AC-006-2B, AC-006-2C |
| FR-006-LOCAL-08 | [006](006-software-installation/spec.md) | 006.2: AC-006-2A, AC-006-2B, AC-006-2C |
| FR-006-LOCAL-07 | [006](006-software-installation/spec.md) | 006.3: AC-006-3A, AC-006-3B, AC-006-3C |
| FR-006-LOCAL-09 | [006](006-software-installation/spec.md) | 006.3: AC-006-3A, AC-006-3B, AC-006-3C |
| FR-048 | [007](007-software-adoption/spec.md) | 007.1: AC-007-1A, AC-007-1B, AC-007-1C |
| FR-007-LOCAL-01 | [007](007-software-adoption/spec.md) | 007.1: AC-007-1A, AC-007-1B, AC-007-1C |
| FR-007-LOCAL-02 | [007](007-software-adoption/spec.md) | 007.1: AC-007-1A, AC-007-1B, AC-007-1C |
| FR-007-LOCAL-03 | [007](007-software-adoption/spec.md) | 007.1: AC-007-1A, AC-007-1B, AC-007-1C |
| FR-007-LOCAL-04 | [007](007-software-adoption/spec.md) | 007.1: AC-007-1A, AC-007-1B, AC-007-1C |
| FR-007-LOCAL-05 | [007](007-software-adoption/spec.md) | 007.2: AC-007-2A, AC-007-2B, AC-007-2C |
| FR-007-LOCAL-06 | [007](007-software-adoption/spec.md) | 007.2: AC-007-2A, AC-007-2B, AC-007-2C |
| FR-007-LOCAL-07 | [007](007-software-adoption/spec.md) | 007.3: AC-007-3A, AC-007-3B, AC-007-3C |
| FR-007-LOCAL-08 | [007](007-software-adoption/spec.md) | 007.3: AC-007-3A, AC-007-3B, AC-007-3C |
| FR-007-LOCAL-09 | [007](007-software-adoption/spec.md) | 007.3: AC-007-3A, AC-007-3B, AC-007-3C |
| FR-003 | [008](008-fleet-workspace/spec.md) | 008.1: AC-008-1A, AC-008-1B, AC-008-1C |
| FR-004 | [008](008-fleet-workspace/spec.md) | 008.1: AC-008-1A, AC-008-1B, AC-008-1C |
| FR-005 | [008](008-fleet-workspace/spec.md) | 008.1: AC-008-1A, AC-008-1B, AC-008-1C |
| FR-006 | [008](008-fleet-workspace/spec.md) | 008.1: AC-008-1A, AC-008-1B, AC-008-1C |
| FR-011 | [008](008-fleet-workspace/spec.md) | 008.1: AC-008-1A, AC-008-1B, AC-008-1C |
| FR-015 | [008](008-fleet-workspace/spec.md) | 008.1: AC-008-1A, AC-008-1B, AC-008-1C |
| FR-016 | [008](008-fleet-workspace/spec.md) | 008.1: AC-008-1A, AC-008-1B, AC-008-1C |
| FR-017 | [008](008-fleet-workspace/spec.md) | 008.2: AC-008-2A, AC-008-2B, AC-008-2C |
| FR-018 | [008](008-fleet-workspace/spec.md) | 008.2: AC-008-2A, AC-008-2B, AC-008-2C |
| FR-019 | [008](008-fleet-workspace/spec.md) | 008.2: AC-008-2A, AC-008-2B, AC-008-2C |
| FR-020 | [008](008-fleet-workspace/spec.md) | 008.2: AC-008-2A, AC-008-2B, AC-008-2C |
| FR-021 | [008](008-fleet-workspace/spec.md) | 008.3: AC-008-3A, AC-008-3B, AC-008-3C |
| FR-025 | [009](009-observability/spec.md) | 009.1: AC-009-1A, AC-009-1B, AC-009-1C |
| FR-028 | [009](009-observability/spec.md) | 009.1: AC-009-1A, AC-009-1B, AC-009-1C |
| FR-029 | [009](009-observability/spec.md) | 009.1: AC-009-1A, AC-009-1B, AC-009-1C |
| FR-030 | [009](009-observability/spec.md) | 009.1: AC-009-1A, AC-009-1B, AC-009-1C |
| FR-031 | [009](009-observability/spec.md) | 009.1: AC-009-1A, AC-009-1B, AC-009-1C |
| FR-032 | [009](009-observability/spec.md) | 009.1: AC-009-1A, AC-009-1B, AC-009-1C |
| FR-033 | [009](009-observability/spec.md) | 009.1: AC-009-1A, AC-009-1B, AC-009-1C |
| FR-034 | [009](009-observability/spec.md) | 009.1: AC-009-1A, AC-009-1B, AC-009-1C |
| FR-116 | [009](009-observability/spec.md) | 009.1: AC-009-1A, AC-009-1B, AC-009-1C |
| FR-009-LOCAL-01 | [009](009-observability/spec.md) | 009.1: AC-009-1A, AC-009-1B, AC-009-1C |
| FR-026 | [009](009-observability/spec.md) | 009.2: AC-009-2A, AC-009-2B, AC-009-2C |
| FR-009-LOCAL-02 | [009](009-observability/spec.md) | 009.2: AC-009-2A, AC-009-2B, AC-009-2C |
| FR-027 | [009](009-observability/spec.md) | 009.3: AC-009-3A, AC-009-3B, AC-009-3C |
| FR-053 | [010](010-system-service-management/spec.md) | 010.1: AC-010-1A, AC-010-1B, AC-010-1C |
| FR-054 | [010](010-system-service-management/spec.md) | 010.1: AC-010-1A, AC-010-1B, AC-010-1C |
| FR-055 | [010](010-system-service-management/spec.md) | 010.1: AC-010-1A, AC-010-1B, AC-010-1C |
| FR-056 | [010](010-system-service-management/spec.md) | 010.1: AC-010-1A, AC-010-1B, AC-010-1C |
| FR-058 | [010](010-system-service-management/spec.md) | 010.1: AC-010-1A, AC-010-1B, AC-010-1C |
| FR-065 | [010](010-system-service-management/spec.md) | 010.2: AC-010-2A, AC-010-2B, AC-010-2C |
| FR-066 | [010](010-system-service-management/spec.md) | 010.2: AC-010-2A, AC-010-2B, AC-010-2C |
| FR-067 | [010](010-system-service-management/spec.md) | 010.2: AC-010-2A, AC-010-2B, AC-010-2C |
| FR-057 | [010](010-system-service-management/spec.md) | 010.3: AC-010-3A, AC-010-3B, AC-010-3C |
| FR-068 | [010](010-system-service-management/spec.md) | 010.3: AC-010-3A, AC-010-3B, AC-010-3C |
| FR-069 | [010](010-system-service-management/spec.md) | 010.3: AC-010-3A, AC-010-3B, AC-010-3C |
| FR-070 | [010](010-system-service-management/spec.md) | 010.3: AC-010-3A, AC-010-3B, AC-010-3C |
| FR-085 | [011](011-access-management/spec.md) | 011.1: AC-011-1A, AC-011-1B, AC-011-1C |
| FR-086 | [011](011-access-management/spec.md) | 011.1: AC-011-1A, AC-011-1B, AC-011-1C |
| FR-087 | [011](011-access-management/spec.md) | 011.2: AC-011-2A, AC-011-2B, AC-011-2C |
| FR-088 | [011](011-access-management/spec.md) | 011.2: AC-011-2A, AC-011-2B, AC-011-2C |
| FR-089 | [011](011-access-management/spec.md) | 011.2: AC-011-2A, AC-011-2B, AC-011-2C |
| FR-090 | [011](011-access-management/spec.md) | 011.3: AC-011-3A, AC-011-3B, AC-011-3C |
| FR-108 | [012](012-backup-recovery/spec.md) | 012.1: AC-012-1A, AC-012-1B, AC-012-1C |
| FR-109 | [012](012-backup-recovery/spec.md) | 012.1: AC-012-1A, AC-012-1B, AC-012-1C |
| FR-113 | [012](012-backup-recovery/spec.md) | 012.1: AC-012-1A, AC-012-1B, AC-012-1C |
| FR-114 | [012](012-backup-recovery/spec.md) | 012.1: AC-012-1A, AC-012-1B, AC-012-1C |
| FR-012-LOCAL-01 | [012](012-backup-recovery/spec.md) | 012.1: AC-012-1A, AC-012-1B, AC-012-1C |
| FR-012-LOCAL-02 | [012](012-backup-recovery/spec.md) | 012.1: AC-012-1A, AC-012-1B, AC-012-1C |
| FR-112 | [012](012-backup-recovery/spec.md) | 012.2: AC-012-2A, AC-012-2B, AC-012-2C |
| FR-110 | [012](012-backup-recovery/spec.md) | 012.3: AC-012-3A, AC-012-3B, AC-012-3C |
| FR-111 | [012](012-backup-recovery/spec.md) | 012.3: AC-012-3A, AC-012-3B, AC-012-3C |
| FR-091 | [013](013-files-diagnostics/spec.md) | 013.1: AC-013-1A, AC-013-1B, AC-013-1C |
| FR-092 | [013](013-files-diagnostics/spec.md) | 013.1: AC-013-1A, AC-013-1B, AC-013-1C |
| FR-093 | [013](013-files-diagnostics/spec.md) | 013.1: AC-013-1A, AC-013-1B, AC-013-1C |
| FR-094 | [013](013-files-diagnostics/spec.md) | 013.2: AC-013-2A, AC-013-2B, AC-013-2C |
| FR-095 | [013](013-files-diagnostics/spec.md) | 013.2: AC-013-2A, AC-013-2B, AC-013-2C |
| FR-096 | [013](013-files-diagnostics/spec.md) | 013.2: AC-013-2A, AC-013-2B, AC-013-2C |
| FR-097 | [013](013-files-diagnostics/spec.md) | 013.3: AC-013-3A, AC-013-3B, AC-013-3C |
| FR-098 | [013](013-files-diagnostics/spec.md) | 013.3: AC-013-3A, AC-013-3B, AC-013-3C |
| FR-099 | [013](013-files-diagnostics/spec.md) | 013.3: AC-013-3A, AC-013-3B, AC-013-3C |
| FR-115 | [013](013-files-diagnostics/spec.md) | 013.3: AC-013-3A, AC-013-3B, AC-013-3C |
| FR-059 | [014](014-software-maintenance/spec.md) | 014.1: AC-014-1A, AC-014-1B, AC-014-1C |
| FR-062 | [014](014-software-maintenance/spec.md) | 014.1: AC-014-1A, AC-014-1B, AC-014-1C |
| FR-063 | [014](014-software-maintenance/spec.md) | 014.1: AC-014-1A, AC-014-1B, AC-014-1C |
| FR-049 | [014](014-software-maintenance/spec.md) | 014.2: AC-014-2A, AC-014-2B, AC-014-2C |
| FR-050 | [014](014-software-maintenance/spec.md) | 014.2: AC-014-2A, AC-014-2B, AC-014-2C |
| FR-060 | [014](014-software-maintenance/spec.md) | 014.2: AC-014-2A, AC-014-2B, AC-014-2C |
| FR-061 | [014](014-software-maintenance/spec.md) | 014.2: AC-014-2A, AC-014-2B, AC-014-2C |
| FR-051 | [014](014-software-maintenance/spec.md) | 014.3: AC-014-3A, AC-014-3B, AC-014-3C |
| FR-052 | [014](014-software-maintenance/spec.md) | 014.3: AC-014-3A, AC-014-3B, AC-014-3C |
| FR-064 | [014](014-software-maintenance/spec.md) | 014.3: AC-014-3A, AC-014-3B, AC-014-3C |
| FR-079 | [015](015-storage-management/spec.md) | 015.1: AC-015-1A, AC-015-1B, AC-015-1C |
| FR-080 | [015](015-storage-management/spec.md) | 015.1: AC-015-1A, AC-015-1B, AC-015-1C |
| FR-081 | [015](015-storage-management/spec.md) | 015.1: AC-015-1A, AC-015-1B, AC-015-1C |
| FR-082 | [015](015-storage-management/spec.md) | 015.1: AC-015-1A, AC-015-1B, AC-015-1C |
| FR-083 | [015](015-storage-management/spec.md) | 015.2: AC-015-2A, AC-015-2B, AC-015-2C |
| FR-084 | [015](015-storage-management/spec.md) | 015.3: AC-015-3A, AC-015-3B, AC-015-3C |
| FR-071 | [016](016-network-management/spec.md) | 016.1: AC-016-1A, AC-016-1B, AC-016-1C |
| FR-075 | [016](016-network-management/spec.md) | 016.1: AC-016-1A, AC-016-1B, AC-016-1C |
| FR-072 | [016](016-network-management/spec.md) | 016.2: AC-016-2A, AC-016-2B, AC-016-2C |
| FR-073 | [016](016-network-management/spec.md) | 016.2: AC-016-2A, AC-016-2B, AC-016-2C |
| FR-074 | [016](016-network-management/spec.md) | 016.2: AC-016-2A, AC-016-2B, AC-016-2C |
| FR-076 | [016](016-network-management/spec.md) | 016.2: AC-016-2A, AC-016-2B, AC-016-2C |
| FR-077 | [016](016-network-management/spec.md) | 016.3: AC-016-3A, AC-016-3B, AC-016-3C |
| FR-078 | [016](016-network-management/spec.md) | 016.3: AC-016-3A, AC-016-3B, AC-016-3C |
| FR-129 | [016](016-network-management/spec.md) | 016.3: AC-016-3A, AC-016-3B, AC-016-3C |
| FR-100 | [017](017-compute-management/spec.md) | 017.1: AC-017-1A, AC-017-1B, AC-017-1C |
| FR-101 | [017](017-compute-management/spec.md) | 017.1: AC-017-1A, AC-017-1B, AC-017-1C |
| FR-104 | [017](017-compute-management/spec.md) | 017.1: AC-017-1A, AC-017-1B, AC-017-1C |
| FR-105 | [017](017-compute-management/spec.md) | 017.1: AC-017-1A, AC-017-1B, AC-017-1C |
| FR-102 | [017](017-compute-management/spec.md) | 017.2: AC-017-2A, AC-017-2B, AC-017-2C |
| FR-106 | [017](017-compute-management/spec.md) | 017.2: AC-017-2A, AC-017-2B, AC-017-2C |
| FR-103 | [017](017-compute-management/spec.md) | 017.3: AC-017-3A, AC-017-3B, AC-017-3C |
| FR-107 | [017](017-compute-management/spec.md) | 017.3: AC-017-3A, AC-017-3B, AC-017-3C |
| FR-117 | [018](018-security-controls/spec.md) | 018.1: AC-018-1A, AC-018-1B, AC-018-1C |
| FR-118 | [018](018-security-controls/spec.md) | 018.1: AC-018-1A, AC-018-1B, AC-018-1C |
| FR-119 | [018](018-security-controls/spec.md) | 018.2: AC-018-2A, AC-018-2B, AC-018-2C |
| FR-120 | [018](018-security-controls/spec.md) | 018.3: AC-018-3A, AC-018-3B, AC-018-3C |
| FR-128 | [019](019-specialized-capabilities/spec.md) | 019.1: AC-019-1A, AC-019-1B, AC-019-1C |
| FR-130 | [019](019-specialized-capabilities/spec.md) | 019.1: AC-019-1A, AC-019-1B, AC-019-1C |
| FR-019-LOCAL-01 | [019](019-specialized-capabilities/spec.md) | 019.1: AC-019-1A, AC-019-1B, AC-019-1C |
| FR-019-LOCAL-02 | [019](019-specialized-capabilities/spec.md) | 019.1: AC-019-1A, AC-019-1B, AC-019-1C |
| FR-131 | [019](019-specialized-capabilities/spec.md) | 019.2: AC-019-2A, AC-019-2B, AC-019-2C |
| FR-132 | [019](019-specialized-capabilities/spec.md) | 019.3: AC-019-3A, AC-019-3B, AC-019-3C |
| FR-020-LOCAL-01 | [020](020-metadata-sync/spec.md) | 020.1: AC-020-1A, AC-020-1B, AC-020-1C |
| FR-020-LOCAL-02 | [020](020-metadata-sync/spec.md) | 020.1: AC-020-1A, AC-020-1B, AC-020-1C |
| FR-020-LOCAL-03 | [020](020-metadata-sync/spec.md) | 020.1: AC-020-1A, AC-020-1B, AC-020-1C |
| FR-020-LOCAL-07 | [020](020-metadata-sync/spec.md) | 020.1: AC-020-1A, AC-020-1B, AC-020-1C |
| FR-020-LOCAL-04 | [020](020-metadata-sync/spec.md) | 020.2: AC-020-2A, AC-020-2B, AC-020-2C |
| FR-020-LOCAL-05 | [020](020-metadata-sync/spec.md) | 020.2: AC-020-2A, AC-020-2B, AC-020-2C |
| FR-020-LOCAL-06 | [020](020-metadata-sync/spec.md) | 020.3: AC-020-3A, AC-020-3B, AC-020-3C |

## Общие пользовательские сценарии

| Общие AC | Ответственный пакет |
| --- | --- |
| AC-001, AC-003, AC-010, AC-011, AC-012, AC-051 | [001](001-service-foundation/spec.md) |
| AC-016 | [006](006-software-installation/spec.md) |
| AC-017, AC-018 | [007](007-software-adoption/spec.md) |
| AC-002, AC-004, AC-005, AC-006 | [008](008-fleet-workspace/spec.md) |
| AC-007, AC-008, AC-009 | [009](009-observability/spec.md) |
| AC-013, AC-014, AC-015, AC-022, AC-023, AC-024 | [010](010-system-service-management/spec.md) |
| AC-031, AC-032, AC-033 | [011](011-access-management/spec.md) |
| AC-046, AC-047, AC-048 | [012](012-backup-recovery/spec.md) |
| AC-034, AC-035, AC-036, AC-037, AC-038, AC-039, AC-049 | [013](013-files-diagnostics/spec.md) |
| AC-019, AC-020, AC-021 | [014](014-software-maintenance/spec.md) |
| AC-028, AC-029, AC-030 | [015](015-storage-management/spec.md) |
| AC-025, AC-026, AC-027 | [016](016-network-management/spec.md) |
| AC-040, AC-041, AC-042, AC-043, AC-044, AC-045 | [017](017-compute-management/spec.md) |
| AC-050 | [018](018-security-controls/spec.md) |
| AC-052, AC-053, AC-054 | [019](019-specialized-capabilities/spec.md) |

Защитные требования действуют с первого применимого действия во всех потребителях. Общие SC каталога применяются по сценарию; собственные SC-SVC и компонентные LOCAL SC дают дополнительные outcomes. Проверка текста и наличие ID не доказывают выполнения приёмки.

## MCP — 021

| Requirement | Owner | Acceptance |
| --- | --- | --- |
| FR-MCP-001 | [021](021-mcp-control/spec.md) | AC-MCP-1A/B/C; cross-cutting SC-MCP-001–006 |
| FR-MCP-002 | [021](021-mcp-control/spec.md) | AC-MCP-1A/B/C; cross-cutting SC-MCP-001–006 |
| FR-MCP-003 | [021](021-mcp-control/spec.md) | AC-MCP-1A/B/C; cross-cutting SC-MCP-001–006 |
| FR-MCP-004 | [021](021-mcp-control/spec.md) | AC-MCP-1A/B/C; cross-cutting SC-MCP-001–006 |
| FR-MCP-005 | [021](021-mcp-control/spec.md) | AC-MCP-1A/B/C; cross-cutting SC-MCP-001–006 |
| FR-MCP-006 | [021](021-mcp-control/spec.md) | AC-MCP-2A/B/C; cross-cutting SC-MCP-001–006 |
| FR-MCP-007 | [021](021-mcp-control/spec.md) | AC-MCP-2A/B/C; cross-cutting SC-MCP-001–006 |
| FR-MCP-008 | [021](021-mcp-control/spec.md) | AC-MCP-3A/B/C/D; cross-cutting SC-MCP-001–006 |
| FR-MCP-009 | [021](021-mcp-control/spec.md) | AC-MCP-3A/B/C/D; cross-cutting SC-MCP-001–006 |
| FR-MCP-010 | [021](021-mcp-control/spec.md) | AC-MCP-3A/B/C/D; cross-cutting SC-MCP-001–006 |
| FR-MCP-011 | [021](021-mcp-control/spec.md) | AC-MCP-3A/B/C/D; cross-cutting SC-MCP-001–006 |
| FR-MCP-012 | [021](021-mcp-control/spec.md) | AC-MCP-3A/B/C/D; cross-cutting SC-MCP-001–006 |
| FR-MCP-013 | [021](021-mcp-control/spec.md) | AC-MCP-3A/B/C/D; cross-cutting SC-MCP-001–006 |
| FR-MCP-014 | [021](021-mcp-control/spec.md) | AC-MCP-3A/B/C/D; cross-cutting SC-MCP-001–006 |
| FR-MCP-015 | [021](021-mcp-control/spec.md) | AC-MCP-3A/B/C/D; cross-cutting SC-MCP-001–006 |
| FR-MCP-016 | [021](021-mcp-control/spec.md) | AC-MCP-3A/B/C/D; cross-cutting SC-MCP-001–006 |
