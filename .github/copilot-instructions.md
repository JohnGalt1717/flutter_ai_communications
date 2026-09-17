Agent rules for this repo live in `AGENTS.md`.

After every Dart save, fix analyzer ERROR/WARNING in that file. Diagnostics only in other files may wait while a multi-file refactor is still in flight.

Before `flutter test`, `dart test`, `flutter run`, `flutter drive`, or launching the example, run `dart analyze` on the workspace and fix every ERROR and WARNING. Do not run broken code.
