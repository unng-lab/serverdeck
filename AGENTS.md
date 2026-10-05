# Working Rules

## Spec Kit

- Spec Kit is installed in this repository: `.specify/` and `.agents/skills/speckit-*`.
- If the user asks to work through Spec Kit, use the Spec Kit skills and workflow.

## Required Checks

- After changing Flutter code, run `dart format --output=none --set-exit-if-changed .`,
  `flutter analyze`, and `flutter test`. Fix failures before committing.
- After changing specifications, check their links with
  `lychee "specs/**/*.md"`. Fix broken links before committing.
- Do not report checks as passed unless they were actually run successfully.
