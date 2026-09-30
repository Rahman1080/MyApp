import 'package:flutter/material.dart';

import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/category_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../domain/smart_organization_service.dart';

/// Phase 18 UI — Smart Organization.
///
/// Detect → Suggest → Review → Confirm workflow:
/// 1. The app scans the inventory and detects opportunities
///    (missing location, category, value, possible duplicates).
/// 2. Each suggestion is shown for review.
/// 3. The user accepts or dismisses each one.
/// 4. Accepted suggestions are applied only after explicit confirmation.
///
/// Nothing is changed without the user's explicit approval.
class OrganizeScreen extends StatefulWidget {
  const OrganizeScreen({
    super.key,
    required this.organizationService,
    required this.belongingRepository,
    required this.locationRepository,
    required this.categoryRepository,
  });

  static const routePath = '/organize';

  final SmartOrganizationService organizationService;
  final BelongingRepository belongingRepository;
  final LocationRepository locationRepository;
  final CategoryRepository categoryRepository;

  @override
  State<OrganizeScreen> createState() => _OrganizeScreenState();
}

class _OrganizeScreenState extends State<OrganizeScreen> {
  List<OrganizationSuggestion> _suggestions = [];
  bool _loading = true;
  bool _applying = false;
  final Map<String, String> _itemNames = {};

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    setState(() => _loading = true);
    try {
      final suggestions =
          await widget.organizationService.detectSuggestions();
      final names = <String, String>{};
      for (final s in suggestions) {
        for (final id in s.belongingIds.take(10)) {
          final b = await widget.belongingRepository.getById(id);
          if (b != null) names[id] = b.name;
        }
      }
      if (!mounted) return;
      setState(() {
        _suggestions = suggestions;
        _itemNames.addAll(names);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _update(OrganizationSuggestion updated) {
    setState(() {
      _suggestions = _suggestions
          .map((s) => s.id == updated.id ? updated : s)
          .toList();
    });
  }

  Future<void> _accept(OrganizationSuggestion suggestion) async {
    // Suggestions that need user input get a picker; others apply directly.
    switch (suggestion.type) {
      case SuggestionType.missingLocation:
        final locationId = await _pickLocation();
        if (locationId == null || !mounted) return;
        await _apply(suggestion, {'locationId': locationId});
        break;
      case SuggestionType.missingCategory:
        final categoryId = await _pickCategory();
        if (categoryId == null || !mounted) return;
        await _apply(suggestion, {'categoryId': categoryId});
        break;
      case SuggestionType.missingValue:
      case SuggestionType.missingTags:
      case SuggestionType.possibleDuplicate:
        // No safe automatic fix — mark as reviewed so it stops showing.
        _update(suggestion.copyWith(status: SuggestionStatus.accepted));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Marked as reviewed. Edit the items directly to fix them.',
              ),
            ),
          );
        }
        break;
    }
  }

  Future<void> _apply(
    OrganizationSuggestion suggestion,
    Map<String, dynamic> action,
  ) async {
    setState(() => _applying = true);
    try {
      await widget.organizationService.applySuggestion(
        suggestion.copyWith(status: SuggestionStatus.accepted),
        action,
      );
      _update(suggestion.copyWith(status: SuggestionStatus.applied));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Applied to ${suggestion.belongingIds.length} item(s).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not apply: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<String?> _pickLocation() async {
    final locations = await widget.locationRepository.getAll();
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a location'),
        children: locations
            .map(
              (l) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, l.id),
                child: Text(l.name),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<String?> _pickCategory() async {
    final categories = await widget.categoryRepository.getAll();
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a category'),
        children: categories
            .map(
              (c) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, c.id),
                child: Text(c.name),
              ),
            )
            .toList(),
      ),
    );
  }

  IconData _iconFor(SuggestionType type) {
    switch (type) {
      case SuggestionType.missingLocation:
        return Icons.place_outlined;
      case SuggestionType.missingCategory:
        return Icons.label_outline;
      case SuggestionType.missingValue:
        return Icons.attach_money;
      case SuggestionType.possibleDuplicate:
        return Icons.content_copy_outlined;
      case SuggestionType.missingTags:
        return Icons.tag_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Organization'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-scan',
            onPressed: _loading ? null : _detect,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _suggestions.isEmpty
              ? _buildAllGood()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _suggestions.length,
                  itemBuilder: (context, i) =>
                      _buildCard(_suggestions[i]),
                ),
    );
  }

  Widget _buildAllGood() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Everything looks organized!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'No suggestions right now. Add more items or check back later.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(OrganizationSuggestion suggestion) {
    final done = suggestion.status == SuggestionStatus.applied ||
        suggestion.status == SuggestionStatus.rejected ||
        suggestion.status == SuggestionStatus.accepted;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(suggestion.type)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    suggestion.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (done)
                  const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(suggestion.description),
            if (suggestion.belongingIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: suggestion.belongingIds.take(5).map((id) {
                  return Chip(
                    label: Text(
                      _itemNames[id] ?? 'Item',
                      style: const TextStyle(fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
            if (!done) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _applying
                        ? null
                        : () => _update(suggestion.copyWith(
                              status: SuggestionStatus.rejected,
                            )),
                    child: const Text('Dismiss'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _applying ? null : () => _accept(suggestion),
                    child: _applying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Review & apply'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
