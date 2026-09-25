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
      shape: rosterOutline,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(shortDate(day),
                      style: const TextStyle(fontSize: 12, color: rosterMuted)),
                  Text(
                      '${slots.length} ${slots.length == 1 ? 'slot' : 'slots'}',
                      style: const TextStyle(fontSize: 12, color: rosterMuted)),
                ],
              ),
            ),
            if (slots.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No shifts scheduled',
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        color: assignedSlotSurface,
        borderRadius: BorderRadius.circular(8),
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
                style: const TextStyle(fontSize: 12, color: rosterMuted)),
          ],
          if (slot.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Note: ${slot.notes}',
                style: const TextStyle(fontSize: 12, color: rosterMuted)),
          ],
        ],
      ),
    );
  }
}
