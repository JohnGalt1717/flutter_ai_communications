/// Kind of a [ScreenSource]. Platforms omit kinds they cannot offer.
enum ScreenSourceKind {
  /// One attached display.
  display,

  /// One top-level window.
  window,

  /// Bounding viewport of every attached display (library stitch).
  allDisplays,

  /// OS picker stands in; the catalog has no real list.
  systemPicker,
}

/// Picker label for a window Screen source. Always includes the owning
/// application when known. Generic "Window" titles are not advertised.
String? windowShareLabel({String? title, String? applicationName}) {
  final app = applicationName?.trim() ?? '';
  final raw = title?.trim() ?? '';
  final generic = raw.isEmpty || raw.toLowerCase() == 'window';
  if (app.isEmpty) {
    return generic ? null : raw;
  }
  if (generic || raw.toLowerCase() == app.toLowerCase()) {
    return app;
  }
  return '$app — $raw';
}

/// One display, window, All-displays viewport, or system-picker stand-in.
final class ScreenSource {
  /// Creates a Screen source. Missing fields are null and unused.
  const ScreenSource({
    required this.id,
    required this.name,
    required this.kind,
    this.applicationName,
    this.x,
    this.y,
    this.width,
    this.height,
    this.canPreview = false,
  });

  /// Maps a native catalog row. Window sources get [windowShareLabel].
  factory ScreenSource.fromChannel(Map<dynamic, dynamic> item) {
    final kind = switch (item['kind'] as String?) {
      'window' => ScreenSourceKind.window,
      'allDisplays' => ScreenSourceKind.allDisplays,
      'systemPicker' => ScreenSourceKind.systemPicker,
      _ => ScreenSourceKind.display,
    };
    final applicationName = item['applicationName'] as String?;
    final rawName = item['name'] as String? ?? '';
    final name = kind == ScreenSourceKind.window
        ? (windowShareLabel(title: rawName, applicationName: applicationName) ??
              rawName)
        : rawName;
    return ScreenSource(
      id: item['id'] as String? ?? '',
      name: name,
      kind: kind,
      applicationName: applicationName,
      x: item['x'] as int?,
      y: item['y'] as int?,
      width: item['width'] as int?,
      height: item['height'] as int?,
      canPreview: item['canPreview'] == true,
    );
  }

  /// Maps a native catalog row. Windows with no shareable label are omitted.
  /// Cocoa's default title "Window" is an overlay, not a shareable source.
  static ScreenSource? tryFromChannel(Map<dynamic, dynamic> item) {
    if (item['kind'] == 'window') {
      final raw = (item['name'] as String?)?.trim() ?? '';
      if (raw.toLowerCase() == 'window') {
        return null;
      }
      if (windowShareLabel(
            title: raw,
            applicationName: item['applicationName'] as String?,
          ) ==
          null) {
        return null;
      }
    }
    return ScreenSource.fromChannel(item);
  }

  /// Maps a native catalog list. Generic untitled windows are omitted.
  static List<ScreenSource> listFromChannel(List<dynamic>? raw) {
    if (raw == null) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map)
          if (tryFromChannel(Map<dynamic, dynamic>.from(item))
              case final ScreenSource source)
            source,
    ];
  }

  /// Stable id for this catalog snapshot.
  final String id;

  /// Advertised name. Window sources include the owning application when known.
  final String name;

  /// Owning application for a window source, when known.
  final String? applicationName;

  /// Capture kind.
  final ScreenSourceKind kind;

  /// Physical origin x, when known.
  final int? x;

  /// Physical origin y, when known.
  final int? y;

  /// Physical pixel width, when known.
  final int? width;

  /// Physical pixel height, when known.
  final int? height;

  /// Whether Screen pick can yield a thumb for this source.
  final bool canPreview;

  @override
  bool operator ==(Object other) =>
      other is ScreenSource &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.applicationName == applicationName &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.canPreview == canPreview;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    applicationName,
    x,
    y,
    width,
    height,
    canPreview,
  );
}
