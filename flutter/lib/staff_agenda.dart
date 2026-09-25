import 'package:flutter/material.dart';
import 'planner_model.dart';
import 'slot_model.dart';

/// Personal schedule presentation; all assignments remain manager-controlled.
class StaffAgenda extends StatefulWidget {
  const StaffAgenda({super.key, required this.name, required this.slots, this.today});
  final String name;
  final List<WorkSlot> slots;
  final DateTime? today;

  @override
  State<StaffAgenda> createState() => _StaffAgendaState();
}

class _StaffAgendaState extends State<StaffAgenda> {
  static const green = Color(0xFF24573D);
  static const muted = Color(0xFF58675F);
  static const line = Color(0xFFDCE5DF);
  DateTime? _week;
  DateTime? _selected;
  DateTime monday(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - 1));

  void browse(DateTime week, int direction) {
    setState(() {
      _week = week.add(Duration(days: direction * 7));
      _selected = null;
    });
  }

  String hours(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(widget.today ?? DateTime.now());
    final all = [...widget.slots]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final week = _week ?? monday(today);
    final end = week.add(const Duration(days: 7));
    final slots = all.where((s) => !s.date.isBefore(week) && s.date.isBefore(end)).toList();
    final chosen = _selected ?? (slots.isEmpty ? week : slots.first.date);
    final selectedSlots = slots.where((s) => dateKey(s.date) == dateKey(chosen)).toList();
    final groups = <String, List<WorkSlot>>{};
    for (final slot in slots) {
      groups.putIfAbsent(dateKey(slot.date), () => []).add(slot);
    }
    final total = slots.fold<int>(0, (sum, s) => sum + s.duration - s.breakMinutes);
    return ColoredBox(
      color: const Color(0xFFF5F7F5),
      child: LayoutBuilder(builder: (context, viewport) {
        final wide = viewport.maxWidth >= 900;
        return SingleChildScrollView(
          padding: EdgeInsets.all(wide ? 32 : 16),
          child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hello, ${widget.name}', style: const TextStyle(color: muted, fontSize: 16)),
              const SizedBox(height: 6),
              const Text('Your working week', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -.8)),
              const SizedBox(height: 8),
              const Text('Your shifts, clearly planned. Select a day to see the details.',
                style: TextStyle(fontSize: 15, color: muted)),
              const SizedBox(height: 24),
              if (wide)
                Row(children: [
                  Expanded(child: _stat(Icons.calendar_today_outlined, '${slots.length} shifts', 'Scheduled this week')),
                  const SizedBox(width: 12),
                  Expanded(child: _stat(Icons.schedule_outlined, hours(total), 'Working time · breaks excluded')),
                  const SizedBox(width: 12),
                  Expanded(child: _stat(Icons.event_available_outlined, '${groups.length} days', 'Days on your schedule')),
                ])
              else
                Container(width: double.infinity, padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: line), borderRadius: BorderRadius.circular(14)),
                  child: Text('${slots.length} shifts  ·  ${hours(total)}  ·  ${groups.length} working days',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: green))),
              const SizedBox(height: 28),
              Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${fullDate(week)} – ${fullDate(end.subtract(const Duration(days: 1)))}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                OutlinedButton.icon(onPressed: () => browse(week, -1),
                  icon: const Icon(Icons.chevron_left), label: const Text('Previous week')),
                OutlinedButton.icon(onPressed: () => browse(week, 1),
                  icon: const Icon(Icons.chevron_right), label: const Text('Next week')),
                if (dateKey(week) != dateKey(monday(today)))
                  TextButton(onPressed: () => setState(() { _week = monday(today); _selected = null; }),
                    child: const Text('This week')),
              ]),
              const SizedBox(height: 18),
              LayoutBuilder(builder: (context, box) {
                // Scroll the date strip on small screens rather than shrinking its labels.
                final width = box.maxWidth < 1000 ? 1000.0 : box.maxWidth;
                return SingleChildScrollView(scrollDirection: Axis.horizontal,
                  child: SizedBox(width: width, child: Row(children: [
                    for (var i = 0; i < 7; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: _day(week.add(Duration(days: i)), chosen, slots)),
                    ],
                  ])));
              }),
              const SizedBox(height: 24),
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 5, child: _details(chosen, selectedSlots, all)),
                  const SizedBox(width: 24),
                  Expanded(flex: 6, child: _overview(groups, chosen)),
                ])
              else ...[
                _details(chosen, selectedSlots, all),
                const SizedBox(height: 24),
                _overview(groups, chosen),
              ],
              const SizedBox(height: 24),
              const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 18, color: muted),
                SizedBox(width: 8),
                Expanded(child: Text('Your manager may update this schedule. Check Messages for team updates.',
                  style: TextStyle(color: muted, fontSize: 14))),
              ]),
              const SizedBox(height: 16),
            ]),
          )),
        );
      }),
    );
  }

  Widget _stat(IconData icon, String value, String caption) => Container(
    width: 260, padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: line), borderRadius: BorderRadius.circular(16)),
    child: Row(children: [
      Icon(icon, color: green, size: 24), const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(caption, style: const TextStyle(fontSize: 13, color: muted)),
      ])),
    ]),
  );

  Widget _day(DateTime day, DateTime chosen, List<WorkSlot> slots) {
    final count = slots.where((s) => dateKey(s.date) == dateKey(day)).length;
    final active = dateKey(day) == dateKey(chosen);
    final closed = restaurantClosed(day) && count == 0;
    final ink = active ? Colors.white : green;
    return Material(color: active ? green : closed ? const Color(0xFFEBEFEC) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: active ? green : line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(key: ValueKey('staff-day-${dateKey(day)}'),
        onTap: () => setState(() => _selected = day),
        child: Semantics(selected: active, child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
          child: Column(children: [
            Text(dayNames[day.weekday - 1], style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink)),
            const SizedBox(height: 8),
            Text('${day.day}', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 8),
            Text(closed ? 'Closed' : count == 0 ? 'No shifts' : '$count ${count == 1 ? 'shift' : 'shifts'}',
              style: TextStyle(fontSize: 13, color: active ? Colors.white : muted)),
          ]),
        )),
      ));
  }

  Widget _details(DateTime day, List<WorkSlot> slots, List<WorkSlot> all) {
    final next = slots.isNotEmpty && all.isNotEmpty && slots.first.id == all.first.id;
    return Container(width: double.infinity, padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.calendar_month_outlined, color: Color(0xFFCAE5D4)),
          const SizedBox(width: 10),
          Text(next ? 'YOUR NEXT SHIFT' : 'SELECTED DAY',
            style: const TextStyle(color: Color(0xFFCAE5D4), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 24),
        Text(dayNames[day.weekday - 1], style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(fullDate(day), style: const TextStyle(color: Color(0xFFCAE5D4), fontSize: 15)),
        const SizedBox(height: 20),
        if (slots.isEmpty)
          Text(restaurantClosed(day) ? 'The restaurant is closed.' : 'No shifts scheduled. Enjoy your time off.',
            style: const TextStyle(color: Colors.white, fontSize: 18)),
        for (var i = 0; i < slots.length; i++) ...[
          if (i > 0) const Padding(padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(color: Color(0xFF588169))),
          Text('${clock(slots[i].start)} – ${clock(slots[i].end)}',
            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text('${hours(slots[i].duration - slots[i].breakMinutes)} working time',
            style: const TextStyle(color: Color(0xFFCAE5D4), fontSize: 15)),
          if (slots[i].nextDay) _detailText('Ends the next day'),
          if (slots[i].breakMinutes > 0) _detailText('${slots[i].breakMinutes} min unpaid break'),
          if (slots[i].role.isNotEmpty) _detailText(slots[i].role),
          if (slots[i].notes.isNotEmpty) _detailText(slots[i].notes),
        ],
      ]));
  }

  Widget _detailText(String value) => Padding(padding: const EdgeInsets.only(top: 10),
    child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5)));

  Widget _overview(Map<String, List<WorkSlot>> groups, DateTime chosen) => Container(
    width: double.infinity, padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: line), borderRadius: BorderRadius.circular(22)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Your schedule', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('All your shifts for this week', style: TextStyle(fontSize: 14, color: muted)),
      const SizedBox(height: 20),
      if (groups.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('No shifts scheduled this week. You can browse another week above.',
            style: TextStyle(fontSize: 15, color: muted))),
      for (final group in groups.values)
        Padding(padding: const EdgeInsets.only(bottom: 12),
          child: Material(color: dateKey(group.first.date) == dateKey(chosen) ? const Color(0xFFE8F2EB) : const Color(0xFFF7F9F7),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(borderRadius: BorderRadius.circular(14),
              key: ValueKey('staff-overview-${dateKey(group.first.date)}'),
              onTap: () => setState(() => _selected = group.first.date),
              child: Padding(padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${dayNames[group.first.date.weekday - 1]}, ${fullDate(group.first.date)}',
                    style: const TextStyle(fontSize: 15, color: green, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  for (final slot in group)
                    Padding(padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Wrap(spacing: 16, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(slot.timeLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        Text(hours(slot.duration - slot.breakMinutes), style: const TextStyle(fontSize: 14, color: muted)),
                      ])),
                  const SizedBox(height: 6),
                  const Text('View details →', style: TextStyle(fontSize: 13, color: green)),
                ])),
            )),
        ),
    ]),
  );
}
