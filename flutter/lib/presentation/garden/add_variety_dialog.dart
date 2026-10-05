import 'package:flutter/material.dart';

import '../../domain/grow/crop.dart';
import '../theme.dart';
import '../widgets/panel.dart' show EmptyPanelText;

Future<(String, String)?> showAddVarietyDialog(
  BuildContext context, {
  required CropCatalog catalog,
}) => showDialog<(String, String)>(
  context: context,
  builder: (context) => _AddVarietyDialog(catalog: catalog),
);

/// Picks a named variety from the catalog.
class _AddVarietyDialog extends StatefulWidget {
  const _AddVarietyDialog({required this.catalog});

  final CropCatalog catalog;

  @override
  State<_AddVarietyDialog> createState() => _AddVarietyDialogState();
}

class _AddVarietyDialogState extends State<_AddVarietyDialog> {
  String _query = '';
  CatalogVariety? _selected;

  bool _matches(CatalogVariety variety) {
    final cropName = widget.catalog.nameOf(variety.cropId);
    final category = widget.catalog.categoryOf(variety.cropId);
    if (cropName == null || category == null) return false;
    final q = _query.trim().toLowerCase();
    return q.isEmpty ||
        variety.name.toLowerCase().contains(q) ||
        cropName.toLowerCase().contains(q) ||
        category.toLowerCase().contains(q);
  }

  void _submit() {
    if (_selected == null) return;
    Navigator.pop(context, (_selected!.cropId, _selected!.name));
  }

  @override
  Widget build(BuildContext context) {
    final varieties = widget.catalog.varieties.where(_matches).toList();
    return AlertDialog(
      title: const Text('Add variety'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search varieties or crops',
                prefixIcon: Icon(Icons.search, size: 18),
                prefixIconConstraints: BoxConstraints(minWidth: 34),
              ),
              onChanged: (v) => setState(() {
                _query = v;
                if (_selected != null && !_matches(_selected!)) {
                  _selected = null;
                }
              }),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 6),
            Expanded(
              // The border is painted over the rows, which have their own
              // fill, so it stays visible all the way round.
              child: Container(
                foregroundDecoration: BoxDecoration(
                  border: Border.all(color: Palette.panelBorder),
                  borderRadius: BorderRadius.circular(Metrics.radius),
                ),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Metrics.radius),
                ),
                child: varieties.isEmpty
                    ? const Center(child: EmptyPanelText('No varieties match.'))
                    : ListView.builder(
                        itemCount: varieties.length,
                        itemBuilder: (context, index) {
                          final variety = varieties[index];
                          final cropName = widget.catalog.nameOf(
                            variety.cropId,
                          )!;
                          return Material(
                            color: variety == _selected
                                ? Palette.wash
                                : Palette.paper,
                            child: InkWell(
                              onTap: () => setState(() => _selected = variety),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        variety.name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: variety == _selected
                                              ? Palette.accent
                                              : Palette.ink,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      cropName,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Palette.faint,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected == null ? null : _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
