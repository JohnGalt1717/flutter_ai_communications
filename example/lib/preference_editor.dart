import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';

/// Host Endpoint preference editor for the example harness.
///
/// Complete hardware Pairs are prefilled. Unpaired renders need a capture
/// chip before they become a persisted row. Unpaired captures are chips only.
final class PreferenceEditor extends StatelessWidget {
  /// Creates the editor.
  const PreferenceEditor({
    super.key,
    required this.catalog,
    required this.draft,
    required this.onChanged,
    required this.onApply,
    required this.onReset,
    this.onUseCurrent,
  });

  /// Live Endpoint catalog.
  final List<Endpoint> catalog;

  /// Draft Endpoint preference. Empty means platform default on next start.
  final EndpointPreference draft;

  /// Draft changed.
  final ValueChanged<EndpointPreference> onChanged;

  /// Persist the draft via [CommunicationsManager.bindPreference].
  final VoidCallback onApply;

  /// Clear the draft back to empty (platform default).
  final VoidCallback onReset;

  /// Apply Explicit selection to the live Desired Pair.
  final VoidCallback? onUseCurrent;

  @override
  Widget build(BuildContext context) {
    final groups = EndpointCatalogGroups.of(catalog);
    final captures = catalog.where((endpoint) => endpoint.isCapture).toList();
    final catalogRenders = [
      for (final pair in groups.completePairs) pair.render!,
      ...groups.unpairedRenders,
    ];
    final inDraft = [
      for (final entry in _effectiveEntries())
        catalog.where((item) => item.id == entry.renderId).firstOrNull,
    ].whereType<Endpoint>().toList();
    final rest = catalogRenders.where(
      (render) => inDraft.every((item) => item.id != render.id),
    );
    final renders = [...inDraft, ...rest];
    return Column(
      key: const Key('preference-editor'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Endpoint preference',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Output rows, then input chips. Apply binds the list. Use current '
          'applies Explicit selection to the live combination.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text('${draft.entries.length}', key: const Key('pref-bound-count')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              key: const Key('pref-apply'),
              onPressed: onApply,
              child: const Text('Apply preference'),
            ),
            OutlinedButton(
              key: const Key('pref-reset'),
              onPressed: onReset,
              child: const Text('Reset'),
            ),
            OutlinedButton(
              key: const Key('pref-use-current'),
              onPressed: onUseCurrent,
              child: const Text('Use current'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final render in renders)
          _row(
            context,
            render: render,
            captures: captures,
            complete: groups.completePairs.any(
              (pair) => pair.render?.id == render.id,
            ),
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required Endpoint render,
    required List<Endpoint> captures,
    required bool complete,
  }) {
    final effective = _effectiveEntries();
    final effectiveIndex = effective.indexWhere(
      (item) => item.renderId == render.id,
    );
    final entry = effectiveIndex < 0 ? null : effective[effectiveIndex];
    return Card(
      key: Key('pref-row-${render.id}'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Switch(
                  key: Key('pref-row-enable-${render.id}'),
                  value: entry?.enabled ?? false,
                  onChanged: (enabled) =>
                      _setEnabled(render, enabled, complete),
                ),
                Expanded(
                  child: Text(
                    '${render.name} · ${complete ? 'Pair' : 'unpaired'}',
                  ),
                ),
                IconButton(
                  key: Key('pref-row-up-${render.id}'),
                  onPressed: effectiveIndex <= 0
                      ? null
                      : () => _move(render.id, -1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  key: Key('pref-row-down-${render.id}'),
                  onPressed:
                      effectiveIndex < 0 ||
                          effectiveIndex == effective.length - 1
                      ? null
                      : () => _move(render.id, 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final capture in captures)
                  FilterChip(
                    key: Key('pref-capture-${render.id}-${capture.id}'),
                    label: Text(capture.name),
                    selected:
                        entry?.captures.any((slot) => slot.id == capture.id) ??
                        false,
                    onSelected: (_) => _toggleCapture(render.id, capture.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _setEnabled(Endpoint render, bool enabled, bool complete) {
    final entries = _editableEntries();
    final index = entries.indexWhere((item) => item.renderId == render.id);
    if (index < 0) {
      if (!enabled) {
        return;
      }
      final mate = catalog
          .where((item) => item.pairId == render.pairId && item.isCapture)
          .firstOrNull;
      if (mate == null && !complete) {
        return;
      }
      entries.add(
        EndpointPreferenceEntry(
          renderId: render.id,
          captures: [if (mate != null) EndpointPreferenceCapture(id: mate.id)],
        ),
      );
      onChanged(EndpointPreference(entries: entries));
      return;
    }
    entries[index] = EndpointPreferenceEntry(
      renderId: entries[index].renderId,
      enabled: enabled,
      captures: entries[index].captures,
    );
    onChanged(EndpointPreference(entries: entries));
  }

  List<EndpointPreferenceEntry> _effectiveEntries() {
    if (draft.entries.isNotEmpty) {
      return draft.entries;
    }
    return EndpointPreference.platformDefault(catalog).entries;
  }

  List<EndpointPreferenceEntry> _editableEntries() => [..._effectiveEntries()];

  void _toggleCapture(String renderId, String captureId) {
    final entries = _editableEntries();
    final index = entries.indexWhere((item) => item.renderId == renderId);
    if (index < 0) {
      entries.add(
        EndpointPreferenceEntry(
          renderId: renderId,
          captures: [EndpointPreferenceCapture(id: captureId)],
        ),
      );
      onChanged(EndpointPreference(entries: entries));
      return;
    }
    final slots = [...entries[index].captures];
    final slotIndex = slots.indexWhere((slot) => slot.id == captureId);
    if (slotIndex < 0) {
      slots.add(EndpointPreferenceCapture(id: captureId));
    } else {
      slots.removeAt(slotIndex);
    }
    if (slots.isEmpty) {
      entries.removeAt(index);
    } else {
      entries[index] = EndpointPreferenceEntry(
        renderId: renderId,
        enabled: entries[index].enabled,
        captures: slots,
      );
    }
    onChanged(EndpointPreference(entries: entries));
  }

  void _move(String renderId, int delta) {
    final entries = _editableEntries();
    final index = entries.indexWhere((item) => item.renderId == renderId);
    final next = index + delta;
    if (index < 0 || next < 0 || next >= entries.length) {
      return;
    }
    final row = entries.removeAt(index);
    entries.insert(next, row);
    onChanged(EndpointPreference(entries: entries));
  }
}
