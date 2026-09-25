import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'planner_model.dart';

// Keep existing FlutLab onboarding test imports working.
export 'onboarding_app.dart' show OnboardingApp;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(StaffPlannerApp(store: LocalPlannerStore()));
}

const plannerGreen = Color(0xFF175E4C);

class StaffPlannerApp extends StatelessWidget {
  const StaffPlannerApp({required this.store, this.today, super.key});
  final PlannerStore store;
  final DateTime? today;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Staff Planner',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: plannerGreen),
          scaffoldBackgroundColor: const Color(0xFFF6F7F3),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF6F7F3)),
          inputDecorationTheme:
              const InputDecorationTheme(border: OutlineInputBorder()),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  backgroundColor: plannerGreen,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 48))),
        ),
        home: PlannerHome(store: store, today: today ?? DateTime.now()),
      );
}

class PlannerHome extends StatefulWidget {
  const PlannerHome({required this.store, required this.today, super.key});
  final PlannerStore store;
  final DateTime today;
  @override
  State<PlannerHome> createState() => _PlannerHomeState();
}

class _PlannerHomeState extends State<PlannerHome> {
  PlannerData? _data;
  bool _loadFailed = false;
  int _tab = 0;
  late DateTime _week = mondayOf(widget.today);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final data = await widget.store.read();
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _save(PlannerData data) async {
    await widget.store.write(data);
    if (mounted) setState(() => _data = data);
  }

  Future<void> _editShift(DateTime day, [Shift? shift]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ShiftEditor(
              data: _data!,
              day: day,
              shift: shift,
              onSave: _save,
            )));
  }

  Future<void> _editStaff([StaffMember? member]) async {
    await showDialog<void>(
        context: context,
        builder: (_) => StaffEditor(
              data: _data!,
              member: member,
              onSave: _save,
            ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loadFailed) {
      return Scaffold(
          appBar: AppBar(title: const Text('Staff Planner')),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                          'Your saved planner could not be loaded. Your saved data has not been changed.',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: _load, child: const Text('Try again')),
                    ],
                  ))));
    }
    if (_data == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
          title: Text(_tab == 0 ? 'Staff Planner' : 'Your staff'),
          actions: [
            if (_tab == 0)
              TextButton(
                  onPressed: () =>
                      setState(() => _week = mondayOf(widget.today)),
                  child: const Text('This week'))
          ]),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: _tab == 0 ? _planner() : _staffList()))),
      bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() => _tab = value),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Week plan'),
            NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Staff'),
          ]),
    );
  }

  Widget _planner() {
    final data = _data!;
    final shifts = data.inWeek(_week);
    final minutes =
        shifts.fold<int>(0, (sum, shift) => sum + shift.plannedMinutes);
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(children: [
            IconButton(
                tooltip: 'Previous week',
                onPressed: () => setState(() => _week = addDays(_week, -7)),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
                child: Column(children: [
              Text('${shortDate(_week)} – ${shortDate(addDays(_week, 6))}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              Text(
                  _week.year == addDays(_week, 6).year
                      ? '${_week.year} · Monday to Sunday'
                      : '${_week.year} / ${addDays(_week, 6).year} · Monday to Sunday',
                  textAlign: TextAlign.center),
            ])),
            IconButton(
                tooltip: 'Next week',
                onPressed: () => setState(() => _week = addDays(_week, 7)),
                icon: const Icon(Icons.chevron_right)),
          ]),
          const SizedBox(height: 20),
          Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: plannerGreen, borderRadius: BorderRadius.circular(20)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('YOUR WEEK AT A GLANCE',
                        style: TextStyle(
                            color: Color(0xFFC9E7DE),
                            fontSize: 12,
                            letterSpacing: 1.3)),
                    const SizedBox(height: 8),
                    Text(
                        '${shifts.length} shifts · ${(minutes / 60).toStringAsFixed(1)} hours',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text('Planned hours, excluding breaks',
                        style: TextStyle(color: Color(0xFFD4E6DF))),
                  ])),
          const SizedBox(height: 12),
          const Text(
              'Saved on this device only. Plans are not yet shared with staff.',
              style: TextStyle(fontSize: 12, color: Color(0xFF54635C))),
          if (data.staff.any((s) => s.sample)) ...[
            const SizedBox(height: 12),
            _Notice(
                text:
                    'Sample staff are included to get you started. Open Staff to rename them or add your team.',
                action: TextButton(
                    onPressed: () => setState(() => _tab = 1),
                    child: const Text('Edit staff'))),
          ],
          const SizedBox(height: 16),
          for (var index = 0; index < 7; index++)
            _dayCard(addDays(_week, index)),
        ]);
  }

  Widget _dayCard(DateTime day) {
    final shifts = _data!.onDay(day);
    final isToday = dateKey(day) == dateKey(widget.today);
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: Colors.white,
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(dayNames[day.weekday - 1],
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(shortDate(day),
                        style: const TextStyle(color: Color(0xFF58665F))),
                    if (isToday)
                      const Chip(
                          label: Text('Today'),
                          visualDensity: VisualDensity.compact),
                  ]),
              if (shifts.isEmpty)
                const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('No shifts planned',
                        style: TextStyle(color: Color(0xFF66736D)))),
              for (final shift in shifts)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Material(
                      color: const Color(0xFFF1F6F3),
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                          key: ValueKey('shift-${shift.id}'),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          title: Text(_data!.member(shift.staffId).name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${shift.timeLabel}\n${shift.role.isEmpty ? 'No role set' : shift.role} · ${shift.breakMinutes} min break${shift.notes.isEmpty ? '' : '\n${shift.notes}'}'),
                          trailing: const Icon(Icons.edit_outlined, size: 20),
                          onTap: () => _editShift(day, shift)),
                    )),
              const SizedBox(height: 8),
              TextButton.icon(
                  key: ValueKey('add-${dateKey(day)}'),
                  onPressed: () => _editShift(day),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add staff / shift')),
            ])));
  }

  Widget _staffList() => ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'Choose these names when planning each day. Renaming a person updates their name on existing shifts.'),
        const SizedBox(height: 16),
        FilledButton.icon(
            key: const ValueKey('add-staff'),
            onPressed: _editStaff,
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add staff member')),
        const SizedBox(height: 16),
        for (final person in _data!.staff)
          Card(
              color: Colors.white,
              child: ListTile(
                title: Text(person.name),
                subtitle: Text(person.sample
                    ? 'Sample staff · Tap to rename'
                    : 'Tap to edit name'),
                leading: CircleAvatar(
                    backgroundColor: const Color(0xFFDDECE4),
                    child: Text(person.name.characters.first.toUpperCase())),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editStaff(person),
              )),
      ]);
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.action, this.error = false});
  final String text;
  final Widget? action;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: error ? const Color(0xFFFFEDEA) : const Color(0xFFEEF0E8),
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text,
            style: TextStyle(
                color:
                    error ? const Color(0xFF9B2424) : const Color(0xFF405345))),
        if (action != null) action!,
      ]));
}

class ShiftEditor extends StatefulWidget {
  const ShiftEditor(
      {required this.data,
      required this.day,
      required this.onSave,
      this.shift,
      super.key});
  final PlannerData data;
  final DateTime day;
  final Shift? shift;
  final Future<void> Function(PlannerData) onSave;
  @override
  State<ShiftEditor> createState() => _ShiftEditorState();
}

class _ShiftEditorState extends State<ShiftEditor> {
  final _form = GlobalKey<FormState>();
  late DateTime _date = widget.shift?.date ?? widget.day;
  late Set<String> _selected =
      widget.shift == null ? {} : {widget.shift!.staffId};
  late bool _nextDay = widget.shift?.nextDay ?? false;
  late final _start =
      TextEditingController(text: clock(widget.shift?.start ?? 540));
  late final _end =
      TextEditingController(text: clock(widget.shift?.end ?? 1020));
  late final _break =
      TextEditingController(text: '${widget.shift?.breakMinutes ?? 30}');
  late final _role = TextEditingController(text: widget.shift?.role ?? '');
  late final _notes = TextEditingController(text: widget.shift?.notes ?? '');
  bool _saving = false;
  String? _error;
  String _search = '';
  @override
  void dispose() {
    for (final controller in [_start, _end, _break, _role, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _minutes(String? value) {
    if (value == null || !RegExp(r'^\d{1,2}:\d{2}$').hasMatch(value.trim()))
      return null;
    final parts = value.trim().split(':').map(int.parse).toList();
    if (parts[0] > 23 || parts[1] > 59) return null;
    return parts[0] * 60 + parts[1];
  }

  String? _validateTime(String? value) =>
      _minutes(value) == null ? 'Use 24-hour time, e.g. 09:00' : null;
  Future<void> _pickTime(TextEditingController controller) async {
    final minutes = _minutes(controller.text) ?? 540;
    final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!));
    if (time != null) controller.text = clock(time.hour * 60 + time.minute);
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime(_date.year - 10),
        lastDate: DateTime(_date.year + 10, 12, 31));
    if (date != null && mounted) setState(() => _date = date);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    if (_selected.isEmpty) {
      setState(() => _error = 'Select at least one staff member.');
      return;
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final additions = _selected
        .map((id) => Shift(
              id: widget.shift?.id ?? 'shift-$stamp-$id',
              staffId: id,
              date: _date,
              start: _minutes(_start.text)!,
              end: _minutes(_end.text)!,
              nextDay: _nextDay,
              breakMinutes: int.parse(_break.text.trim()),
              role: _role.text.trim(),
              notes: _notes.text.trim(),
            ))
        .toList();
    for (final shift in additions) {
      final error =
          widget.data.validateShift(shift, replacingId: widget.shift?.id);
      if (error != null) {
        setState(() => _error = error);
        return;
      }
    }
    final updated = widget.data.copyWith(shifts: [
      ...widget.data.shifts.where((s) => s.id != widget.shift?.id),
      ...additions,
    ]);
    setState(() => _saving = true);
    try {
      await widget.onSave(updated);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Changes could not be saved. Please try again.';
        });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Remove this shift?'),
              content: Text(
                  '${widget.data.member(widget.shift!.staffId).name}\n${shortDate(widget.shift!.date)} · ${widget.shift!.timeLabel}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep shift')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Remove shift'))
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(widget.data.copyWith(
          shifts: widget.data.shifts
              .where((s) => s.id != widget.shift!.id)
              .toList()));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'The shift could not be removed. Please try again.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.data.staff
        .where((p) => p.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();
    return PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(
              title: Text(widget.shift == null ? 'Add shift' : 'Edit shift')),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: AbsorbPointer(
                          absorbing: _saving,
                          child: Form(
                              key: _form,
                              child: ListView(
                                padding: const EdgeInsets.all(20),
                                children: [
                                  OutlinedButton.icon(
                                      onPressed: _pickDate,
                                      icon: const Icon(
                                          Icons.calendar_today_outlined),
                                      label: Text(
                                          '${dayNames[_date.weekday - 1]}, ${shortDate(_date)} ${_date.year}')),
                                  const SizedBox(height: 20),
                                  Text('Select staff (${_selected.length})',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  Text(widget.shift == null
                                      ? 'Choose one or more names. These shift details apply to each selected person.'
                                      : 'Choose the person assigned to this shift.'),
                                  const SizedBox(height: 12),
                                  TextField(
                                      onChanged: (value) =>
                                          setState(() => _search = value),
                                      decoration: const InputDecoration(
                                          labelText: 'Search staff',
                                          prefixIcon: Icon(Icons.search))),
                                  const SizedBox(height: 8),
                                  if (staff.isEmpty)
                                    const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Text(
                                            'No matching staff. Add a person from the Staff tab.')),
                                  for (final person in staff)
                                    CheckboxListTile(
                                        key: ValueKey('choose-${person.id}'),
                                        contentPadding: EdgeInsets.zero,
                                        value: _selected.contains(person.id),
                                        title: Text(person.name),
                                        subtitle: person.sample
                                            ? const Text('Sample name')
                                            : null,
                                        onChanged: (value) => setState(() {
                                              if (widget.shift != null) {
                                                _selected = value == true
                                                    ? {person.id}
                                                    : {};
                                              } else if (value == true) {
                                                _selected.add(person.id);
                                              } else {
                                                _selected.remove(person.id);
                                              }
                                            })),
                                  const SizedBox(height: 20),
                                  Text('Shift details',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 12),
                                  _timeField(
                                      'Start time', _start, 'start-time'),
                                  const SizedBox(height: 16),
                                  _timeField('End time', _end, 'end-time'),
                                  SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('Ends next day'),
                                      subtitle: const Text(
                                          'Turn on for shifts that finish after midnight.'),
                                      value: _nextDay,
                                      onChanged: (value) =>
                                          setState(() => _nextDay = value)),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                      key: const ValueKey('break-minutes'),
                                      controller: _break,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                      decoration: const InputDecoration(
                                          labelText: 'Unpaid break (minutes)',
                                          hintText: 'e.g. 30'),
                                      validator: (value) =>
                                          int.tryParse(value?.trim() ?? '') ==
                                                  null
                                              ? 'Enter break minutes, or 0.'
                                              : null),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                      key: const ValueKey('shift-role'),
                                      controller: _role,
                                      maxLength: 60,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      decoration: const InputDecoration(
                                          labelText: 'Role / area (optional)',
                                          hintText:
                                              'e.g. Kitchen, Service, Bar')),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                      key: const ValueKey('shift-notes'),
                                      controller: _notes,
                                      minLines: 2,
                                      maxLines: 4,
                                      maxLength: 300,
                                      decoration: const InputDecoration(
                                          labelText: 'Shift notes (optional)',
                                          hintText:
                                              'e.g. Prepare the terrace before service')),
                                  if (_error != null) ...[
                                    const SizedBox(height: 12),
                                    _Notice(text: _error!, error: true)
                                  ],
                                  const SizedBox(height: 20),
                                  FilledButton(
                                      key: const ValueKey('save-shift'),
                                      onPressed: _saving ? null : _save,
                                      child: Text(_saving
                                          ? 'Saving…'
                                          : widget.shift == null
                                              ? 'Save shifts'
                                              : 'Save changes')),
                                  TextButton(
                                      onPressed: _saving
                                          ? null
                                          : () => Navigator.pop(context),
                                      child: const Text('Cancel')),
                                  if (widget.shift != null)
                                    TextButton.icon(
                                        key: const ValueKey('delete-shift'),
                                        onPressed: _saving ? null : _delete,
                                        icon: const Icon(Icons.delete_outline),
                                        label: const Text('Remove shift')),
                                ],
                              )))))),
        ));
  }

  Widget _timeField(
          String label, TextEditingController controller, String key) =>
      TextFormField(
        key: ValueKey(key),
        controller: controller,
        keyboardType: TextInputType.datetime,
        decoration: InputDecoration(
            labelText: label,
            hintText: 'HH:MM',
            suffixIcon: IconButton(
                tooltip: 'Choose $label',
                onPressed: () => _pickTime(controller),
                icon: const Icon(Icons.schedule))),
        validator: _validateTime,
      );
}

class StaffEditor extends StatefulWidget {
  const StaffEditor(
      {required this.data, required this.onSave, this.member, super.key});
  final PlannerData data;
  final StaffMember? member;
  final Future<void> Function(PlannerData) onSave;
  @override
  State<StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends State<StaffEditor> {
  late final _name = TextEditingController(text: widget.member?.name ?? '');
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a staff name.');
      return;
    }
    if (widget.data.staff.any((p) =>
        p.id != widget.member?.id &&
        p.name.toLowerCase() == name.toLowerCase())) {
      setState(
          () => _error = 'This name already exists. Add a surname or initial.');
      return;
    }
    final person = StaffMember(
        id: widget.member?.id ??
            'staff-${DateTime.now().microsecondsSinceEpoch}',
        name: name);
    final staff = widget.member == null
        ? [...widget.data.staff, person]
        : widget.data.staff.map((p) => p.id == person.id ? person : p).toList();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(widget.data.copyWith(staff: staff));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Name could not be saved. Please try again.';
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
            widget.member == null ? 'Add staff member' : 'Edit staff name'),
        scrollable: true,
        content: TextField(
            key: const ValueKey('staff-name'),
            controller: _name,
            autofocus: true,
            enabled: !_saving,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
                labelText: 'Staff name',
                hintText: 'e.g. First name Last name',
                errorText: _error)),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              key: const ValueKey('save-staff'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save name'))
        ],
      ));
}
