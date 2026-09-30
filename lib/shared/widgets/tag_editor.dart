import 'package:flutter/material.dart';

import '../../core/database/keepit_database.dart';
import '../../core/database/repositories/tag_repository.dart';

/// Chip-based tag editor for any entity (purchases, belongings, ...).
///
/// Shows the entity's current tags as removable chips plus an "add" chip
/// that opens a sheet with suggestions, existing tags and a free-text field
/// for custom tags. All writes go through [TagRepository]; linking is
/// idempotent so double-taps are harmless.
class TagEditor extends StatefulWidget {
  const TagEditor({
    super.key,
    required this.tagRepository,
    required this.entityType,
    required this.entityId,
    this.suggestions = const [],
    this.onChanged,
  });

  final TagRepository tagRepository;
  final String entityType;
  final String entityId;

  /// Suggested tag names offered at the top of the picker.
  final List<String> suggestions;

  final VoidCallback? onChanged;

  @override
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  late Future<List<Tag>> _tagsFuture = _load();

  Future<List<Tag>> _load() => widget.tagRepository.tagsForEntity(
        entityType: widget.entityType,
        entityId: widget.entityId,
      );

  void _refresh() {
    setState(() => _tagsFuture = _load());
    widget.onChanged?.call();
  }

  Future<void> _addTag(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final tag = await widget.tagRepository.getOrCreate(trimmed);
    await widget.tagRepository.link(
      tagId: tag.id,
      entityType: widget.entityType,
      entityId: widget.entityId,
    );
    _refresh();
  }

  Future<void> _removeTag(Tag tag) async {
    await widget.tagRepository.unlink(
      tagId: tag.id,
      entityType: widget.entityType,
      entityId: widget.entityId,
    );
    _refresh();
  }

  Future<void> _openPicker() async {
    final current = await _tagsFuture;
    final currentIds = current.map((t) => t.id).toSet();
    final all = await widget.tagRepository.watchAll().first;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _TagPickerSheet(
        suggestions: widget.suggestions,
        allTags: all,
        currentIds: currentIds,
        onSelect: (name) async {
          await _addTag(name);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Tag>>(
      future: _tagsFuture,
      builder: (context, snapshot) {
        final tags = snapshot.data ?? const <Tag>[];
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final tag in tags)
              Chip(
                label: Text(tag.name),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _removeTag(tag),
                visualDensity: VisualDensity.compact,
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: Text(tags.isEmpty ? 'Add tags' : 'Add'),
              onPressed: _openPicker,
              visualDensity: VisualDensity.compact,
            ),
          ],
        );
      },
    );
  }
}

class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet({
    required this.suggestions,
    required this.allTags,
    required this.currentIds,
    required this.onSelect,
  });

  final List<String> suggestions;
  final List<Tag> allTags;
  final Set<String> currentIds;
  final Future<void> Function(String name) onSelect;

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existingNames =
        widget.allTags.map((t) => t.name.toLowerCase()).toSet();
    final freshSuggestions = widget.suggestions
        .where((s) => !existingNames.contains(s.toLowerCase()))
        .toList();
    final others = widget.allTags
        .where((t) => !widget.currentIds.contains(t.id))
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tags',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (freshSuggestions.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                children: [
                  for (final s in freshSuggestions)
                    ActionChip(
                      label: Text(s),
                      onPressed: () async {
                        await widget.onSelect(s);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (others.isNotEmpty) ...[
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final tag in others)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.label_outline),
                        title: Text(tag.name),
                        onTap: () async {
                          await widget.onSelect(tag.name);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: 'New tag',
                      hintText: 'e.g. Heirloom',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    await widget.onSelect(name);
    if (mounted) Navigator.of(context).pop();
  }
}
