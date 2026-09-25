import 'package:flutter/material.dart';

import 'planner_theme.dart';

// Quiet sage tones complement the charcoal and white planner theme.
const assignedSlotSurface = Color(0xFFEDF4EF);
const assignedSlotBorder = Color(0xFFBACDBE);
const assignedSlotInk = Color(0xFF486351);

class ShiftSlotRow extends StatelessWidget {
  const ShiftSlotRow({
    required this.time,
    required this.index,
    this.staffName,
    this.role = '',
    this.problem,
    this.locked = false,
    this.onTap,
    super.key,
  });

  final String time;
  final int index;
  final String? staffName;
  final String role;
  final String? problem;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final assigned = staffName != null;
    final review = !locked && problem != null;
    final colors = Theme.of(context).colorScheme;
    final background = review
        ? colors.errorContainer
        : assigned
            ? assignedSlotSurface
            : rosterSurface;
    final border = review
        ? colors.error
        : assigned
            ? assignedSlotBorder
            : rosterLine;
    final iconColor = review
        ? colors.error
        : assigned
            ? assignedSlotInk
            : rosterMuted;
    final name = staffName ?? 'Open';
    const timeStyle = TextStyle(
        fontSize: 17,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: rosterInk);
    const slotStyle = TextStyle(fontSize: 12, height: 1.25, color: rosterMuted);
    final nameStyle = TextStyle(
        fontSize: 15,
        height: 1.25,
        fontWeight: assigned ? FontWeight.w700 : FontWeight.w400,
        color: assigned ? rosterInk : rosterMuted);
    final timeText = Text(time, style: timeStyle);
    final slotText = Text('Slot $index', style: slotStyle);
    final nameText = Text(name, style: nameStyle, textAlign: TextAlign.right);
    final icon = Icon(
        locked
            ? Icons.lock_outline
            : review
                ? Icons.warning_amber_rounded
                : assigned
                    ? Icons.check_circle_outline
                    : Icons.person_add_alt,
        size: 24,
        color: iconColor);
    final semantics = [
      time,
      'Slot $index',
      if (role.isNotEmpty) role,
      staffName ?? 'Open slot · Choose staff',
      if (locked) 'Published, locked',
      if (review) 'Review: $problem',
    ].join(', ');

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        label: semantics,
        button: onTap != null,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Material(
            color: background,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  child: LayoutBuilder(builder: (context, constraints) {
                    double width(String value, TextStyle style) {
                      final painter = TextPainter(
                        text: TextSpan(
                            text: value,
                            style: DefaultTextStyle.of(context)
                                .style
                                .merge(style)),
                        textDirection: Directionality.of(context),
                        textScaler: MediaQuery.textScalerOf(context),
                      )..layout();
                      final result = painter.width;
                      painter.dispose();
                      return result;
                    }

                    // Keep the reference's single row whenever all labels fit.
                    final fits = width(time, timeStyle) +
                            width('Slot $index', slotStyle) +
                            width(name, nameStyle) +
                            54 <=
                        constraints.maxWidth;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (fits)
                          Row(children: [
                            timeText,
                            const SizedBox(width: 6),
                            slotText,
                            const SizedBox(width: 12),
                            Expanded(child: nameText),
                            const SizedBox(width: 12),
                            icon,
                          ])
                        else ...[
                          Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [timeText, slotText]),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(child: nameText),
                            const SizedBox(width: 12),
                            icon,
                          ]),
                        ],
                        if (role.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(role, style: slotStyle),
                        ],
                        if (review) ...[
                          const SizedBox(height: 6),
                          Text('Review: $problem',
                              style:
                                  TextStyle(color: colors.error, fontSize: 12)),
                        ],
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
