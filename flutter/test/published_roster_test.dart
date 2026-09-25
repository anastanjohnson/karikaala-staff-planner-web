import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onboarding_flutter/planner_model.dart';
import 'package:onboarding_flutter/slot_model.dart';
import 'package:onboarding_flutter/published_roster.dart';
import 'package:onboarding_flutter/planner_theme.dart';

void main() {
  for (final width in [390.0, 1600.0]) {
    testWidgets('published snapshot and copy action at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final week = DateTime(2026, 9, 21);
      final plan = SlotPlan(staff: [const StaffMember(id: 'a', name: 'Alex')],
        slots: [WorkSlot(id: 'one', date: week, start: 960, end: 1320, staffId: 'a', notes: 'Open the terrace')])
        .publishWeek(week, week);
      final snapshot = plan.published[dateKey(week)]!;
      var copies = 0;
      await tester.pumpWidget(MaterialApp(theme: plannerTheme(), home: Scaffold(
        body: PublishedRosterOverview(publication: snapshot, onCopy: () => copies++, hasDraft: true))));
      expect(find.text('Alex'), findsOneWidget);
      expect(find.textContaining('Draft changes have not been published'), findsOneWidget);
      expect(find.text('Restaurant closed'), findsNWidgets(2));
      expect(find.text('Note: Open the terrace'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('copy-roster')));
      expect(copies, 1);
      expect(find.byType(Switch), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
