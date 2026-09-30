import 'package:flutter/material.dart';

import '../theme.dart';

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
