import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/grow/day.dart';
import 'package:garden_gnome/presentation/garden/timeline_view.dart';

void main() {
  test('zooming keeps the day under the pointer in place', () {
    const view = TimelineView(start: 0, days: 120);
    final out = view.zoomed(2, 0.25);
    expect(out.days, 240);
    expect(out.start + 0.25 * out.days, 30, reason: 'day 30 stays put');
    final back = out.zoomed(0.5, 0.25);
    expect(back, view);
  });

  test('zoom stops at two weeks and about three years', () {
    const view = TimelineView(start: 0, days: 120);
    expect(view.zoomed(0.001, 0.5).days, TimelineView.minDays);
    expect(view.zoomed(1000, 0.5).days, TimelineView.maxDays);
  });

  test('panning moves by a share of the span; the window covers part days', () {
    const view = TimelineView(start: 0, days: 100);
    expect(view.panned(0.5).start, 50);
    final home = DateTime.utc(2026, 1, 1);
    final w = const TimelineView(start: 10.5, days: 20).window(home);
    expect(w.start, addDays(home, 10));
    expect(w.end, addDays(home, 30));
  });
}
