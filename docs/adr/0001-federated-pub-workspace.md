# Federated Flutter plugin in a pub workspace

The current repo is a single FFI `sum` stub. Web cannot share that C hook, and iOS/Android need different communications graphs, so the product is a Flutter plugin federated across a Dart 3 pub workspace: app package, `platform_interface`, `shared` DSP, and per-platform packages (`ios`, `android`, `web` now; desktop later). We rejected one-package conditional imports (web still forks the world) and keeping MethodChannels in the host app (that is the Scribe mess this library exists to retire).
