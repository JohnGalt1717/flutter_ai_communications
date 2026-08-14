# Workspace: federated pub plugin

## Parent

See the v1 spec issue.

## What to build

Turn the FFI `sum` stub into a Dart 3 pub workspace with a federated Flutter plugin: app package, platform interface, shared DSP package, and iOS / Android / Web implementations (desktop packages not created yet). Analysis options, workspace `pubspec`, and resolution follow current Flutter team conventions. The example app depends on the app package only.

## Acceptance criteria

- [ ] Root is a pub workspace; packages resolve with `resolution: workspace`
- [ ] Federated plugin `pubspec` wiring is valid for iOS, Android, and Web
- [ ] Shared analysis options are used by every package
- [ ] The leftover `sum` / Native Assets demo is gone from the public app package
- [ ] `dart pub get` succeeds at the workspace root

## Blocked by

None — can start immediately.
