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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(dayNames[day.weekday - 1],
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w700)),
                  Text(fullDate(day),
                      style: const TextStyle(fontSize: 14, color: rosterMuted)),
                  Text(
                      '${slots.length} ${slots.length == 1 ? 'slot' : 'slots'}',
                      style: const TextStyle(fontSize: 14, color: rosterMuted)),
                ],
              ),
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
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: rosterInk);
    const timeStyle = TextStyle(
        fontSize: 16,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      constraints: const BoxConstraints(minHeight: 68),
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
                style: timeStyle, textAlign: TextAlign.right);
            if (fits) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: nameText),
                    const SizedBox(width: 16),
                    timeText,
                  ]);
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  nameText,
                  const SizedBox(height: 6),
                  timeText,
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
    return ColoredBox(color: const Color(0xFFF5F7F5),
      child: LayoutBuilder(builder: (context, viewport) => SingleChildScrollView(
        padding: EdgeInsets.all(viewport.maxWidth >= 900 ? 32 : 16),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Published schedule', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -.6)),
            const SizedBox(height: 8),
            const Text('Review the confirmed week and share it with your team.',
              style: TextStyle(fontSize: 16, color: rosterMuted)),
            const SizedBox(height: 24),
            Container(padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 24, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Icon(Icons.verified_outlined, color: Colors.white, size: 30),
                  Text('Published · Version ${publication.revision}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                  FilledButton.icon(key: const ValueKey('copy-roster'), onPressed: onCopy,
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: green),
                    icon: const Icon(Icons.copy_outlined), label: const Text('Copy published roster')),
                ]),
                const SizedBox(height: 16),
                Text('Confirmed ${fullDate(confirmed)} at ${clock(confirmed.hour * 60 + confirmed.minute)}',
                  style: const TextStyle(color: Color(0xFFD6EBDD), fontSize: 15)),
                const SizedBox(height: 12),
                Text('${publication.slots.length} shifts  ·  $people staff members',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(shared ? 'Linked staff can see their own confirmed shifts.' : 'Copy this roster to share it with your team.',
                  style: const TextStyle(color: Color(0xFFD6EBDD), fontSize: 14)),
              ])),
            if (hasDraft) Container(margin: const EdgeInsets.only(top: 16), padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: const Color(0xFFFFE8BC), borderRadius: BorderRadius.circular(14)),
              child: const Text('Draft changes have not been published. The confirmed schedule below is unchanged.',
                style: TextStyle(color: Color(0xFF805000), fontSize: 15))),
            const SizedBox(height: 28),
            const Text('The week at a glance', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Confirmed assignments · Make changes in Plan',
              style: TextStyle(color: rosterMuted, fontSize: 14)),
            const SizedBox(height: 18),
            LayoutBuilder(builder: (context, box) {
              final columns = box.maxWidth >= 1200 ? 3 : box.maxWidth >= 760 ? 2 : 1;
              final width = (box.maxWidth - (columns - 1) * 20) / columns;
              return Wrap(spacing: 20, runSpacing: 20, children: [
                for (var d = 0; d < 7; d++)
                  SizedBox(width: width, child: PublishedDayCard(
                    publication: publication, day: addDays(publication.week, d))),
              ]);
            }),
          ]),
        ))),
      ),
    );
  }
}
