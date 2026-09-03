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

/// One display, window, All-displays viewport, or system-picker stand-in.
final class ScreenSource {
  /// Creates a Screen source. Missing fields are null and unused.
  const ScreenSource({
    required this.id,
    required this.name,
    required this.kind,
    this.x,
    this.y,
    this.width,
    this.height,
    this.canPreview = false,
  });

  /// Stable id for this catalog snapshot.
  final String id;

  /// Advertised name.
  final String name;

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
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.canPreview == canPreview;

  @override
  int get hashCode =>
      Object.hash(id, name, kind, x, y, width, height, canPreview);
}
