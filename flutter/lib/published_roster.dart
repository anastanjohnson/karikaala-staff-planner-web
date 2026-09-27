import 'package:flutter/material.dart';

import 'planner_model.dart';
import 'planner_theme.dart';
import 'slot_model.dart';
import 'slot_row.dart';

/// A read-only day from the confirmed snapshot, including its saved names.
class PublishedDayCard extends StatelessWidget {
  const PublishedDayCard({
    required this.publication,
    required this.day,
    super.key,
  });

  final PublishedWeek publication;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final slots = publication.slots
        .where((slot) => dateKey(slot.date) == dateKey(day))
        .toList()
      ..sort((a, b) {
        final start = a.start.compareTo(b.start);
        if (start != 0) return start;
        final end = a.endsAt.compareTo(b.endsAt);
        return end != 0 ? end : a.id.compareTo(b.id);
      });
    return Card(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      color: rosterPaper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFDCE5DF))),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(dayNames[day.weekday - 1], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(fullDate(day), style: const TextStyle(fontSize: 13, color: rosterMuted)),
                const SizedBox(height: 10),
                Text('${slots.length} confirmed ${slots.length == 1 ? 'shift' : 'shifts'}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF24573D))),
                const SizedBox(height: 8),
              ]),
            ),
            if (slots.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(restaurantClosed(day) ? 'Restaurant closed' : 'No shifts scheduled',
                    style: TextStyle(color: rosterMuted, fontSize: 13)),
              ),
            for (final slot in slots)
              _PublishedStaffRow(
                key: ValueKey('published-slot-${slot.id}'),
                slot: slot,
                name: publication.names[slot.staffId] ?? 'Unassigned',
              ),
          ],
        ),
      ),
    );
  }
}

class _PublishedStaffRow extends StatelessWidget {
  const _PublishedStaffRow({required this.slot, required this.name, super.key});

  final WorkSlot slot;
  final String name;

  @override
  Widget build(BuildContext context) {
    const nameStyle = TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: rosterInk);
    const timeStyle = TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: -0.2,
        color: rosterInk);
    final details = [
      if (slot.role.isNotEmpty) slot.role,
      if (slot.breakMinutes > 0) '${slot.breakMinutes} min unpaid break',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: assignedSlotSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: assignedSlotBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(
                  text: slot.timeLabel,
                  style: DefaultTextStyle.of(context).style.merge(timeStyle)),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final fits = painter.width +
                    MediaQuery.textScalerOf(context).scale(72) +
                    16 <=
                constraints.maxWidth;
            painter.dispose();
            final nameText = Text(name, style: nameStyle);
            final timeText = Text(slot.timeLabel,
                style: timeStyle, textAlign: TextAlign.left);
            if (fits) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    timeText,
                    const SizedBox(width: 12),
                    Expanded(child: nameText),
                  ]);
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  timeText,
                  const SizedBox(height: 8),
                  nameText,
                ]);
          }),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(details,
                style: const TextStyle(fontSize: 14, color: rosterMuted)),
          ],
          if (slot.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Note: ${slot.notes}',
                style: const TextStyle(fontSize: 14, color: rosterMuted)),
          ],
        ],
      ),
    );
  }
}

/// Review the immutable published snapshot in a responsive weekly overview.
class PublishedRosterOverview extends StatelessWidget {
  const PublishedRosterOverview({super.key, required this.publication,
    required this.onCopy, this.hasDraft = false, this.shared = false});
  final PublishedWeek publication;
  final VoidCallback onCopy;
  final bool hasDraft, shared;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF24573D);
    final people = publication.slots.map((s) => s.staffId).whereType<String>().toSet().length;
    final confirmed = publication.publishedAt.toLocal();

    final days = List.generate(7, (d) => addDays(publication.week, d));
    bool closedEmpty(DateTime day) => restaurantClosed(day) &&
      !publication.slots.any((slot) => dateKey(slot.date) == dateKey(day));
    final workingDays = days.where((day) => !closedEmpty(day)).toList();
    return ColoredBox(color: const Color(0xFFF5F7F5),
      child: LayoutBuilder(builder: (context, viewport) => SingleChildScrollView(
        padding: EdgeInsets.all(viewport.maxWidth >= 900 ? 24 : 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 24, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Published schedule', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            Chip(avatar: const Icon(Icons.verified_outlined, color: green, size: 20),
              label: Text('Confirmed · Version ${publication.revision}'),
              backgroundColor: const Color(0xFFDDEFE3)),
            Text('${publication.slots.length} ${publication.slots.length == 1 ? 'shift' : 'shifts'} · $people ${people == 1 ? 'staff member' : 'staff members'}',
              style: const TextStyle(fontSize: 16, color: rosterMuted)),
            FilledButton.icon(key: const ValueKey('copy-roster'), onPressed: onCopy,
              style: FilledButton.styleFrom(backgroundColor: green),
              icon: const Icon(Icons.copy_outlined), label: const Text('Copy published roster')),
          ]),
          const SizedBox(height: 12),
          Text('Confirmed ${fullDate(confirmed)} at ${clock(confirmed.hour * 60 + confirmed.minute)}',
            style: const TextStyle(fontSize: 14, color: rosterMuted)),
          const SizedBox(height: 8),
          Text(shared ? 'Linked staff can see these confirmed shifts. Make changes in Plan.' :
            'Review the confirmed week. Copy the roster to share it with your team.',
            style: const TextStyle(fontSize: 14, color: rosterMuted)),
          if (hasDraft) Container(margin: const EdgeInsets.only(top: 16), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFFFE8BC), borderRadius: BorderRadius.circular(12)),
            child: const Text('Draft changes have not been published. The confirmed schedule below is unchanged.',
              style: TextStyle(color: Color(0xFF805000), fontSize: 15))),
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 8, children: [
            for (final day in days.where(closedEmpty))
              Chip(avatar: const Icon(Icons.event_busy_outlined, size: 18),
                label: Text('${dayNames[day.weekday - 1]} · ${fullDate(day)} · Restaurant closed')),
          ]),
          const SizedBox(height: 20),
          if (viewport.maxWidth >= 1000)
            LayoutBuilder(builder: (context, box) {
              final minWidth = workingDays.length * 260.0 + (workingDays.length - 1) * 16;
              final width = box.maxWidth > minWidth ? box.maxWidth : minWidth;
              return SingleChildScrollView(scrollDirection: Axis.horizontal,
                child: SizedBox(width: width, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (var i = 0; i < workingDays.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    Expanded(child: PublishedDayCard(publication: publication, day: workingDays[i])),
                  ],
                ])));
            })
          else
            Column(children: [
              for (final day in workingDays)
                Padding(padding: const EdgeInsets.only(bottom: 16),
                  child: SizedBox(width: double.infinity, child: PublishedDayCard(publication: publication, day: day))),
            ]),
        ]),
      )),
    );
  }
}
