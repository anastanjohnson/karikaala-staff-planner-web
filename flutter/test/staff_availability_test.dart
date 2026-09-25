import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onboarding_flutter/planner_model.dart';
import 'package:onboarding_flutter/slot_model.dart';
import 'package:onboarding_flutter/staff_availability.dart';
import 'package:onboarding_flutter/planner_theme.dart';

void main() {
  for (final width in [390.0, 1600.0]) {
    testWidgets('availability selection and saving at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var plan = SlotPlan(staff: [const StaffMember(id: 'alex', name: 'Alex')], slots: []);
      var saves = 0;
      await tester.pumpWidget(MaterialApp(theme: plannerTheme(), home: Scaffold(
        body: StaffAvailabilityPanel(getPlan: () => plan, onSave: (next) async { plan = next; saves++; },
          onEdit: (_) async {}, today: DateTime(2026, 9, 25), resetToken: 0))));
      final date = find.byKey(const ValueKey('calendar-day-2026-09-25'));
      await tester.ensureVisible(date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      expect(find.text('Friday, 25 September 2026'), findsOneWidget);
      final toggle = find.byType(SwitchListTile).first;
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(plan.hasTimeOff('alex', DateTime(2026, 9, 25)), isTrue);
      final restore = find.byKey(const ValueKey('available-all-day'));
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(plan.hasTimeOff('alex', DateTime(2026, 9, 25)), isFalse);
      final next = find.byKey(const ValueKey('calendar-next-month'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
