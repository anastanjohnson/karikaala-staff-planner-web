import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'planner_model.dart';

class PlanValidationException implements Exception {
  const PlanValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

bool restaurantClosed(DateTime date) =>
    date.weekday == DateTime.tuesday || date.weekday == DateTime.wednesday;

DateTime wallTime(DateTime date, int minutes) =>
    DateTime.utc(date.year, date.month, date.day, minutes ~/ 60, minutes % 60);

class WorkSlot {
  const WorkSlot({
    required this.id,
    required this.date,
    required this.start,
    required this.end,
    this.nextDay = false,
    this.staffId,
    this.breakMinutes = 0,
    this.role = '',
    this.notes = '',
  });
  final String id;
  final DateTime date;
  final int start;
  final int end;
  final bool nextDay;
  final String? staffId;
  final int breakMinutes;
  final String role;
  final String notes;
  int get duration => end + (nextDay ? 1440 : 0) - start;
  DateTime get startsAt => wallTime(date, start);
  DateTime get endsAt => wallTime(date, end + (nextDay ? 1440 : 0));
  String get timeLabel =>
      '${clock(start)} – ${clock(end)}${nextDay ? ' (+1 day)' : ''}';
  WorkSlot assign(String? person) => WorkSlot(
    id: id,
    date: date,
    start: start,
    end: end,
    nextDay: nextDay,
    staffId: person,
    breakMinutes: breakMinutes,
    role: role,
    notes: notes,
  );
  String? get detailsError {
    if (start < 0 ||
        start >= 1440 ||
        end < 0 ||
        end >= 1440 ||
        duration <= 0 ||
        duration >= 1440) {
      return 'End must follow start. Turn on “Ends next day” for an overnight slot. Slots must be shorter than 24 hours.';
    }
    if (breakMinutes < 0 || breakMinutes >= duration) {
      return 'Break must be shorter than the slot.';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': dateKey(date),
    'start': start,
    'end': end,
    'nextDay': nextDay,
    'staffId': staffId,
    'breakMinutes': breakMinutes,
    'role': role,
    'notes': notes,
  };
  factory WorkSlot.fromJson(Map<String, dynamic> json) => WorkSlot(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    start: json['start'] as int,
    end: json['end'] as int,
    nextDay: json['nextDay'] == true,
    staffId: json['staffId'] as String?,
    breakMinutes: json['breakMinutes'] as int? ?? 0,
    role: json['role'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
  );
}

// A reusable set of hours and default details, independent of any assignment.
class SlotPreset {
  const SlotPreset({
    required this.start,
    required this.end,
    this.nextDay = false,
    this.breakMinutes = 0,
    this.role = '',
  });
  final int start, end, breakMinutes;
  final bool nextDay;
  final String role;
  String get key => jsonEncode([start, end, nextDay, breakMinutes, role]);
  String get timeLabel =>
      '${clock(start)} – ${clock(end)}${nextDay ? ' (+1 day)' : ''}';
  String get detailLabel => [
    breakMinutes == 0 ? 'No unpaid break' : '$breakMinutes min unpaid break',
    if (role.isNotEmpty) role,
  ].join(' · ');
  factory SlotPreset.fromSlot(WorkSlot slot) => SlotPreset(
    start: slot.start,
    end: slot.end,
    nextDay: slot.nextDay,
    breakMinutes: slot.breakMinutes,
    role: slot.role.trim(),
  );
  WorkSlot onDay(DateTime day, String id) => WorkSlot(
    id: id,
    date: dateOnly(day),
    start: start,
    end: end,
    nextDay: nextDay,
    breakMinutes: breakMinutes,
    role: role,
  );
  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'nextDay': nextDay,
    'breakMinutes': breakMinutes,
    'role': role,
  };
  factory SlotPreset.fromJson(Map<String, dynamic> json) => SlotPreset(
    start: json['start'] as int,
    end: json['end'] as int,
    nextDay: json['nextDay'] as bool,
    breakMinutes: json['breakMinutes'] as int,
    role: (json['role'] as String).trim(),
  );
}

const standardSlotPresets = [
  SlotPreset(start: 660, end: 1020),
  SlotPreset(start: 720, end: 1020),
  SlotPreset(start: 960, end: 1320),
  SlotPreset(start: 1020, end: 1320),
];

List<SlotPreset> uniqueSlotPresets(Iterable<SlotPreset> presets) =>
    {for (final preset in presets) preset.key: preset}.values.toList()
      ..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        if (byStart != 0) return byStart;
        final byEnd = (a.end + (a.nextDay ? 1440 : 0)).compareTo(
          b.end + (b.nextDay ? 1440 : 0),
        );
        if (byEnd != 0) return byEnd;
        final byRole = a.role.compareTo(b.role);
        return byRole != 0 ? byRole : a.breakMinutes.compareTo(b.breakMinutes);
      });

class StaffAvailability {
  const StaffAvailability({
    required this.staffId,
    required this.date,
    required this.available,
    this.start = 0,
    this.end = 1440,
  });
  final String staffId;
  final DateTime date;
  final bool available;
  final int start;
  // May exceed 1440 when availability continues after midnight.
  final int end;
  String get key => '$staffId/${dateKey(date)}';
  String get label => !available
      ? 'Unavailable this day'
      : '${clock(start)} – ${clock(end > 1440 ? end - 1440 : end)}${end > 1440 ? ' (+1 day)' : ''}';
  bool covers(WorkSlot slot) =>
      available && start <= slot.start && end >= slot.start + slot.duration;
  Map<String, dynamic> toJson() => {
    'staffId': staffId,
    'date': dateKey(date),
    'available': available,
    'start': start,
    'end': end,
  };
  factory StaffAvailability.fromJson(Map<String, dynamic> json) =>
      StaffAvailability(
        staffId: json['staffId'] as String,
        date: DateTime.parse(json['date'] as String),
        available: json['available'] as bool,
        start: json['start'] as int,
        end: json['end'] as int,
      );
}

// Unavailable clock-time intervals. Overnight ranges are split at midnight.
class StaffTimeOff {
  const StaffTimeOff({
    required this.staffId,
    required this.date,
    required this.start,
    required this.end,
  });
  final String staffId;
  final DateTime date;
  final int start, end;
  DateTime get startsAt => wallTime(date, start);
  DateTime get endsAt => wallTime(date, end);
  bool overlaps(WorkSlot slot) =>
      startsAt.isBefore(slot.endsAt) && slot.startsAt.isBefore(endsAt);
  Map<String, dynamic> toJson() => {
    'staffId': staffId,
    'date': dateKey(date),
    'start': start,
    'end': end,
  };
  factory StaffTimeOff.fromJson(Map<String, dynamic> json) {
    final date = DateTime.parse(json['date'] as String);
    if (dateKey(date) != json['date']) {
      throw const FormatException('Invalid date');
    }
    return StaffTimeOff(
      staffId: json['staffId'] as String,
      date: date,
      start: json['start'] as int,
      end: json['end'] as int,
    );
  }
}

List<StaffTimeOff> mergeTimeOff(Iterable<StaffTimeOff> input) {
  final sorted = input.toList()
    ..sort((a, b) {
      final staff = a.staffId.compareTo(b.staffId);
      if (staff != 0) return staff;
      final day = dateKey(a.date).compareTo(dateKey(b.date));
      return day != 0 ? day : a.start.compareTo(b.start);
    });
  final result = <StaffTimeOff>[];
  for (final item in sorted) {
    if (result.isNotEmpty) {
      final last = result.last;
      if (last.staffId == item.staffId &&
          dateKey(last.date) == dateKey(item.date) &&
          item.start <= last.end) {
        result[result.length - 1] = StaffTimeOff(
          staffId: last.staffId,
          date: last.date,
          start: last.start,
          end: item.end > last.end ? item.end : last.end,
        );
        continue;
      }
    }
    result.add(item);
  }
  return result;
}

List<StaffTimeOff> splitTimeOff(String id, DateTime from, DateTime to) {
  final result = <StaffTimeOff>[];
  var day = DateTime.utc(from.year, from.month, from.day);
  while (day.isBefore(to)) {
    final next = day.add(const Duration(days: 1));
    result.add(
      StaffTimeOff(
        staffId: id,
        date: DateTime(day.year, day.month, day.day),
        start: from.isAfter(day) ? from.difference(day).inMinutes : 0,
        end: to.isBefore(next) ? to.difference(day).inMinutes : 1440,
      ),
    );
    day = next;
  }
  return result;
}

// Keep entered restrictions, but discard complete untouched demo-week defaults.
List<StaffTimeOff> migrateAvailability(
  List<StaffAvailability> legacy,
  List<StaffMember> staff,
) {
  final demoWeeks = <String>{};
  for (final person in staff.where((p) => p.sample)) {
    final weeks = legacy
        .where((a) => a.staffId == person.id)
        .map((a) => dateKey(mondayOf(a.date)))
        .toSet();
    for (final week in weeks) {
      final entries = legacy
          .where(
            (a) => a.staffId == person.id && dateKey(mondayOf(a.date)) == week,
          )
          .toList();
      if (entries.length == 7 &&
          entries.every(
            (a) =>
                a.available ==
                    ![
                      DateTime.tuesday,
                      DateTime.wednesday,
                    ].contains(a.date.weekday) &&
                a.start == (a.date.weekday < DateTime.saturday ? 960 : 660) &&
                a.end == 1320,
          )) {
        demoWeeks.add('${person.id}/$week');
      }
    }
  }
  final entered = legacy
      .where(
        (a) => !demoWeeks.contains('${a.staffId}/${dateKey(mondayOf(a.date))}'),
      )
      .toList();
  final result = <StaffTimeOff>[];
  for (final entry in entered) {
    final allowed = <StaffTimeOff>[
      if (entry.available)
        StaffTimeOff(
          staffId: entry.staffId,
          date: entry.date,
          start: entry.start,
          end: entry.end > 1440 ? 1440 : entry.end,
        ),
      for (final previous in entered)
        if (previous.staffId == entry.staffId &&
            previous.available &&
            previous.end > 1440 &&
            dateKey(addDays(previous.date, 1)) == dateKey(entry.date))
          StaffTimeOff(
            staffId: entry.staffId,
            date: entry.date,
            start: 0,
            end: previous.end - 1440,
          ),
    ];
    var cursor = 0;
    for (final window in mergeTimeOff(allowed)) {
      if (window.start > cursor) {
        result.add(
          StaffTimeOff(
            staffId: entry.staffId,
            date: entry.date,
            start: cursor,
            end: window.start,
          ),
        );
      }
      if (window.end > cursor) cursor = window.end;
    }
    if (cursor < 1440) {
      result.add(
        StaffTimeOff(
          staffId: entry.staffId,
          date: entry.date,
          start: cursor,
          end: 1440,
        ),
      );
    }
  }
  return mergeTimeOff(result);
}

class PublishedWeek {
  PublishedWeek({
    required this.week,
    required List<WorkSlot> slots,
    required Map<String, String> names,
    required this.publishedAt,
    required this.revision,
  }) : slots = List.unmodifiable(slots),
       names = Map.unmodifiable(names);
  final DateTime week;
  final List<WorkSlot> slots;
  final Map<String, String> names;
  final DateTime publishedAt;
  final int revision;
  Map<String, dynamic> toJson() => {
    'week': dateKey(week),
    'slots': slots.map((s) => s.toJson()).toList(),
    'names': names,
    'publishedAt': publishedAt.toIso8601String(),
    'revision': revision,
  };
  factory PublishedWeek.fromJson(Map<String, dynamic> json) => PublishedWeek(
    week: DateTime.parse(json['week'] as String),
    slots: (json['slots'] as List)
        .map((s) => WorkSlot.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList(),
    names: Map<String, String>.from(json['names'] as Map),
    publishedAt: DateTime.parse(json['publishedAt'] as String),
    revision: json['revision'] as int,
  );
  String rosterText() {
    final text = StringBuffer(
      'STAFF PLAN · ${shortDate(week)} – ${shortDate(addDays(week, 6))} ${addDays(week, 6).year}\nPublished · version $revision\n',
    );
    for (var i = 0; i < 7; i++) {
      final day = addDays(week, i);
      final entries =
          slots.where((s) => dateKey(s.date) == dateKey(day)).toList()
            ..sort((a, b) => a.start.compareTo(b.start));
      text.writeln('\n${dayNames[i]} ${shortDate(day)}');
      if (entries.isEmpty) text.writeln('No shifts');
      for (final slot in entries) {
        text.writeln(
          '${slot.timeLabel} · ${names[slot.staffId] ?? 'Unassigned'}${slot.role.isEmpty ? '' : ' · ${slot.role}'}',
        );
        if (slot.breakMinutes > 0) {
          text.writeln('Break: ${slot.breakMinutes} min');
        }
        if (slot.notes.isNotEmpty) text.writeln(slot.notes);
      }
    }
    return text.toString().trim();
  }
}

List<WorkSlot> standardSlots(DateTime week) {
  final monday = mondayOf(week);
  final slots = <WorkSlot>[];
  for (var day = 0; day < 7; day++) {
    final times = switch (day) {
      0 || 3 || 4 => [(960, 1320), (1020, 1320), (1020, 1320)],
      5 ||
      6 => [(660, 1020), (720, 1020), (1020, 1320), (1020, 1320), (1020, 1320)],
      _ => <(int, int)>[],
    };
    for (var index = 0; index < times.length; index++) {
      final date = addDays(monday, day);
      slots.add(
        WorkSlot(
          id: 'template-${dateKey(date)}-$index',
          date: date,
          start: times[index].$1,
          end: times[index].$2,
        ),
      );
    }
  }
  return slots;
}

class SlotPlan {
  SlotPlan({
    required List<StaffMember> staff,
    required List<WorkSlot> slots,
    List<SlotPreset>? presets,
    List<StaffTimeOff> timeOff = const [],
    List<StaffTimeOff> staffTimeOff = const [],
    Map<String, PublishedWeek> published = const {},
    Set<String> editing = const {},
    Set<String>? preparedWeeks,
  }) : staff = List.unmodifiable(staff),
       slots = List.unmodifiable(slots),
       presets = List.unmodifiable(
         uniqueSlotPresets(
           presets ??
               [...standardSlotPresets, ...slots.map(SlotPreset.fromSlot)],
         ),
       ),
       timeOff = List.unmodifiable(timeOff),
       staffTimeOff = List.unmodifiable(staffTimeOff),
       published = Map.unmodifiable(published),
       editing = Set.unmodifiable(editing),
       preparedWeeks = Set.unmodifiable(
         preparedWeeks ??
             {
               ...slots.map((s) => dateKey(mondayOf(s.date))),
               ...published.keys,
             },
       );
  final List<StaffMember> staff;
  final List<WorkSlot> slots;
  final List<SlotPreset> presets;
  final List<StaffTimeOff> timeOff;
  final List<StaffTimeOff> staffTimeOff;
  final Map<String, PublishedWeek> published;
  final Set<String> editing;
  final Set<String> preparedWeeks;
  SlotPlan prepareWeek(DateTime week, {bool replaceDraft = false}) {
    final monday = mondayOf(week), key = dateKey(mondayOf(week));
    if (published.containsKey(key)) return this;
    final existing = inWeek(monday), standard = standardSlots(monday);
    // Preserve an edited draft; only replace an untouched standard template.
    final untouched =
        existing.length == standard.length &&
        existing.every(
          (s) =>
              s.staffId == null &&
              s.breakMinutes == 0 &&
              s.role.isEmpty &&
              s.notes.isEmpty &&
              !s.nextDay &&
              standard.any(
                (t) => t.id == s.id && t.start == s.start && t.end == s.end,
              ),
        );
    if (!replaceDraft && preparedWeeks.contains(key) && !untouched) return this;
    final previous =
        published.values.where((p) => p.week.isBefore(monday)).toList()
          ..sort((a, b) => b.week.compareTo(a.week));
    if (previous.isEmpty && preparedWeeks.contains(key)) return this;
    final defaults = previous.isEmpty
        ? standard
        : [
            for (var i = 0; i < previous.first.slots.length; i++)
              if (!restaurantClosed(previous.first.slots[i].date))
                WorkSlot(
                  id: 'repeat-$key-$i',
                  date: addDays(
                    monday,
                    previous.first.slots[i].date.weekday - 1,
                  ),
                  start: previous.first.slots[i].start,
                  end: previous.first.slots[i].end,
                  nextDay: previous.first.slots[i].nextDay,
                  breakMinutes: previous.first.slots[i].breakMinutes,
                  role: previous.first.slots[i].role,
                  notes: previous.first.slots[i].notes,
                  staffId:
                      staff.any((p) => p.id == previous.first.slots[i].staffId)
                      ? previous.first.slots[i].staffId
                      : null,
                ),
          ];
    return copyWith(
      slots: [
        ...slots.where((s) => dateKey(mondayOf(s.date)) != key),
        ...defaults,
      ],
      preparedWeeks: {...preparedWeeks, key},
    );
  }

  factory SlotPlan.initial(DateTime today) {
    final staff = PlannerData.initial().staff;
    final week = mondayOf(today);
    return SlotPlan(staff: staff, slots: standardSlots(week));
  }
  SlotPlan copyWith({
    List<StaffMember>? staff,
    List<WorkSlot>? slots,
    List<SlotPreset>? presets,
    List<StaffTimeOff>? timeOff,
    List<StaffTimeOff>? staffTimeOff,
    Map<String, PublishedWeek>? published,
    Set<String>? editing,
    Set<String>? preparedWeeks,
  }) => SlotPlan(
    staff: staff ?? this.staff,
    slots: slots ?? this.slots,
    presets: presets ?? this.presets,
    timeOff: timeOff ?? this.timeOff,
    staffTimeOff: staffTimeOff ?? this.staffTimeOff,
    published: published ?? this.published,
    editing: editing ?? this.editing,
    preparedWeeks: preparedWeeks ?? this.preparedWeeks,
  );
  // Use confirmed weeks unless they have an active draft; never count both.
  double monthlyScheduledHours(String staffId, DateTime month) {
    final from = DateTime.utc(month.year, month.month);
    final to = DateTime.utc(month.year, month.month + 1);
    final effective = <String, WorkSlot>{
      for (final slot in slots)
        if (!locked(slot.date)) slot.id: slot,
      for (final entry in published.entries)
        if (!editing.contains(entry.key))
          for (final slot in entry.value.slots) slot.id: slot,
    };
    var minutes = 0.0;
    for (final slot in effective.values) {
      if (slot.staffId != staffId) continue;
      final start = slot.startsAt.isAfter(from) ? slot.startsAt : from;
      final end = slot.endsAt.isBefore(to) ? slot.endsAt : to;
      if (!start.isBefore(end)) continue;
      // Break timing is not recorded; apportion it across month boundaries.
      minutes +=
          end.difference(start).inMinutes *
          (slot.duration - slot.breakMinutes) /
          slot.duration;
    }
    return minutes / 60;
  }

  StaffMember person(String id) => staff.firstWhere((s) => s.id == id);
  List<WorkSlot> inWeek(DateTime week) =>
      slots
          .where(
            (s) =>
                !dateOnly(s.date).isBefore(mondayOf(week)) &&
                dateOnly(s.date).isBefore(addDays(mondayOf(week), 7)),
          )
          .toList()
        ..sort((a, b) {
          final d = a.date.compareTo(b.date);
          return d == 0 ? a.start.compareTo(b.start) : d;
        });
  bool availableFor(WorkSlot slot, String staffId) =>
      !restaurantClosed(slot.date) &&
      staff.any((p) => p.id == staffId) &&
      ![
        ...timeOff,
        ...staffTimeOff,
      ].any((period) => period.staffId == staffId && period.overlaps(slot));

  bool hasTimeOff(String staffId, DateTime day) =>
      [...timeOff, ...staffTimeOff].any(
        (period) =>
            period.staffId == staffId && dateKey(period.date) == dateKey(day),
      );

  List<SlotPreset> availabilityRanges(DateTime day) {
    if (restaurantClosed(day)) return [];
    final all = uniqueSlotPresets([
      ...presets,
      ...slots
          .where((s) => dateKey(s.date) == dateKey(day))
          .map(SlotPreset.fromSlot),
    ]);
    final unique = <String, SlotPreset>{};
    for (final preset in all) {
      unique.putIfAbsent(
        '${preset.start}/${preset.end}/${preset.nextDay}',
        () => preset,
      );
    }
    return unique.values.toList();
  }

  SlotPlan setRangeAvailable(String staffId, WorkSlot range, bool available) {
    if (!staff.any((p) => p.id == staffId)) {
      throw PlanValidationException('Staff member no longer exists');
    }
    if (range.detailsError != null) {
      throw PlanValidationException(range.detailsError!);
    }
    if (!available) {
      return copyWith(
        timeOff: mergeTimeOff([
          ...timeOff,
          ...splitTimeOff(staffId, range.startsAt, range.endsAt),
        ]),
      );
    }
    final remaining = <StaffTimeOff>[];
    for (final period in timeOff) {
      if (period.staffId != staffId || !period.overlaps(range)) {
        remaining.add(period);
      } else {
        if (period.startsAt.isBefore(range.startsAt)) {
          remaining.addAll(
            splitTimeOff(staffId, period.startsAt, range.startsAt),
          );
        }
        if (period.endsAt.isAfter(range.endsAt)) {
          remaining.addAll(splitTimeOff(staffId, range.endsAt, period.endsAt));
        }
      }
    }
    for (final period in staffTimeOff.where(
      (p) => p.staffId == staffId && p.overlaps(range),
    )) {
      if (period.startsAt.isBefore(range.startsAt))
        remaining.addAll(
          splitTimeOff(staffId, period.startsAt, range.startsAt),
        );
      if (range.endsAt.isBefore(period.endsAt))
        remaining.addAll(splitTimeOff(staffId, range.endsAt, period.endsAt));
    }
    return copyWith(
      timeOff: mergeTimeOff(remaining),
      staffTimeOff: staffTimeOff
          .where((p) => p.staffId != staffId || !p.overlaps(range))
          .toList(),
    );
  }

  SlotPlan clearTimeOffDay(String staffId, DateTime day) => copyWith(
    staffTimeOff: staffTimeOff
        .where((p) => p.staffId != staffId || dateKey(p.date) != dateKey(day))
        .toList(),
    timeOff: timeOff
        .where((p) => p.staffId != staffId || dateKey(p.date) != dateKey(day))
        .toList(),
  );

  bool locked(DateTime week) =>
      published.containsKey(dateKey(mondayOf(week))) &&
      !editing.contains(dateKey(mondayOf(week)));
  String? assignmentProblem(WorkSlot slot, String staffId) {
    if (!staff.any((s) => s.id == staffId)) {
      return 'Staff member no longer exists';
    }
    if (!availableFor(slot, staffId)) return 'Unavailable during these hours';
    final candidateWeek = dateKey(mondayOf(slot.date));
    final occupied = [
      ...slots,
      for (final entry in published.entries)
        if (entry.key != candidateWeek && editing.contains(entry.key))
          ...entry.value.slots,
    ];
    for (final other in occupied) {
      if (other.id == slot.id || other.staffId != staffId) continue;
      if (slot.startsAt.isBefore(other.endsAt) &&
          other.startsAt.isBefore(slot.endsAt)) {
        return 'Already assigned: ${shortDate(other.date)}, ${other.timeLabel}';
      }
    }
    return null;
  }

  SlotPlan updateSlot(WorkSlot slot) {
    if (restaurantClosed(slot.date)) {
      throw const PlanValidationException(
        'Restaurant closed on Tuesdays and Wednesdays.',
      );
    }
    if (locked(slot.date)) {
      throw PlanValidationException(
        'Create a draft before editing this published week.',
      );
    }
    final original = slots.where((s) => s.id == slot.id).firstOrNull;
    if (original != null && locked(original.date)) {
      throw PlanValidationException(
        'Create a draft before editing this published week.',
      );
    }
    if (original != null &&
        dateKey(mondayOf(original.date)) != dateKey(mondayOf(slot.date))) {
      throw PlanValidationException(
        'Move a slot within this week. Add a new slot when planning another week.',
      );
    }
    final problem =
        slot.detailsError ??
        (slot.staffId == null ? null : assignmentProblem(slot, slot.staffId!));
    if (problem != null) throw PlanValidationException(problem);
    return copyWith(
      slots: [...slots.where((s) => s.id != slot.id), slot],
      presets: [...presets, SlotPreset.fromSlot(slot)],
    );
  }

  SlotPlan removeSlot(WorkSlot slot) {
    if (locked(slot.date)) {
      throw PlanValidationException(
        'Create a draft before removing a published slot.',
      );
    }
    return copyWith(slots: slots.where((s) => s.id != slot.id).toList());
  }

  SlotPlan loadTemplate(DateTime week) {
    if (locked(week) || inWeek(week).isNotEmpty) {
      throw PlanValidationException('Use the template on an empty draft week.');
    }
    return copyWith(slots: [...slots, ...standardSlots(week)]);
  }

  String? publishProblem(DateTime week) {
    final entries = inWeek(week);
    if (entries.isEmpty) return 'Add slots before publishing this week.';
    final open = entries.where((s) => s.staffId == null).length;
    if (open > 0) {
      return 'Assign all slots before publishing. $open still open.';
    }
    for (final slot in entries) {
      final problem =
          slot.detailsError ?? assignmentProblem(slot, slot.staffId!);
      if (problem != null) {
        return '${person(slot.staffId!).name}: $problem. Review ${shortDate(slot.date)}, ${slot.timeLabel}.';
      }
    }
    return null;
  }

  SlotPlan publishWeek(DateTime week, DateTime now) {
    final problem = publishProblem(week);
    if (problem != null) throw PlanValidationException(problem);
    final monday = mondayOf(week), key = dateKey(mondayOf(week));
    final snapshot = PublishedWeek(
      week: monday,
      slots: inWeek(monday),
      names: {for (final person in staff) person.id: person.name},
      publishedAt: now,
      revision: (published[key]?.revision ?? 0) + 1,
    );
    return copyWith(
      published: {...published, key: snapshot},
      editing: {...editing}..remove(key),
    ).prepareWeek(addDays(monday, 7), replaceDraft: true);
  }

  SlotPlan revise(DateTime week) =>
      copyWith(editing: {...editing, dateKey(mondayOf(week))});
  String encode() => jsonEncode({
    'version': 3,
    'staff': staff.map((s) => s.toJson()).toList(),
    'slots': slots.map((s) => s.toJson()).toList(),
    'timeOff': timeOff.map((a) => a.toJson()).toList(),
    'presets': presets.map((p) => p.toJson()).toList(),
    'published': published.map((k, v) => MapEntry(k, v.toJson())),
    'preparedWeeks': preparedWeeks.toList(),
    'editing': editing.toList(),
  });
  factory SlotPlan.decode(String value) {
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      if (json['version'] != 2 && json['version'] != 3) {
        throw const FormatException('Unsupported version');
      }
      final staff = (json['staff'] as List)
          .map((s) => StaffMember.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList();
      final legacy = json['version'] == 2
          ? (json['availability'] as List)
                .map(
                  (s) => StaffAvailability.fromJson(
                    Map<String, dynamic>.from(s as Map),
                  ),
                )
                .toList()
          : <StaffAvailability>[];
      if (legacy.map((a) => a.key).toSet().length != legacy.length ||
          legacy.any(
            (a) =>
                !staff.any((p) => p.id == a.staffId) ||
                a.start < 0 ||
                a.start >= 1440 ||
                a.end <= a.start ||
                a.end > a.start + 1440,
          )) {
        throw const FormatException('Invalid saved availability');
      }
      final plan = SlotPlan(
        presets: json.containsKey('presets')
            ? (json['presets'] as List)
                  .map(
                    (p) => SlotPreset.fromJson(
                      Map<String, dynamic>.from(p as Map),
                    ),
                  )
                  .toList()
            : null,
        staff: staff,
        slots: (json['slots'] as List)
            .map((s) => WorkSlot.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList(),
        timeOff: json['version'] == 2
            ? migrateAvailability(legacy, staff)
            : (json['timeOff'] as List)
                  .map(
                    (s) => StaffTimeOff.fromJson(
                      Map<String, dynamic>.from(s as Map),
                    ),
                  )
                  .toList(),
        published: (json['published'] as Map).map(
          (k, v) => MapEntry(
            k as String,
            PublishedWeek.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
        preparedWeeks: json['preparedWeeks'] == null
            ? null
            : Set<String>.from(json['preparedWeeks'] as List),
        editing: Set<String>.from(json['editing'] as List),
      );
      if (plan.presets.any(
            (p) => p.onDay(DateTime(2000), 'check').detailsError != null,
          ) ||
          plan.staff.map((s) => s.id).toSet().length != plan.staff.length ||
          plan.staff.any((s) => s.id.isEmpty || s.name.trim().isEmpty) ||
          plan.slots.map((s) => s.id).toSet().length != plan.slots.length ||
          plan.slots.any(
            (s) =>
                s.id.isEmpty ||
                s.detailsError != null ||
                (s.staffId != null &&
                    !plan.staff.any((p) => p.id == s.staffId)),
          ) ||
          plan.timeOff.any(
            (a) =>
                !plan.staff.any((s) => s.id == a.staffId) ||
                a.start < 0 ||
                a.start >= 1440 ||
                a.end <= a.start ||
                a.end > 1440,
          )) {
        throw const FormatException('Invalid saved schedule');
      }
      for (final entry in plan.published.entries) {
        final snapshot = entry.value;
        if (entry.key != dateKey(mondayOf(snapshot.week)) ||
            snapshot.week.weekday != DateTime.monday ||
            snapshot.revision < 1 ||
            snapshot.slots.isEmpty ||
            snapshot.slots.map((s) => s.id).toSet().length !=
                snapshot.slots.length ||
            snapshot.slots.any(
              (s) =>
                  s.detailsError != null ||
                  s.staffId == null ||
                  (snapshot.names[s.staffId]?.trim().isEmpty ?? true) ||
                  dateKey(mondayOf(s.date)) != entry.key,
            )) {
          throw const FormatException('Invalid published schedule');
        }
      }
      // Update untouched old templates; preserve customized and published weeks.
      final weeks = plan.slots.map((s) => dateKey(mondayOf(s.date))).toSet();
      var migrated = plan;
      for (final key in weeks) {
        if (plan.published.containsKey(key)) continue;
        final week = DateTime.parse(key);
        final entries = plan.inWeek(week);
        final expected = standardSlots(week);
        final oldSlots = <WorkSlot>[];
        for (final slot in expected) {
          final weekend = slot.date.weekday >= DateTime.saturday;
          final index = int.parse(slot.id.split('-').last);
          oldSlots.add(
            WorkSlot(
              id: weekend && index >= 2
                  ? 'template-${dateKey(slot.date)}-${index + 1}'
                  : slot.id,
              date: slot.date,
              start: slot.start,
              end: slot.end,
            ),
          );
          if (weekend && index == 1)
            oldSlots.add(
              WorkSlot(
                id: 'template-${dateKey(slot.date)}-2',
                date: slot.date,
                start: 720,
                end: 1020,
              ),
            );
        }
        if (entries.length == oldSlots.length &&
            entries.every(
              (s) =>
                  s.staffId == null &&
                  s.breakMinutes == 0 &&
                  s.role.isEmpty &&
                  s.notes.isEmpty &&
                  !s.nextDay &&
                  oldSlots.any(
                    (o) => o.id == s.id && o.start == s.start && o.end == s.end,
                  ),
            )) {
          migrated = migrated.copyWith(
            slots: [
              ...migrated.slots.where((s) => dateKey(mondayOf(s.date)) != key),
              ...expected,
            ],
          );
        }
      }
      return migrated.copyWith(timeOff: mergeTimeOff(migrated.timeOff));
    } catch (_) {
      throw const FormatException('Saved slot plan could not be read');
    }
  }
}

abstract interface class SlotStore {
  Future<SlotPlan> read();
  Future<void> write(SlotPlan plan);
}

/// Implemented by stores that can notify the UI when another device changes
/// the shared roster.
abstract interface class LiveSlotStore implements SlotStore {
  Stream<void> watch();
}

class LocalSlotStore implements SlotStore {
  LocalSlotStore({DateTime? today}) : today = today ?? DateTime.now();
  final DateTime today;
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static const key = 'karikaala.slots.v3';
  static const previousKey = 'karikaala.slots.v2';
  @override
  Future<SlotPlan> read() async {
    final saved = await _preferences.getString(key);
    if (saved != null) return SlotPlan.decode(saved);
    final v2 = await _preferences.getString(previousKey);
    if (v2 != null) return SlotPlan.decode(v2);
    final previous = await _preferences.getString(LocalPlannerStore.key);
    if (previous == null) return SlotPlan.initial(today);
    final old = PlannerData.decode(previous);
    return SlotPlan(
      staff: old.staff,
      slots: old.shifts
          .map(
            (s) => WorkSlot(
              id: s.id,
              date: s.date,
              start: s.start,
              end: s.end,
              nextDay: s.nextDay,
              staffId: s.staffId,
              breakMinutes: s.breakMinutes,
              role: s.role,
              notes: s.notes,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> write(SlotPlan plan) =>
      _preferences.setString(key, plan.encode());
}
