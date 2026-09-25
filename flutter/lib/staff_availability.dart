import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'planner_model.dart';
import 'planner_theme.dart';
import 'slot_model.dart';
import 'slot_row.dart';

const _offInk = Color(0xFF9C4E46);
const _offSurface = Color(0xFFFCF1F0);

class StaffAvailabilityPanel extends StatefulWidget {
  const StaffAvailabilityPanel(
      {required this.getPlan,
      required this.onSave,
      required this.onEdit,
      required this.today,
      required this.resetToken,
      super.key});
  final SlotPlan Function() getPlan;
  final Future<void> Function(SlotPlan) onSave;
  final Future<void> Function(StaffMember?) onEdit;
  final DateTime today;
  final int resetToken;
  @override
  State<StaffAvailabilityPanel> createState() => _StaffAvailabilityPanelState();
}

class _StaffAvailabilityPanelState extends State<StaffAvailabilityPanel> {
  late DateTime _month = DateTime(widget.today.year, widget.today.month);
  String? _staffId;
  late DateTime? _day = restaurantClosed(widget.today) ? null : dateOnly(widget.today);
  bool _busy = false;
  String? _error;
  @override
  void didUpdateWidget(covariant StaffAvailabilityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) {
      _month = DateTime(widget.today.year, widget.today.month);
      _day = restaurantClosed(widget.today) ? null : dateOnly(widget.today);
      _error = null;
    }
  }

  Future<void> _save(SlotPlan next) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(next);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is PlanValidationException
            ? error.message
            : 'Availability could not be saved. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addStaff() async {
    final before = widget.getPlan().staff.map((p) => p.id).toSet();
    await widget.onEdit(null);
    if (!mounted) return;
    final added =
        widget.getPlan().staff.where((p) => !before.contains(p.id)).firstOrNull;
    if (added != null) {
      setState(() {
        _staffId = added.id;
        _error = null;
      });
    }
  }

  void _moveMonth(int offset) => setState(() {
        _month = DateTime(_month.year, _month.month + offset);
        _day = null;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final plan = widget.getPlan();
    final staff = plan.staff;
    final person =
        staff.where((p) => p.id == _staffId).firstOrNull ?? staff.firstOrNull;
    final id = person?.id;

    return ColoredBox(color: const Color(0xFFF5F7F5), child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final details = _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Day availability', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (person != null) ...[
          if (_day == null)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('Choose a date to view its time slots.',
                    style: TextStyle(color: rosterMuted))),
          if (_day != null) ...[
            const SizedBox(height: 16),
            Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${dayNames[_day!.weekday - 1]}, ${fullDate(_day!)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 18)),
                  TextButton(
                      key: const ValueKey('available-all-day'),
                      onPressed: _busy || !plan.hasTimeOff(id!, _day!)
                          ? null
                          : () => _save(
                              widget.getPlan().clearTimeOffDay(id!, _day!)),
                      child: const Text('All available')),
                ]),
            const Text(
                'On = available · Off = unavailable. Overlapping shifts are blocked too.',
                style: TextStyle(fontSize: 14, color: rosterMuted)),
            if (_busy)
              const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Saving…',
                      style: TextStyle(fontSize: 14, color: rosterMuted))),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: const TextStyle(color: _offInk))),
            for (final preset in plan.availabilityRanges(_day!))
              _slot(plan, id!, preset),
            if (plan.slots.any((s) =>
                s.staffId == id &&
                !plan.availableFor(s, id!) &&
                (dateKey(s.date) == dateKey(_day!) ||
                    (s.nextDay &&
                        dateKey(addDays(s.date, 1)) == dateKey(_day!)))))
              Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: _offSurface,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text(
                      'Already assigned during unavailable hours. Review the affected slots in Plan. Published rosters keep their confirmed version.',
                      style: TextStyle(color: _offInk, fontSize: 13))),
            const SizedBox(height: 12),
            const Text('Changes save automatically.',
                style: TextStyle(fontSize: 14, color: rosterMuted)),
          ],
          ],
        ]));
        return SingleChildScrollView(
          key: const PageStorageKey('staff-availability-scroll'),
          padding: EdgeInsets.all(wide ? 32 : 16),
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Staff & availability', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -.6)),
              const SizedBox(height: 8),
              const Text('Manage your team and plan around their availability.',
                style: TextStyle(fontSize: 16, color: rosterMuted)),
              const SizedBox(height: 24),
              if (person == null) _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Build your team', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                const Text('Add a staff member to start managing their availability.'),
                const SizedBox(height: 20),
                FilledButton.icon(key: const ValueKey('add-person'), onPressed: _addStaff,
                  icon: const Icon(Icons.person_add_alt), label: const Text('Add staff member')),
              ]))
              else ...[
                _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: DropdownButtonFormField<String>(
              key: const ValueKey('availability-staff'),
              value: id,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Staff member',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
              style: const TextStyle(
                  fontFamily: 'Roboto',
                  color: rosterInk,
                  fontSize: 17,
                  fontWeight: FontWeight.w700),
              items: [
                for (final member in staff)
                  DropdownMenuItem(value: member.id, child: Text(member.name))
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                        _staffId = value;
                        _error = null;
                      }),
            )),
            if (wide) TextButton.icon(onPressed: _busy ? null : () => widget.onEdit(person), icon: const Icon(Icons.edit_outlined), label: const Text('Edit staff'))
            else IconButton(
                tooltip: 'Edit ${person.name}',
                onPressed: _busy ? null : () => widget.onEdit(person),
                icon: const Icon(Icons.edit_outlined)),
            if (wide) FilledButton.icon(key: const ValueKey('add-person'), onPressed: _busy ? null : _addStaff, icon: const Icon(Icons.person_add_alt), label: const Text('Add staff'))
            else IconButton(
                key: const ValueKey('add-person'),
                tooltip: 'Add staff member',
                onPressed: _busy ? null : _addStaff,
                icon: const Icon(Icons.person_add_alt)),
          ]),
          const SizedBox(height: 10),
          const Text(
              'Available by default on open days. Select a date to manage time off.',
              style: TextStyle(fontSize: 15, color: rosterMuted)),
          if (person.sample)
            const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Sample staff member',
                    style: TextStyle(fontSize: 12, color: rosterMuted))),

                ])),
                const SizedBox(height: 24),
                if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 7, child: _calendar(plan, id!)),
                    const SizedBox(width: 24),
                    Expanded(flex: 4, child: details),
                  ])
                else ...[
                  _calendar(plan, id!),
                  const SizedBox(height: 24),
                  details,
                ],
              ],
            ]))),
        );
      },
    ));
  }

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFDCE5DF))),
    child: child);

  Widget _calendar(SlotPlan plan, String id) {
    final count = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = _month.weekday - 1;
    final rows = (leading + count + 6) ~/ 7;
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFDCE5DF)),
          borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(children: [
          IconButton(
              key: const ValueKey('calendar-previous-month'),
              tooltip: 'Previous month',
              onPressed: _busy ? null : () => _moveMonth(-1),
              icon: const Icon(Icons.chevron_left)),
          Expanded(
              child: Text('${_monthName(_month.month)} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700))),
          IconButton(
              key: const ValueKey('calendar-next-month'),
              tooltip: 'Next month',
              onPressed: _busy ? null : () => _moveMonth(1),
              icon: const Icon(Icons.chevron_right)),
        ]),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12),
          child: Wrap(spacing: 16, runSpacing: 8, children: [
            Text('● Available', style: TextStyle(color: Color(0xFF24573D), fontSize: 13)),
            Text('● Time off', style: TextStyle(color: _offInk, fontSize: 13)),
            Text('● Closed Tuesday & Wednesday', style: TextStyle(color: rosterMuted, fontSize: 13)),
          ])),
        LayoutBuilder(builder: (context, constraints) {
          final number = TextPainter(
              text: TextSpan(
                  text: '99',
                  style: DefaultTextStyle.of(context)
                      .style
                      .copyWith(fontSize: 20, fontWeight: FontWeight.w700)),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context))
            ..layout();
          final cell = math.max(constraints.maxWidth / 7,
              math.max(56.0, math.max(number.width, number.height) + 20));
          number.dispose();
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
                width: cell * 7,
                child: Column(children: [
                  Row(children: [
                    for (final name in (cell >= 90 ? dayNames : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']))
                      SizedBox(
                          width: cell,
                          height: 48,
                          child: Center(
                              child: Text(name,
                                  style: const TextStyle(
                                      fontSize: 13, color: rosterMuted))))
                  ]),
                  for (var week = 0; week < rows; week++)
                    Row(children: [
                      for (var weekday = 0; weekday < 7; weekday++)
                        SizedBox(
                            width: cell,
                            height: cell >= 80 ? 88 : 56,
                            child: _dateCell(plan, id,
                                week * 7 + weekday - leading + 1, count, cell >= 80)),
                    ]),
                ])),
          );
        }),
      ]),
    );
  }

  Widget _dateCell(SlotPlan plan, String id, int day, int count, bool detailed) {
    if (day < 1 || day > count) return const SizedBox.shrink();
    final date = DateTime(_month.year, _month.month, day);
    final closed = restaurantClosed(date);
    final selected = _day != null && dateKey(date) == dateKey(_day!);
    final off = !closed &&
        plan.availabilityRanges(date).any((preset) =>
            !plan.availableFor(preset.onDay(date, 'calendar-range'), id));
    final today = dateKey(date) == dateKey(widget.today);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Semantics(
        label:
            '${dayNames[date.weekday - 1]}, ${shortDate(date)} ${date.year}${closed ? ', restaurant closed' : off ? ', unavailable time' : ', available'}',
        selected: selected,
        enabled: !closed,
        button: true,
        child: Material(
          color: closed
              ? rosterSurface
              : off
                  ? const Color(0xFFFFE1DF)
                  : selected
                      ? assignedSlotSurface
                      : const Color(0xFFEAF4ED),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                  color: !closed && off
                      ? (selected ? _offInk : const Color(0xFFE8C9C7))
                      : selected
                          ? assignedSlotInk
                          : today
                              ? rosterLine
                              : Colors.transparent,
                  width: selected ? 1.5 : 1)),
          child: InkWell(
            key: ValueKey('calendar-day-${dateKey(date)}'),
            borderRadius: BorderRadius.circular(12),
            onTap: _busy || closed
                ? null
                : () => setState(() {
                      _day = date;
                      _error = null;
                    }),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$day',
                  style: TextStyle(
                      color: closed
                          ? rosterMuted
                          : off
                              ? _offInk
                              : rosterInk,
                      fontSize: 20,
                      fontWeight: selected || today
                          ? FontWeight.w700
                          : FontWeight.w400)),
              const SizedBox(height: 6),
              if (detailed) Text(closed ? 'Closed' : off ? 'Time off' : 'Available', style: TextStyle(fontSize: 12, color: off ? _offInk : rosterMuted)),
              Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: off ? _offInk : Colors.transparent)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _slot(SlotPlan plan, String id, SlotPreset preset) {
    final range = preset.onDay(_day!, 'availability-range');
    final available = plan.availableFor(range, id);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
          color: available ? assignedSlotSurface : _offSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: available ? assignedSlotBorder : const Color(0xFFE8C9C7))),
      child: Material(color: Colors.transparent, child: SwitchListTile(
        key: ValueKey(
            'availability-toggle-${preset.start}-${preset.end}-${preset.nextDay}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        title: Text(preset.timeLabel,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        subtitle: Text(available ? 'Available' : 'Unavailable',
            style: TextStyle(
                color: available ? assignedSlotInk : _offInk, fontSize: 14)),
        value: available,
        activeColor: Colors.white,
        activeTrackColor: assignedSlotInk,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: _offInk,
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        onChanged: _busy
            ? null
            : (value) =>
                _save(widget.getPlan().setRangeAvailable(id, range, value)),
      )),
    );
  }
}

String _monthName(int month) => const [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ][month - 1];
