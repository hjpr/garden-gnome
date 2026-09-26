import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

/// An icon from assets/icons, tinted to the text colour.
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {super.key, this.size = 20, this.color});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/$name',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color ?? Palette.ink, BlendMode.srcIn),
  );
}

/// A small square icon button with a tooltip.
///
/// Shows either an SVG from assets/icons ([icon]) or a Material icon
/// ([iconData]). [selected] gives it the accent wash, for toggles.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    this.icon,
    this.iconData,
    required this.label,
    required this.onPressed,
    this.size = 28,
    this.tooltip,
    this.selected = false,
  }) : assert(icon != null || iconData != null);

  final String? icon;
  final IconData? iconData;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colour = onPressed == null
        ? Palette.faint
        : (selected ? Palette.accent : Palette.ink);
    return Tooltip(
      message: tooltip ?? label,
      child: Semantics(
        label: label,
        button: true,
        selected: selected,
        child: Material(
          color: selected ? Palette.wash : Colors.transparent,
          borderRadius: BorderRadius.circular(Metrics.radius),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(Metrics.radius),
            hoverColor: Palette.hover,
            child: SizedBox.square(
              dimension: size,
              child: Center(
                child: icon != null
                    ? AppIcon(icon!, size: 16, color: colour)
                    : Icon(iconData, size: 17, color: colour),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A panel inside a dock: a heading that folds the body away, a grip for
/// dragging the panel to a new place in the dock, and the body.
///
/// Must be built inside the dock's reorderable list; [index] is its
/// position there.
class DockPanel extends StatelessWidget {
  const DockPanel({
    super.key,
    required this.index,
    required this.title,
    required this.expanded,
    required this.onExpandedChanged,
    required this.child,
    this.subtitle,
    this.footer,
  });

  final int index;
  final String title;

  /// Shown after the title in a lighter style, e.g. the selected layer kind.
  final String? subtitle;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final Widget child;

  /// A strip under the body for actions, such as Add layer buttons.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Palette.paper,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Palette.panelBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading(),
                if (expanded) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                    child: child,
                  ),
                  if (footer != null) ...[const Divider(), footer!],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading() {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Tooltip(
                message: 'Drag to reorder',
                child: Semantics(
                  label: 'Reorder $title',
                  child: const SizedBox(
                    width: 22,
                    height: 34,
                    child: Icon(
                      Icons.drag_indicator,
                      size: 14,
                      color: Palette.faint,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              button: true,
              expanded: expanded,
              label: '${expanded ? 'Collapse' : 'Expand'} $title',
              child: InkWell(
                onTap: () => onExpandedChanged(!expanded),
                hoverColor: Palette.hover,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: title.toUpperCase(),
                            children: [
                              if (subtitle != null)
                                TextSpan(
                                  text: '  $subtitle',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 0,
                                    color: Palette.faint,
                                  ),
                                ),
                            ],
                          ),
                          overflow: TextOverflow.ellipsis,
                          style: sectionTitleStyle.copyWith(color: Palette.ink),
                        ),
                      ),
                      AnimatedRotation(
                        turns: expanded ? 0 : -0.25,
                        duration: const Duration(milliseconds: 160),
                        child: const Icon(
                          Icons.expand_more,
                          size: 18,
                          color: Palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The greyed, centred line a panel shows when it has nothing to show.
class EmptyPanelText extends StatelessWidget {
  const EmptyPanelText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 12.5,
        fontStyle: FontStyle.italic,
        color: Palette.faint,
      ),
    ),
  );
}

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
