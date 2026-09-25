import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'planner_model.dart';
import 'planner_theme.dart';
import 'slot_model.dart';

/// Wide-screen presentation of the same slots and actions used on mobile.
class WeeklyBoard extends StatefulWidget {
  const WeeklyBoard({super.key, required this.plan, required this.week,
    required this.onPick, required this.onAdd, required this.onPublish,
    required this.onRevise, required this.onTemplate, this.error});
  final SlotPlan plan;
  final DateTime week;
  final ValueChanged<WorkSlot> onPick;
  final ValueChanged<DateTime> onAdd;
  final VoidCallback onPublish, onRevise, onTemplate;
  final String? error;
  @override
  State<WeeklyBoard> createState() => _WeeklyBoardState();
}

class _WeeklyBoardState extends State<WeeklyBoard> {
  bool _openOnly = false;
  final _scroll = ScrollController();
  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final slots = plan.inWeek(widget.week);
    final assigned = slots.where((s) => s.staffId != null).length;
    final locked = plan.locked(widget.week);
    final problem = plan.publishProblem(widget.week);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${locked ? 'Published' : 'Weekly draft'} · $assigned/${slots.length} assigned · ${slots.length - assigned} open',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          FilterChip(visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, labelStyle: const TextStyle(fontSize: 11), label: const Text('Open shifts only'), selected: _openOnly,
            onSelected: (value) => setState(() => _openOnly = value)),
          if (locked) OutlinedButton(style: _compactButton, onPressed: widget.onRevise, child: const Text('Create draft'))
          else Tooltip(message: problem ?? 'Publish this week to staff', child: FilledButton(style: _compactButton,
            onPressed: slots.isNotEmpty && problem == null ? widget.onPublish : null,
            child: Text(plan.published.containsKey(dateKey(widget.week)) ? 'Republish' : 'Publish'))),
          if (!locked && slots.isEmpty) TextButton(style: _compactButton, onPressed: widget.onTemplate, child: const Text('Use standard template')),
        ]),
        if (widget.error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(widget.error!, style: const TextStyle(color: Colors.red))),
        const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text(
          'Select a shift to assign staff or edit its details. Each day scrolls independently.',
          style: TextStyle(color: rosterMuted, fontSize: 12))),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final width = math.max(1100.0, constraints.maxWidth);
          final days = List.generate(7, (i) => addDays(widget.week, i));
          // A closed day with existing slots must still expose those shifts.
          final compact = days.where((d) => restaurantClosed(d) && !slots.any((s) => dateKey(s.date) == dateKey(d))).length;
          final dayWidth = (width - 6 * 6 - compact * 68) / (7 - compact);
          return Scrollbar(controller: _scroll, thumbVisibility: width > constraints.maxWidth,
            child: SingleChildScrollView(controller: _scroll, scrollDirection: Axis.horizontal,
              child: SizedBox(width: width, height: constraints.maxHeight - 12,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    SizedBox(width: restaurantClosed(days[i]) && !slots.any((s) => dateKey(s.date) == dateKey(days[i])) ? 68 : dayWidth,
                      child: _day(days[i], slots, locked)),
                  ],
                ]))));
        })),
      ]),
    );
  }

  Widget _day(DateTime date, List<WorkSlot> all, bool locked) {
    final entries = all.where((s) => dateKey(s.date) == dateKey(date)).toList()
      ..sort((a, b) { final order = a.start.compareTo(b.start); return order == 0 ? a.id.compareTo(b.id) : order; });
    final closed = restaurantClosed(date);
    final visible = entries.where((s) => !_openOnly || s.staffId == null).toList();
    final assigned = entries.where((s) => s.staffId != null).length;
    return Container(key: ValueKey('board-day-${dateKey(date)}'),
      decoration: BoxDecoration(color: closed ? const Color(0xFFF7F7F7) : Colors.white,
        border: Border.all(color: rosterLine), borderRadius: BorderRadius.circular(6)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (closed && entries.isEmpty) ...[
            Text(dayNames[date.weekday - 1].substring(0, 3), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            Text('${date.day}/${date.month}', style: const TextStyle(color: rosterMuted, fontSize: 10)),
            const Text('Closed', style: TextStyle(color: rosterMuted, fontSize: 10)),
          ] else ...[
            Row(children: [
              Text(dayNames[date.weekday - 1].substring(0, 3), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(width: 6),
              Text('${date.day}/${date.month}', style: const TextStyle(color: rosterMuted, fontSize: 10)),
              const Spacer(),
              Text('$assigned/${entries.length}', style: const TextStyle(color: rosterMuted, fontSize: 10)),
            ]),
            const SizedBox(height: 5),
            LinearProgressIndicator(minHeight: 2, value: entries.isEmpty ? 0 : assigned / entries.length, color: const Color(0xFF24573D)),
          ],
        ])),
        const Divider(height: 1),
        Flexible(fit: FlexFit.loose, child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(5), children: [
          for (final slot in visible) _card(slot, locked),
          if (visible.isEmpty && !closed) Padding(padding: const EdgeInsets.all(12), child: Text(
            _openOnly ? 'No open shifts' : 'No shifts yet', style: const TextStyle(color: rosterMuted, fontSize: 12))),
        ])),
        if (!locked && !closed) Padding(padding: const EdgeInsets.fromLTRB(5, 0, 5, 4), child: TextButton.icon(
          style: _compactButton,
          key: ValueKey('board-add-${dateKey(date)}'), onPressed: () => widget.onAdd(date),
          icon: const Icon(Icons.add_circle_outline, size: 14), label: const Text('Add shift'))),
      ]));
  }

  Widget _card(WorkSlot slot, bool locked) {
    final plan = widget.plan;
    final name = slot.staffId == null ? null :
      (locked ? plan.published[dateKey(widget.week)]?.names[slot.staffId] : null) ?? plan.person(slot.staffId!).name;
    final problem = !locked && slot.staffId != null ? plan.assignmentProblem(slot, slot.staffId!) : null;
    final color = problem != null ? const Color(0xFFA33B32) : name == null ? const Color(0xFF9B6000) : const Color(0xFF24573D);
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Material(
      color: problem != null ? const Color(0xFFFFF0EF) : name == null ? const Color(0xFFFFFAF0) : const Color(0xFFEDF4EF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: BorderSide(color: color.withValues(alpha: .25))),
      child: InkWell(key: ValueKey('board-slot-${slot.id}'), onTap: locked ? null : () => widget.onPick(slot),
        borderRadius: BorderRadius.circular(5), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Flexible(flex: 6, child: Text(slot.timeLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
              const SizedBox(width: 6),
              Icon(name == null ? Icons.person_add_alt : Icons.check_circle_outline, size: 13, color: color),
              const SizedBox(width: 4),
              Expanded(flex: 5, child: Text(name ?? (locked ? 'Open' : 'Assign staff'), style: TextStyle(color: color, fontSize: 11))),
            ]),
            if (slot.role.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(slot.role, style: const TextStyle(color: rosterMuted, fontSize: 10))),
            if (problem != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(problem, style: TextStyle(color: color, fontSize: 10))),
          ])))));
  }
  ButtonStyle get _compactButton => TextButton.styleFrom(
    minimumSize: const Size(32, 30), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500));
}
