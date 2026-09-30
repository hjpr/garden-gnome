import 'package:flutter/material.dart';

import '../theme.dart';

/// A titled group of controls inside a panel.
class PropertyGroup extends StatelessWidget {
  const PropertyGroup({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Semantics(
            header: true,
            child: Text(title, style: sectionTitleStyle),
          ),
        ),
        ...children,
      ],
    ),
  );
}

/// A label on the left and a control on the right.
class PropertyRow extends StatelessWidget {
  const PropertyRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: Palette.muted),
            ),
          ),
        ),
        Expanded(flex: 3, child: child),
      ],
    ),
  );
}

/// A compact dropdown that fits a property row.
class CompactDropdown<T> extends StatelessWidget {
  const CompactDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.label,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> items;
  final String label;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: DropdownButtonFormField<T>(
      // Rebuild when the stored value changes elsewhere, e.g. after Undo.
      key: ValueKey(value),
      initialValue: value,
      isDense: true,
      isExpanded: true,
      iconSize: 18,
      borderRadius: BorderRadius.circular(Metrics.radius),
      dropdownColor: Palette.paper,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      style: const TextStyle(fontSize: 13, color: Palette.ink),
      items: [
        for (final entry in items.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(
              entry.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged == null ? null : (v) => onChanged!(v as T),
    ),
  );
}
