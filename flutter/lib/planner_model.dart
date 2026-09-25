import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);
DateTime mondayOf(DateTime date) => addDays(dateOnly(date), 1 - date.weekday);
String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String clock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
const dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday'
];
const monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];
String shortDate(DateTime date) => '${date.day} ${monthNames[date.month - 1]}';

class StaffMember {
  const StaffMember(
      {required this.id, required this.name, this.sample = false});
  final String id;
  final String name;
  final bool sample;
  Map<String, Object> toJson() => {'id': id, 'name': name, 'sample': sample};
  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        id: json['id'] as String,
        name: json['name'] as String,
        sample: json['sample'] == true,
      );
}

class Shift {
  const Shift(
      {required this.id,
      required this.staffId,
      required this.date,
      required this.start,
      required this.end,
      this.nextDay = false,
      this.breakMinutes = 0,
      this.role = '',
      this.notes = ''});
  final String id;
  final String staffId;
  final DateTime date;
  final int start;
  final int end;
  final bool nextDay;
  final int breakMinutes;
  final String role;
  final String notes;
  int get duration => end + (nextDay ? 1440 : 0) - start;
  int get plannedMinutes => duration - breakMinutes;
  // Calendar wall-clock minutes; this planner is not a payroll time clock.
  DateTime get startsAt =>
      DateTime.utc(date.year, date.month, date.day, start ~/ 60, start % 60);
  DateTime get endsAt => startsAt.add(Duration(minutes: duration));
  String get timeLabel =>
      '${clock(start)} – ${clock(end)}${nextDay ? ' (+1 day)' : ''}';
  Map<String, Object> toJson() => {
        'id': id,
        'staffId': staffId,
        'date': dateKey(date),
        'start': start,
        'end': end,
        'nextDay': nextDay,
        'breakMinutes': breakMinutes,
        'role': role,
        'notes': notes
      };
  factory Shift.fromJson(Map<String, dynamic> json) => Shift(
        id: json['id'] as String,
        staffId: json['staffId'] as String,
        date: DateTime.parse(json['date'] as String),
        start: json['start'] as int,
        end: json['end'] as int,
        nextDay: json['nextDay'] == true,
        breakMinutes: json['breakMinutes'] as int,
        role: json['role'] as String,
        notes: json['notes'] as String,
      );
}

class PlannerData {
  PlannerData({required List<StaffMember> staff, required List<Shift> shifts})
      : staff = List.unmodifiable(staff),
        shifts = List.unmodifiable(shifts);
  final List<StaffMember> staff;
  final List<Shift> shifts;
  factory PlannerData.initial() => PlannerData(staff: const [
        StaffMember(id: 'sample-alex', name: 'Alex', sample: true),
        StaffMember(id: 'sample-maria', name: 'Maria', sample: true),
        StaffMember(id: 'sample-sam', name: 'Sam', sample: true),
      ], shifts: []);
  PlannerData copyWith({List<StaffMember>? staff, List<Shift>? shifts}) =>
      PlannerData(staff: staff ?? this.staff, shifts: shifts ?? this.shifts);
  StaffMember member(String id) =>
      staff.firstWhere((person) => person.id == id);
  List<Shift> onDay(DateTime day) =>
      shifts.where((s) => dateKey(s.date) == dateKey(day)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  List<Shift> inWeek(DateTime monday) => shifts
      .where((s) =>
          !dateOnly(s.date).isBefore(monday) &&
          dateOnly(s.date).isBefore(addDays(monday, 7)))
      .toList();

  String? validateShift(Shift shift, {String? replacingId}) {
    if (!staff.any((s) => s.id == shift.staffId))
      return 'Select a staff member.';
    if (shift.start < 0 ||
        shift.start >= 1440 ||
        shift.end < 0 ||
        shift.end >= 1440 ||
        shift.duration <= 0 ||
        shift.duration >= 1440) {
      return 'End time must follow start time. For an overnight shift, turn on “Ends next day”. Shifts must be shorter than 24 hours.';
    }
    if (shift.breakMinutes < 0 || shift.breakMinutes >= shift.duration) {
      return 'Break must be shorter than the shift and cannot be negative.';
    }
    for (final other in shifts) {
      if (other.id == replacingId || other.staffId != shift.staffId) continue;
      if (shift.startsAt.isBefore(other.endsAt) &&
          other.startsAt.isBefore(shift.endsAt)) {
        return '${member(shift.staffId).name} already has an overlapping shift (${shortDate(other.date)}, ${other.timeLabel}).';
      }
    }
    return null;
  }

  String encode() => jsonEncode({
        'version': 1,
        'staff': staff.map((s) => s.toJson()).toList(),
        'shifts': shifts.map((s) => s.toJson()).toList()
      });
  factory PlannerData.decode(String? value) {
    if (value == null) return PlannerData.initial();
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      if (json['version'] != 1)
        throw const FormatException('Unknown planner version');
      final data = PlannerData(
        staff: (json['staff'] as List)
            .map((s) => StaffMember.fromJson(s as Map<String, dynamic>))
            .toList(),
        shifts: (json['shifts'] as List)
            .map((s) => Shift.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
      if (data.staff.any((s) => s.id.isEmpty || s.name.trim().isEmpty) ||
          data.staff.map((s) => s.id).toSet().length != data.staff.length ||
          data.shifts.map((s) => s.id).toSet().length != data.shifts.length ||
          data.shifts.any((s) =>
              s.id.isEmpty ||
              data.validateShift(s, replacingId: s.id) != null)) {
        throw const FormatException('Invalid planner data');
      }
      return data;
    } catch (_) {
      // Do not silently overwrite an unreadable staff schedule with demo data.
      throw const FormatException('Saved planner could not be read');
    }
  }
}

abstract interface class PlannerStore {
  Future<PlannerData> read();
  Future<void> write(PlannerData data);
}

class LocalPlannerStore implements PlannerStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static const key = 'karikaala.planner.v1';
  @override
  Future<PlannerData> read() async =>
      PlannerData.decode(await _preferences.getString(key));
  @override
  Future<void> write(PlannerData data) =>
      _preferences.setString(key, data.encode());
}
