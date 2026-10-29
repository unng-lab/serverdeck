import 'package:flutter/material.dart';

import 'design_scenarios.dart';

/// Current003.4 metadata is separate from the unchanged historical35 bindings.
final currentBaseBindings = List<AcceptanceBinding>.unmodifiable(
  [
    ...designBindings,
    const AcceptanceBinding(
      screenId: '11-host-key-changed',
      group: 'A03',
      ownerFile: 'lib/servers/server_sections.dart',
      sourceOwners: ['lib/servers/server_sections.dart'],
      ownerRequirement: '001 trust lifecycle;003 current37',
      ownerFR: ['FR-003-LOCAL-14'],
      ownerAC: ['AC-003-3B'],
      taskIds: ['T132', 'T136'],
      states: ['host-key-changed'],
      notApplicableReason: 'No fabricated observed fingerprint.',
      productionWidgets: ['ServerChangedKeySection'],
    ),
    const AcceptanceBinding(
      screenId: '93-protected-effect-blocked',
      group: 'A04',
      ownerFile: 'lib/automation/automation_sections.dart',
      sourceOwners: ['lib/automation/automation_sections.dart'],
      ownerRequirement: 'FA07.1 blocked-unspecified',
      ownerFR: ['FR-003-LOCAL-09'],
      ownerAC: ['AC-003-1B'],
      taskIds: ['T133', 'T136'],
      states: ['blocked-unspecified'],
      notApplicableReason:
          'Effect identity is unknown; no protected cause discriminator.',
      productionWidgets: ['AutomationPlanSection'],
    ),
  ]..sort((a, b) => a.screenId.compareTo(b.screenId)),
);

const currentBaseFrames = <Size>[
  Size(1100, 760),
  Size(800, 600),
  Size(390, 800),
  Size(360, 800),
];
const currentBaseThemes = <ThemeMode>[ThemeMode.light, ThemeMode.dark];
const currentBaseScales = <double>[1, 2];
