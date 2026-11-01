import 'dart:convert';

// Literal target contract, independent of production CollectionSchema objects.
const names = [
  'StoredWorkspace',
  'StoredSettings',
  'StoredProfile',
  'StoredCredential',
  'StoredReceipt',
  'StoredMcpGrant',
  'StoredDelegation',
  'StoredAutomationProfile',
  'StoredAutomationRevision',
  'StoredAutomationPlan',
  'StoredAutomationApproval',
  'StoredAutomationJob',
  'StoredDesiredState',
  'StoredAutomationReceipt',
  'StoredAutomationEvent',
  'StoredHostTrust',
];

Map<String, List<int>> registry() => {
  for (final name in names)
    name: utf8.encode(
      jsonEncode({
        'name': name,
        'embedded': false,
        'properties': [
          if (names.indexOf(name) >= 2)
            {'name': 'entityId', 'type': 'String', 'target': null},
          {'name': 'payload', 'type': 'String', 'target': null},
        ],
        'indexes': [
          if (names.indexOf(name) >= 2)
            {
              'name': 'entityId',
              'properties': [
                {'name': 'entityId', 'type': 'Hash', 'caseSensitive': true},
              ],
              'unique': true,
              'replace': false,
            },
        ],
        'links': [],
        'version': 2,
      }),
    ),
};
