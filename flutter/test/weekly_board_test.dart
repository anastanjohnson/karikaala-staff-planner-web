import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onboarding_flutter/planner_model.dart';
import 'package:onboarding_flutter/slot_model.dart';
import 'package:onboarding_flutter/weekly_board.dart';

void main() {
  final week = DateTime(2026, 9, 21);
  final open = WorkSlot(id: 'open', date: week, start: 600, end: 960);
  final assigned = WorkSlot(id: 'assigned', date: week, start: 960, end: 1200, staffId: 'a');
  final plan = SlotPlan(staff: [const StaffMember(id: 'a', name: 'Alex')], slots: [open, assigned]);

  testWidgets('wide board shows seven chronological days and routes actions to the existing planner', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WorkSlot? picked;
    DateTime? added;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WeeklyBoard(
      plan: plan, week: week, onPick: (s) => picked = s, onAdd: (d) => added = d,
      onPublish: () {}, onRevise: () {}, onTemplate: () {}))));
    for (var i = 0; i < 7; i++) {
      expect(find.byKey(ValueKey('board-day-${dateKey(addDays(week, i))}')), findsOneWidget);
    }
    expect(find.text('Closed'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('board-slot-open')));
    expect(picked, open);
    await tester.tap(find.byKey(const ValueKey('board-add-2026-09-21')));
    expect(added, week);
    await tester.tap(find.text('Open shifts only'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-slot-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-slot-assigned')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('published board disables edits and permits creating a new draft', (tester) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final locked = SlotPlan(staff: plan.staff, slots: [assigned]).publishWeek(week, week);
    var picked = false, revised = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WeeklyBoard(
      plan: locked, week: week, onPick: (_) => picked = true, onAdd: (_) {},
      onPublish: () {}, onRevise: () => revised = true, onTemplate: () {}))));
    expect(find.text('Add shift'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('board-slot-assigned')));
    expect(picked, isFalse);
    await tester.tap(find.text('Create draft'));
    expect(revised, isTrue);
    expect(tester.takeException(), isNull);
  });
}
