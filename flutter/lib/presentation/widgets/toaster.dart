import 'package:flutter/material.dart';

import '../../application/toasts.dart';
import '../../application/workspace_settings.dart';
import '../theme.dart';

/// Shows a [ToastCenter]'s toasts as a Sonner-style stack at the top or
/// bottom centre of the window.
///
/// The newest toast sits in front; up to two older ones peek out behind
/// it, smaller. Pointing at the stack fans it out so every toast can be
/// read, and holds them until the pointer leaves.
class Toaster extends StatefulWidget {
  const Toaster({super.key, required this.toasts, required this.position});

  final ToastCenter toasts;
  final ToastPosition position;

  /// Distance from the window edge, clear of the header and status bar.
  static const double edgeGap = Metrics.headerHeight + 12;

  @override
  State<Toaster> createState() => _ToasterState();
}

class _ToasterState extends State<Toaster> {
  static const double _width = 356;
  static const double _gap = 8;

  /// How far each older toast peeks out behind the one in front.
  static const double _peek = 10;
  static const int _visibleBehind = 2;
  static const _duration = Duration(milliseconds: 320);
  static const _curve = Curves.easeOutCubic;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.toasts,
    builder: (context, _) {
      final toasts = widget.toasts.toasts;
      if (toasts.isEmpty) {
        _expanded = false;
        return const SizedBox.shrink();
      }
      final top = widget.position == ToastPosition.top;
      final heights = [for (final t in toasts) _ToastCard.heightFor(t, _width)];
      final newestFirst = List.generate(
        toasts.length,
        (i) => toasts.length - 1 - i,
      );
      final frontHeight = heights.last;

      // Where each toast sits, measured inward from the window edge.
      final offsets = <int, double>{};
      var travelled = 0.0;
      for (final (depth, index) in newestFirst.indexed) {
        offsets[index] = _expanded ? travelled : depth * _peek;
        travelled += heights[index] + _gap;
      }
      final stackHeight = _expanded
          ? travelled - _gap
          : frontHeight + _peek * (toasts.length - 1).clamp(0, _visibleBehind);

      return Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
            top: top ? Toaster.edgeGap : 0,
            bottom: top ? 0 : Metrics.statusHeight + 16,
          ),
          child: MouseRegion(
            onEnter: (_) {
              widget.toasts.pause();
              setState(() => _expanded = true);
            },
            onExit: (_) {
              widget.toasts.resume();
              setState(() => _expanded = false);
            },
            child: AnimatedContainer(
              duration: _duration,
              curve: _curve,
              width: _width,
              height: stackHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Oldest first, so the newest is painted in front.
                  for (final (index, toast) in toasts.indexed)
                    _placed(
                      toast,
                      depth: toasts.length - 1 - index,
                      offset: offsets[index]!,
                      // Collapsed, the ones behind take the front one's
                      // height so only their edge shows.
                      height: _expanded ? heights[index] : frontHeight,
                      top: top,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _placed(
    Toast toast, {
    required int depth,
    required double offset,
    required double height,
    required bool top,
  }) {
    final hidden = !_expanded && depth > _visibleBehind;
    return AnimatedPositioned(
      key: ValueKey(toast.id),
      duration: _duration,
      curve: _curve,
      left: 0,
      right: 0,
      top: top ? offset : null,
      bottom: top ? null : offset,
      height: height,
      child: AnimatedScale(
        duration: _duration,
        curve: _curve,
        alignment: top ? Alignment.bottomCenter : Alignment.topCenter,
        scale: _expanded ? 1 : 1 - 0.05 * depth,
        child: AnimatedOpacity(
          duration: _duration,
          opacity: hidden ? 0 : 1,
          child: _Arrival(
            fromTop: top,
            child: _ToastCard(
              toast: toast,
              // Text of toasts tucked behind stays hidden until fanned out.
              showContent: _expanded || depth == 0,
              onClose: () => widget.toasts.dismiss(toast.id),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slides and fades a new toast in from the window edge.
class _Arrival extends StatelessWidget {
  const _Arrival({required this.fromTop, required this.child});

  final bool fromTop;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 360),
    curve: Curves.easeOutCubic,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * (fromTop ? -24 : 24)),
        child: child,
      ),
    ),
    child: child,
  );
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({
    required this.toast,
    required this.showContent,
    required this.onClose,
  });

  final Toast toast;
  final bool showContent;
  final VoidCallback onClose;

  static const _padding = EdgeInsets.fromLTRB(14, 12, 8, 12);
  static const _iconSize = 18.0;
  static const _textStyle = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: Palette.ink,
  );

  /// Room the icon, its spacing and the close button take from a row.
  static const _besideText = _iconSize + 10 + 28;

  /// The card's height for [toast] at [width], worked out ahead of layout
  /// so the stack can place every card without measuring.
  static double heightFor(Toast toast, double width) {
    final painter = TextPainter(
      text: TextSpan(text: toast.message, style: _textStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - _padding.horizontal - _besideText);
    final height = painter.height;
    painter.dispose();
    return _padding.vertical + (height < 22 ? 22 : height);
  }

  (IconData, Color) get _icon => switch (toast.kind) {
    ToastKind.error => (Icons.error, Palette.invalid),
    ToastKind.success => (Icons.check_circle, Palette.valid),
    ToastKind.info => (Icons.info, Palette.muted),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = _icon;
    final error = toast.kind == ToastKind.error;
    return Semantics(
      liveRegion: true,
      label: toast.message,
      child: Material(
        color: error ? const Color(0xFFFFF5F5) : Palette.paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: error ? const Color(0xFFF6D3D3) : Palette.panelBorder,
          ),
        ),
        shadowColor: Colors.black,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: showContent ? 1 : 0,
            child: Padding(
              padding: _padding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(icon, size: _iconSize, color: colour),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      toast.message,
                      style: error
                          ? _textStyle.copyWith(color: const Color(0xFF8E1F1F))
                          : _textStyle,
                    ),
                  ),
                  SizedBox.square(
                    dimension: 22,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      tooltip: 'Dismiss',
                      onPressed: onClose,
                      icon: const Icon(Icons.close, color: Palette.faint),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
