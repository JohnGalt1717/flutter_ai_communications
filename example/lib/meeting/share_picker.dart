import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';

import 'chrome.dart';
import 'video_surface_view.dart';

/// Share picker: display tiles, then application windows as a list.
final class SharePicker extends StatelessWidget {
  /// Creates the Share picker.
  const SharePicker({
    super.key,
    required this.sources,
    required this.includeSound,
    required this.motion,
    required this.cursor,
    required this.onIncludeSound,
    required this.onMotion,
    required this.onCursor,
    required this.onPick,
    this.indicatedId,
    this.previewBuilder,
  });

  /// Screen source catalog.
  final List<ScreenSource> sources;

  /// Include system audio.
  final bool includeSound;

  /// Motion / optimize.
  final bool motion;

  /// Include cursor.
  final bool cursor;

  /// Indicated Screen source id.
  final String? indicatedId;

  /// Sound chip.
  final ValueChanged<bool> onIncludeSound;

  /// Motion chip.
  final ValueChanged<bool> onMotion;

  /// Cursor chip.
  final ValueChanged<bool> onCursor;

  /// Pick a source and start share.
  final ValueChanged<String> onPick;

  /// Optional live thumb for a source.
  final Widget? Function(ScreenSource source)? previewBuilder;

  @override
  Widget build(BuildContext context) {
    final screens = [
      for (final source in sources)
        if (source.kind == ScreenSourceKind.display ||
            source.kind == ScreenSourceKind.allDisplays)
          source,
    ];
    final apps = [
      for (final source in sources)
        if (source.kind == ScreenSourceKind.window) source,
    ];
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      key: const Key('share-picker'),
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  key: const Key('screen-sound'),
                  label: const Text('Include sound'),
                  selected: includeSound,
                  onSelected: onIncludeSound,
                ),
                FilterChip(
                  key: const Key('screen-motion'),
                  label: const Text('Optimize'),
                  selected: motion,
                  onSelected: onMotion,
                ),
                FilterChip(
                  key: const Key('screen-cursor'),
                  label: const Text('Cursor'),
                  selected: cursor,
                  onSelected: onCursor,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Screens', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            if (screens.isEmpty)
              Text('No screens', style: textTheme.bodySmall)
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final source in screens) _screenTile(context, source),
                ],
              ),
            const SizedBox(height: 20),
            Text('Apps', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            if (apps.isEmpty)
              Text('No apps', style: textTheme.bodySmall)
            else
              for (final source in apps) _appTile(source),
          ],
        ),
      ),
    );
  }

  Widget _screenTile(BuildContext context, ScreenSource source) {
    final selected = source.id == indicatedId;
    final preview = previewBuilder?.call(source);
    return SizedBox(
      width: 160,
      child: Material(
        color: MeetingChrome.button,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('screen-source-${source.id}'),
          onTap: () => onPick(source.id),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: MeetingChrome.background,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected
                            ? MeetingChrome.buttonActive
                            : MeetingChrome.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child:
                          preview ??
                          Center(
                            child: Icon(
                              source.kind == ScreenSourceKind.allDisplays
                                  ? Icons.desktop_windows
                                  : Icons.monitor,
                              color: MeetingChrome.dim,
                            ),
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  source.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _appTile(ScreenSource source) {
    final preview = previewBuilder?.call(source);
    return ListTile(
      key: Key('screen-source-${source.id}'),
      leading: SizedBox(
        width: 72,
        height: 40,
        child:
            preview ??
            const ColoredBox(
              color: MeetingChrome.background,
              child: Icon(Icons.window, color: MeetingChrome.dim, size: 20),
            ),
      ),
      title: Text(source.name),
      subtitle: Text(
        source.applicationName ??
            '${source.kind.name}'
                '${source.width != null ? ' · ${source.width}x${source.height}' : ''}',
      ),
      selected: source.id == indicatedId,
      onTap: () => onPick(source.id),
    );
  }
}

/// Thumb for a Screen source preview surface.
Widget? screenPreviewThumb(Session? session, ScreenSource source) {
  if (session == null) {
    return null;
  }
  final preview = session.screenPreview(source.id);
  if (preview == null) {
    return null;
  }
  return VideoSurfaceView(
    key: Key('screen-preview-${source.id}'),
    surface: preview,
    viewTypePrefix: 'fac-screen',
  );
}
