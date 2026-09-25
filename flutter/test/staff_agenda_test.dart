import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onboarding_flutter/staff_agenda.dart';
import 'package:onboarding_flutter/slot_model.dart';
import 'package:onboarding_flutter/planner_theme.dart';

void main() {
  final today = DateTime(2026, 9, 25);
  final slots = [
    WorkSlot(id: 'friday', date: today, start: 1020, end: 1320),
    WorkSlot(id: 'saturday', date: DateTime(2026, 9, 26), start: 660, end: 1020,
      breakMinutes: 30, role: 'Service', notes: 'Meet the shift lead'),
  ];
  for (final width in [390.0, 1440.0]) {
    testWidgets('staff schedule at $width supports selection and week browsing', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: plannerTheme(), home: Scaffold(
        body: StaffAgenda(name: 'Alex', slots: slots, today: today))));
      expect(find.textContaining('2 shifts'), findsOneWidget);
      expect(find.textContaining('10 h 30 min'), findsOneWidget);
      final saturday = find.byKey(const ValueKey('staff-overview-2026-09-26'));
      await tester.ensureVisible(saturday);
      await tester.tap(saturday);
      await tester.pumpAndSettle();
      expect(find.text('Meet the shift lead'), findsOneWidget);
      expect(find.text('30 min unpaid break'), findsOneWidget);
      final next = find.text('Next week');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.textContaining('0 shifts'), findsOneWidget);
      await tester.tap(find.text('This week'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 shifts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
