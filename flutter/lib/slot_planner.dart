import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'planner_model.dart';
import 'slot_model.dart';
import 'planner_theme.dart';
import 'slot_picker.dart';
import 'slot_row.dart';
import 'published_roster.dart';
import 'staff_availability.dart';
import 'weekly_board.dart';
import 'staff_agenda.dart';

const staffSelfAvailabilityEnabled = true;

class SlotPlannerApp extends StatelessWidget {
  const SlotPlannerApp({required this.store, this.today, super.key});
  final SlotStore store;
  final DateTime? today;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Staff Planner',
    debugShowCheckedModeBanner: false,
    theme: plannerTheme(),
    home: ManagerAuthGate(store: store, today: today ?? DateTime.now()),
  );
}

class InfoBox extends StatelessWidget {
  const InfoBox(this.text, {this.error = false, super.key});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFCF1F0) : rosterSurface,
      border: Border.all(color: error ? const Color(0xFFE8C9C7) : rosterLine),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: error ? const Color(0xFF9C302B) : rosterMuted),
    ),
  );
}

class SlotHome extends StatefulWidget {
  const SlotHome({required this.store, required this.today, super.key});
  final SlotStore store;
  final DateTime today;
  @override
  State<SlotHome> createState() => _SlotHomeState();
}

class _SlotHomeState extends State<SlotHome> {
  SlotPlan? _plan;
  late DateTime _week = mondayOf(widget.today);
  bool _loadError = false, _busy = false;
  String? _error;
  int _tab = 0;
  bool? _weekBoardOverride;
  int _staffCalendarReset = 0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _availabilityWatch;
  StreamSubscription<void>? _rosterWatch;
  @override
  void dispose() {
    _availabilityWatch?.cancel();
    _rosterWatch?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.store case final LiveSlotStore liveStore) {
      _rosterWatch = liveStore.watch().listen((_) {
        if (mounted && !_busy) _load();
      }, onError: (_) {});
    }
    if (staffSelfAvailabilityEnabled) {
      var first = true;
      _availabilityWatch = FirebaseFirestore.instance
          .collection('staffAvailability')
          .snapshots()
          .listen((_) {
            if (first) {
              first = false;
              return;
            }
            if (mounted && !_busy) _load();
          }, onError: (_) {});
    }
  }

  Future<void> _load() async {
    setState(() => _loadError = false);
    try {
      final saved = await widget.store.read();
      final plan = saved.prepareWeek(_week);
      if (!identical(saved, plan)) await widget.store.write(plan);
      if (mounted) setState(() => _plan = plan);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
  }

  Future<void> _openWeek(DateTime week) async {
    await _action(() async {
      final next = _plan!.prepareWeek(week);
      if (!identical(next, _plan)) await _commit(next);
      if (mounted)
        setState(() {
          _week = week;
          _error = null;
        });
    });
  }

  Future<void> _commit(SlotPlan plan) async {
    await widget.store.write(plan);
    if (mounted) {
      setState(() {
        _plan = plan;
        _error = null;
      });
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PlanValidationException
              ? error.message
              : 'Changes could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(WorkSlot slot) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            SlotAssignment(slot: slot, getPlan: () => _plan!, onSave: _commit),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editSlot(DateTime day) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SlotPresetPicker(
          day: day,
          getPlan: () => _plan!,
          onSave: _commit,
          createNew: (pickerContext) async {
            var saved = false;
            await Navigator.push(
              pickerContext,
              MaterialPageRoute<void>(
                builder: (_) => SlotDetails(
                  day: day,
                  plan: _plan!,
                  onSave: (plan) async {
                    await _commit(plan);
                    saved = true;
                  },
                ),
              ),
            );
            return saved;
          },
        ),
      ),
    );
  }

  Future<void> _saveAvailability(SlotPlan plan) async {
    if (_busy) {
      throw PlanValidationException('Please wait for the current save.');
    }
    setState(() => _busy = true);
    try {
      await _commit(plan);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _staff([StaffMember? person]) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          SlotStaffEditor(plan: _plan!, person: person, onSave: _commit),
    );
  }

  Future<void> _publish() async {
    final problem = _plan!.publishProblem(_week);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final previous = _plan!.published[dateKey(_week)];
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          previous == null ? 'Publish this week?' : 'Publish the revised week?',
        ),
        content: Text(
          '${shortDate(_week)} – ${shortDate(addDays(_week, 6))}\n${_plan!.inWeek(_week).length} slots assigned.\n\nThis saves a confirmed version. Staff access will be available after cloud setup is completed.${previous == null ? '' : '\n\nThis replaces published version ${previous.revision}.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep draft'),
          ),
          FilledButton(
            key: const ValueKey('confirm-publish'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publish week'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await _action(() async {
        await _commit(_plan!.publishWeek(_week, DateTime.now()));
        if (mounted) setState(() => _tab = 2);
      });
    }
  }

  Future<void> _copy(PublishedWeek publication) async {
    await Clipboard.setData(ClipboardData(text: publication.rosterText()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Published roster copied. Paste it into your staff chat.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final compactDesktop = MediaQuery.sizeOf(context).width >= 800;
    final showWeekBoard = _weekBoardOverride ?? MediaQuery.sizeOf(context).width >= 800;
    if (_loadError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Staff Planner')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Your saved plan could not be loaded. Saved data has not been replaced.',
                ),
                FilledButton(onPressed: _load, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      );
    }
    if (_plan == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: _tab == 0 && showWeekBoard ? const Color(0xFFF5F7F5) : Colors.white,
      appBar: AppBar(
        toolbarHeight: compactDesktop ? 64 : null,
        title: Text(_tab == 3 ? 'Messages' : 'Staff Planner', style: compactDesktop ? const TextStyle(fontSize: 22, fontWeight: FontWeight.w700) : null),
        actions: [
          IconButton(
            tooltip: 'Reload plan',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.sync),
          ),
          if (cloudRosterEnabled)
            IconButton(
              tooltip: 'Staff login access',
              onPressed: _busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => StaffLoginLinks(
                          store: widget.store,
                          getPlan: () => _plan!,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.manage_accounts_outlined),
            ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _busy ? null : () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
          if (_tab != 3)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      if (_tab == 1) {
                        _staffCalendarReset++;
                      } else {
                        _week = mondayOf(widget.today);
                      }
                    }),
              child: Text(_tab == 1 ? 'This month' : 'This week'),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: (_tab == 0 && showWeekBoard) || _tab == 1 ? double.infinity : 760),
            child: AbsorbPointer(
              absorbing: _busy,
              child: Column(
                children: [
                  if (_tab == 0 && !compactDesktop)
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Align(alignment: Alignment.centerRight, child: _viewSwitch(showWeekBoard))),
                  if (_tab == 0 || _tab == 2)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => _openWeek(addDays(_week, -7)),
                            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                              Icon(Icons.chevron_left),
                              const Text('Previous week', style: TextStyle(fontSize: 14)),
                            ]),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '${shortDate(_week)} – ${shortDate(addDays(_week, 6))}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: compactDesktop ? 22 : 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${_week.year == addDays(_week, 6).year ? _week.year : '${_week.year}/${addDays(_week, 6).year}'} · Monday to Sunday',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 13, color: rosterMuted),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _openWeek(addDays(_week, 7)),
                            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                              Icon(Icons.chevron_right),
                              const Text('Next week', style: TextStyle(fontSize: 14)),
                            ]),
                          ),
                          if (_tab == 0 && compactDesktop) _viewSwitch(showWeekBoard),
                        ],
                      ),
                    ),
                  if (_busy) const LinearProgressIndicator(),
                  Expanded(
                    child: IndexedStack(
                      index: _tab,
                      children: [
                        showWeekBoard
                            ? WeeklyBoard(plan: _plan!, week: _week,
                                onPick: _pick, onAdd: _editSlot,
                                onPublish: _publish,
                                onRevise: () => _action(() => _commit(_plan!.revise(_week))),
                                onTemplate: () => _action(() => _commit(_plan!.loadTemplate(_week))),
                                error: _error)
                            : _weeklyPlan(),
                        StaffAvailabilityPanel(
                          getPlan: () => _plan!,
                          onSave: _saveAvailability,
                          onEdit: _staff,
                          today: widget.today,
                          resetToken: _staffCalendarReset,
                        ),
                        _published(),
                        _tab == 3
                            ? _MessagingInbox(
                                manager: true,
                                getPlan: () => _plan!,
                              )
                            : const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: rosterLine)),
        ),
        child: NavigationBar(
          height: compactDesktop ? 76 : null,
          selectedIndex: _tab,
          onDestinationSelected: _busy
              ? null
              : (tab) => setState(() {
                  _tab = tab;
                  _error = null;
                }),
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.view_week_outlined),
              label: 'Plan',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              label: 'Staff',
            ),
            NavigationDestination(
              icon: Icon(Icons.task_alt),
              label: 'Published',
            ),
            const NavigationDestination(
              icon: _MessagingIcon(),
              label: 'Messages',
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewSwitch(bool showWeekBoard) => SegmentedButton<bool>(
    style: SegmentedButton.styleFrom(minimumSize: const Size(48, 44),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), textStyle: const TextStyle(fontSize: 14),
      iconSize: 18, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    segments: const [
      ButtonSegment(value: true, icon: Icon(Icons.view_week_outlined), label: Text('Week view')),
      ButtonSegment(value: false, icon: Icon(Icons.view_agenda_outlined), label: Text('Day view')),
    ], selected: {showWeekBoard},
    onSelectionChanged: (selection) => setState(() => _weekBoardOverride = selection.first));

  final Set<String> _collapsedDays = {};

  int _selectedPlanDay = 0;
  bool _planDayVisible = true;
  int _selectedPublishedDay = 0;
  bool _publishedDayVisible = true;

  Widget _weeklyPlan() {
    final slots = _plan!.inWeek(_week), locked = _plan!.locked(_week);
    final assigned = slots.where((s) => s.staffId != null).length;
    final hasPublished = _plan!.published.containsKey(dateKey(_week));
    const green = Color(0xFF24573D);
    return ListView(
      key: ValueKey('week-${dateKey(_week)}-day-$_selectedPlanDay'),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                locked
                    ? 'Published · $assigned/${slots.length} assigned'
                    : '$assigned/${slots.length} assigned · ${slots.length - assigned} open',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            if (locked)
              OutlinedButton(
                onPressed: () => _action(() => _commit(_plan!.revise(_week))),
                child: const Text('Create draft'),
              )
            else
              FilledButton(
                key: const ValueKey('publish-week'),
                style: FilledButton.styleFrom(backgroundColor: green),
                onPressed:
                    slots.isNotEmpty && _plan!.publishProblem(_week) == null
                    ? _publish
                    : null,
                child: Text(hasPublished ? 'Republish' : 'Publish'),
              ),
          ],
        ),
        if (_error != null) InfoBox(_error!, error: true),
        if (!locked &&
            slots.any(
              (s) =>
                  s.staffId != null &&
                  _plan!.assignmentProblem(s, s.staffId!) != null,
            ))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Resolve the highlighted staff conflicts before publishing.',
              style: TextStyle(fontSize: 12, color: Color(0xFFA33B32)),
            ),
          ),
        if (!locked && slots.isEmpty)
          TextButton.icon(
            onPressed: () => _action(() => _commit(_plan!.loadTemplate(_week))),
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('Use standard template · 19 slots'),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var d = 0; d < 7; d++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: d == 6 ? 0 : 4),
                  child: Builder(
                    builder: (context) {
                      final date = addDays(_week, d),
                          closed = restaurantClosed(date);
                      final entries = slots
                          .where((s) => dateKey(s.date) == dateKey(date))
                          .toList();
                      final count = entries
                          .where((s) => s.staffId != null)
                          .length;
                      final selected = !closed && _selectedPlanDay == d;
                      return Semantics(
                        selected: selected,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(7),
                          onTap: closed
                              ? null
                              : () async {
                                  if (d == _selectedPlanDay ||
                                      !_planDayVisible) {
                                    return;
                                  }
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _planDayVisible = false;
                                  });
                                  await Future<void>.delayed(
                                    const Duration(milliseconds: 300),
                                  );
                                  if (!mounted) return;
                                  setState(() {
                                    _selectedPlanDay = d;
                                    _collapsedDays.remove(dateKey(date));
                                    _planDayVisible = true;
                                  });
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: closed
                                  ? const Color(0xFFF3F3F3)
                                  : selected
                                  ? const Color(0xFFEDF5EF)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: selected ? green : rosterLine,
                                width: selected ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  dayNames[date.weekday - 1].substring(0, 3),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: closed ? rosterMuted : rosterInk,
                                  ),
                                ),
                                Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: closed ? rosterMuted : rosterInk,
                                  ),
                                ),
                                Text(
                                  closed
                                      ? 'Closed'
                                      : '$count/${entries.length}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: closed ? rosterMuted : green,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  child: LinearProgressIndicator(
                                    minHeight: 3,
                                    value: closed || entries.isEmpty
                                        ? 0
                                        : count / entries.length,
                                    backgroundColor: rosterLine,
                                    color: green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          opacity: _planDayVisible ? 1 : 0,
          child: _day(addDays(_week, _selectedPlanDay), locked),
        ),
        for (var d = 0; d < 7; d++)
          if (d != _selectedPlanDay && !restaurantClosed(addDays(_week, d)))
            _day(addDays(_week, d), locked),
      ],
    );
  }

  Widget _day(DateTime date, bool locked) {
    final entries = _plan!
        .inWeek(_week)
        .where((s) => dateKey(s.date) == dateKey(date))
        .toList();
    final assigned = entries.where((s) => s.staffId != null).length;
    final expanded = !_collapsedDays.contains(dateKey(date));
    const green = Color(0xFF24573D);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: rosterLine),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (expanded) {
                _collapsedDays.add(dateKey(date));
              } else {
                _collapsedDays.remove(dateKey(date));
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${dayNames[date.weekday - 1].substring(0, 3)} ${shortDate(date)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '$assigned/${entries.length}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      value: entries.isEmpty ? 0 : assigned / entries.length,
                      backgroundColor: rosterLine,
                      color: green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                    color: green,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            for (var i = 0; i < entries.length; i++)
              _slotTile(entries[i], i + 1, locked),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(10),
                child: Text(
                  'No shifts yet',
                  style: TextStyle(color: rosterMuted),
                ),
              ),
            if (!locked)
              Material(
                color: const Color(0xFFF0F7F2),
                child: InkWell(
                  key: ValueKey('add-slot-${dateKey(date)}'),
                  onTap: () => _editSlot(date),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    child: Row(
                      children: [
                        Icon(Icons.add_circle, color: green, size: 22),
                        SizedBox(width: 9),
                        Text(
                          'Add time slot',
                          style: TextStyle(
                            color: green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _slotTile(WorkSlot slot, int index, bool locked) {
    final name = slot.staffId == null
        ? null
        : locked
        ? _plan!.published[dateKey(_week)]!.names[slot.staffId!] ??
              _plan!.person(slot.staffId!).name
        : _plan!.person(slot.staffId!).name;
    final problem = locked || slot.staffId == null
        ? null
        : _plan!.assignmentProblem(slot, slot.staffId!);
    return Semantics(
      label: 'Slot $index',
      child: InkWell(
        key: ValueKey('slot-${slot.id}'),
        onTap: locked ? null : () => _pick(slot),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          margin: const EdgeInsets.fromLTRB(8, 3, 8, 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: problem != null
                ? const Color(0xFFFFF0EF)
                : name == null
                ? Colors.white
                : const Color(0xFFEDF4EF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: problem != null
                  ? const Color(0xFFE4AAA5)
                  : name == null
                  ? rosterLine
                  : const Color(0xFFBCD1C1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      slot.timeLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Text(
                      name ?? 'Open',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: name == null
                            ? const Color(0xFF9B6000)
                            : rosterInk,
                        fontWeight: name == null
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (problem != null)
                    Tooltip(
                      message: problem,
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Colors.red,
                      ),
                    ),
                  if (!locked && name == null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3D9),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'Assign +',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9B6000),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else if (problem == null)
                    Icon(
                      name != null
                          ? Icons.check_circle_outline
                          : Icons.chevron_right,
                      size: 18,
                      color: const Color(0xFF24573D),
                    ),
                ],
              ),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    problem,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFA33B32),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _published() {
    final publication = _plan!.published[dateKey(_week)];
    if (publication == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.calendar_today_outlined, size: 42, color: rosterInk),
          const SizedBox(height: 16),
          const Text(
            'No published plan for this week',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const InfoBox(
            'Prepare your slots and assignments in Plan, then publish the completed week.',
          ),
          FilledButton(
            onPressed: () => setState(() => _tab = 0),
            child: const Text('Prepare week'),
          ),
        ],
      );
    }
    final slots = publication.slots;
    const green = Color(0xFF24573D);
    return ListView(
      key: ValueKey('published-${dateKey(_week)}-day-$_selectedPublishedDay'),
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Published · version ${publication.revision}',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: rosterInk,
          ),
        ),
        Text(
          'Confirmed ${shortDate(publication.publishedAt.toLocal())} ${clock(publication.publishedAt.toLocal().hour * 60 + publication.publishedAt.toLocal().minute)}',
        ),
        const SizedBox(height: 12),
        if (_plan!.editing.contains(dateKey(_week)))
          const InfoBox(
            'You have draft changes. This view still shows the last published version.',
          ),
        FilledButton.icon(
          key: const ValueKey('copy-roster'),
          onPressed: () => _copy(publication),
          icon: const Icon(Icons.copy),
          label: const Text('Copy published roster'),
        ),
        const SizedBox(height: 6),
        Text(
          cloudRosterEnabled
              ? 'Shared roster · Linked staff can see their own shifts'
              : 'Saved on this device · Copy to share with your team',
          style: TextStyle(fontSize: 12, color: rosterMuted),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var d = 0; d < 7; d++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: d == 6 ? 0 : 4),
                  child: Builder(
                    builder: (context) {
                      final date = addDays(_week, d),
                          closed = restaurantClosed(date);
                      final entries = slots
                          .where((s) => dateKey(s.date) == dateKey(date))
                          .toList();
                      final count = entries
                          .where((s) => s.staffId != null)
                          .length;
                      final selected = !closed && _selectedPublishedDay == d;
                      return Semantics(
                        selected: selected,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(7),
                          onTap: closed
                              ? null
                              : () async {
                                  if (d == _selectedPublishedDay ||
                                      !_publishedDayVisible) {
                                    return;
                                  }
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _publishedDayVisible = false;
                                  });
                                  await Future<void>.delayed(
                                    const Duration(milliseconds: 300),
                                  );
                                  if (!mounted) return;
                                  setState(() {
                                    _selectedPublishedDay = d;
                                    _publishedDayVisible = true;
                                  });
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: closed
                                  ? const Color(0xFFF3F3F3)
                                  : selected
                                  ? const Color(0xFFEDF5EF)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: selected ? green : rosterLine,
                                width: selected ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  dayNames[date.weekday - 1].substring(0, 3),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: closed ? rosterMuted : rosterInk,
                                  ),
                                ),
                                Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: closed ? rosterMuted : rosterInk,
                                  ),
                                ),
                                Text(
                                  closed
                                      ? 'Closed'
                                      : '$count/${entries.length}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: closed ? rosterMuted : green,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  child: LinearProgressIndicator(
                                    minHeight: 3,
                                    value: closed || entries.isEmpty
                                        ? 0
                                        : count / entries.length,
                                    backgroundColor: rosterLine,
                                    color: green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          opacity: _publishedDayVisible ? 1 : 0,
          child: PublishedDayCard(
            key: ValueKey(
              'published-selected-${dateKey(_week)}-$_selectedPublishedDay',
            ),
            publication: publication,
            day: addDays(publication.week, _selectedPublishedDay),
          ),
        ),
        for (var day = 0; day < 7; day++)
          if (day != _selectedPublishedDay &&
              !restaurantClosed(addDays(publication.week, day)))
            PublishedDayCard(
              key: ValueKey(
                'published-day-${dateKey(addDays(publication.week, day))}',
              ),
              publication: publication,
              day: addDays(publication.week, day),
            ),
      ],
    );
  }
}

class SlotAssignment extends StatefulWidget {
  const SlotAssignment({
    required this.slot,
    required this.getPlan,
    required this.onSave,
    super.key,
  });
  final WorkSlot slot;
  final SlotPlan Function() getPlan;
  final Future<void> Function(SlotPlan) onSave;
  @override
  State<SlotAssignment> createState() => _SlotAssignmentState();
}

class _SlotAssignmentState extends State<SlotAssignment> {
  String _search = '';
  String? _error;
  bool _busy = false;
  WorkSlot get _slot =>
      widget.getPlan().slots.firstWhere((s) => s.id == widget.slot.id);
  Future<void> _assign(String? staffId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(widget.getPlan().updateSlot(_slot.assign(staffId)));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is PlanValidationException
              ? error.message
              : 'Assignment could not be saved. Please try again.';
        });
      }
    }
  }

  Future<void> _details() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SlotDetails(
          day: _slot.date,
          slot: _slot,
          plan: widget.getPlan(),
          onSave: widget.onSave,
        ),
      ),
    );
    if (!mounted) return;
    if (!widget.getPlan().slots.any((s) => s.id == widget.slot.id)) {
      Navigator.pop(context);
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.getPlan(), slot = _slot;
    final people =
        plan.staff
            .where((p) => p.name.toLowerCase().contains(_search.toLowerCase()))
            .toList()
          ..sort(
            (a, b) => (plan.assignmentProblem(slot, a.id) == null ? 0 : 1)
                .compareTo(plan.assignmentProblem(slot, b.id) == null ? 0 : 1),
          );
    final count = plan.staff
        .where((p) => plan.assignmentProblem(slot, p.id) == null)
        .length;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Assign this slot')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: AbsorbPointer(
                absorbing: _busy,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            slot.timeLabel,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('edit-slot-details'),
                          tooltip: 'Edit slot times',
                          onPressed: _details,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                    Text(
                      '${dayNames[slot.date.weekday - 1]}, ${shortDate(slot.date)} ${slot.date.year}',
                    ),
                    if (slot.role.isNotEmpty) Text(slot.role),
                    Text('${slot.breakMinutes} min unpaid break'),
                    if (slot.notes.isNotEmpty) Text(slot.notes),
                    Text(
                      '$count staff available',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Staff are available by default. Time off and overlapping assignments are checked automatically.',
                    ),
                    Text(
                      'Monthly scheduled hours · ${slot.date.month}/${slot.date.year} · unpaid breaks excluded',
                      style: const TextStyle(fontSize: 12, color: rosterMuted),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (value) => setState(() => _search = value),
                      decoration: const InputDecoration(
                        labelText: 'Search staff',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    if (_error != null) InfoBox(_error!, error: true),
                    if (_busy) const LinearProgressIndicator(),
                    for (final person in people)
                      Card(
                        elevation: 0,
                        surfaceTintColor: Colors.transparent,
                        shape: rosterOutline,
                        color: Colors.white,
                        child: ListTile(
                          key: ValueKey('assign-${person.id}'),
                          title: Text(
                            person.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            plan.assignmentProblem(slot, person.id) ??
                                'Available${person.sample ? ' · Sample' : ''}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${plan.monthlyScheduledHours(person.id, slot.date).toStringAsFixed(1).replaceFirst(RegExp(r"\.0$"), "")} Hours',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                plan.assignmentProblem(slot, person.id) == null
                                    ? Icons.person_add_alt
                                    : Icons.block,
                              ),
                            ],
                          ),
                          enabled:
                              plan.assignmentProblem(slot, person.id) == null,
                          onTap: plan.assignmentProblem(slot, person.id) == null
                              ? () => _assign(person.id)
                              : null,
                        ),
                      ),
                    if (count == 0)
                      const InfoBox(
                        'No staff can take this slot. Check time off in Staff or review overlapping assignments in Plan.',
                      ),
                    if (slot.staffId != null)
                      OutlinedButton(
                        key: const ValueKey('unassign-slot'),
                        onPressed: () => _assign(null),
                        child: const Text('Unassign staff · Keep slot'),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

int? parseTime(String value, {bool allow24 = false}) {
  final input = value.trim();
  if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(input)) return null;
  final parts = input.split(':').map(int.parse).toList();
  if (allow24 && parts[0] == 24 && parts[1] == 0) return 1440;
  if (parts[0] > 23 || parts[1] > 59) return null;
  return parts[0] * 60 + parts[1];
}

class SlotDetails extends StatefulWidget {
  const SlotDetails({
    required this.day,
    required this.plan,
    required this.onSave,
    this.slot,
    super.key,
  });
  final DateTime day;
  final SlotPlan plan;
  final WorkSlot? slot;
  final Future<void> Function(SlotPlan) onSave;
  @override
  State<SlotDetails> createState() => _SlotDetailsState();
}

class _SlotDetailsState extends State<SlotDetails> {
  final _form = GlobalKey<FormState>();
  late final DateTime _date = widget.slot?.date ?? widget.day;
  late String? _staffId = widget.slot?.staffId;
  late final _start = TextEditingController(
    text: clock(widget.slot?.start ?? 960),
  );
  late final _end = TextEditingController(
    text: clock(widget.slot?.end ?? 1320),
  );
  late final _break = TextEditingController(
    text: '${widget.slot?.breakMinutes ?? 0}',
  );
  late final _role = TextEditingController(text: widget.slot?.role ?? '');
  late final _notes = TextEditingController(text: widget.slot?.notes ?? '');
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    for (final c in [_start, _end, _break, _role, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final slot = WorkSlot(
        id: widget.slot?.id ?? 'slot-${DateTime.now().microsecondsSinceEpoch}',
        date: _date,
        start: parseTime(_start.text)!,
        end: parseTime(_end.text)!,
        nextDay: parseTime(_end.text)! <= parseTime(_start.text)!,
        staffId: _staffId,
        breakMinutes: int.parse(_break.text),
        role: _role.text.trim(),
        notes: _notes.text.trim(),
      );
      await widget.onSave(widget.plan.updateSlot(slot));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is PlanValidationException
              ? '${error.message}${_staffId == null ? '' : '. Unassign the person below if changing their hours.'}'
              : 'Slot could not be saved. Please try again.';
        });
      }
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this time slot?'),
        content: const Text(
          'This removes the slot and its assignment from the draft.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep slot'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove slot'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(widget.plan.removeSlot(widget.slot!));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'The slot could not be removed. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.slot == null ? 'Add time slot' : 'Edit slot details',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: AbsorbPointer(
              absorbing: _busy,
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        '${dayNames[_date.weekday - 1]}, ${shortDate(_date)} ${_date.year}',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _time('Start time', _start, 'slot-start'),
                    const SizedBox(height: 16),
                    _time('End time', _end, 'slot-end'),
                    const SizedBox(height: 12),
                    if (_error != null) InfoBox(_error!, error: true),
                    if (_staffId != null)
                      OutlinedButton(
                        onPressed: () => setState(() => _staffId = null),
                        child: Text(
                          'Unassign ${widget.plan.person(_staffId!).name}',
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('save-slot'),
                      onPressed: _save,
                      child: Text(_busy ? 'Saving…' : 'Save slot'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    if (widget.slot != null)
                      TextButton.icon(
                        key: const ValueKey('remove-slot'),
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove time slot'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget _time(String name, TextEditingController controller, String key) =>
      TextFormField(
        key: ValueKey(key),
        controller: controller,
        keyboardType: TextInputType.datetime,
        decoration: InputDecoration(
          labelText: name,
          hintText: 'HH:MM, 24-hour time',
          suffixIcon: IconButton(
            tooltip: 'Choose $name',
            icon: const Icon(Icons.schedule),
            onPressed: () async {
              final minutes = parseTime(controller.text) ?? 960;
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: minutes ~/ 60,
                  minute: minutes % 60,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(alwaysUse24HourFormat: true),
                  child: child!,
                ),
              );
              if (picked != null) {
                controller.text = clock(picked.hour * 60 + picked.minute);
              }
            },
          ),
        ),
        validator: (value) =>
            parseTime(value ?? '') == null ? 'Use a time such as 16:00.' : null,
      );
}

class SlotStaffEditor extends StatefulWidget {
  const SlotStaffEditor({
    required this.plan,
    required this.onSave,
    this.person,
    super.key,
  });
  final SlotPlan plan;
  final StaffMember? person;
  final Future<void> Function(SlotPlan) onSave;
  @override
  State<SlotStaffEditor> createState() => _SlotStaffEditorState();
}

class _SlotStaffEditorState extends State<SlotStaffEditor> {
  late final _name = TextEditingController(text: widget.person?.name ?? '');
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a staff name.');
      return;
    }
    if (widget.plan.staff.any(
      (s) =>
          s.id != widget.person?.id &&
          s.name.toLowerCase() == name.toLowerCase(),
    )) {
      setState(() => _error = 'This name exists. Add a surname or initial.');
      return;
    }
    final person = StaffMember(
      id: widget.person?.id ?? 'staff-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(
        widget.plan.copyWith(
          staff: widget.person == null
              ? [...widget.plan.staff, person]
              : widget.plan.staff
                    .map((s) => s.id == person.id ? person : s)
                    .toList(),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Name could not be saved. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        widget.person == null ? 'Add staff member' : 'Edit staff name',
      ),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.person?.sample == true)
            const InfoBox(
              'Rename this sample member for your team. Availability stays with this staff record.',
            ),
          TextField(
            key: const ValueKey('person-name'),
            controller: _name,
            enabled: !_busy,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: 'Staff name',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('save-person'),
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save name'),
        ),
      ],
    ),
  );
}

// Activate after the private Firestore rules are published.
const cloudRosterEnabled = true;
const managerUid = 'RsGP2tDDF2ce0w479MMFyWH6vrS2';
const managerEmail = 'anastan.johnson@sailygroup.com';

class ManagerAuthGate extends StatefulWidget {
  const ManagerAuthGate({required this.store, required this.today, super.key});
  final SlotStore store;
  final DateTime today;
  @override
  State<ManagerAuthGate> createState() => _ManagerAuthGateState();
}

class _ManagerAuthGateState extends State<ManagerAuthGate> {
  late Future<FirebaseApp> _ready = _initialize();
  Future<FirebaseApp> _initialize() async {
    if (Firebase.apps.isNotEmpty) return Firebase.app();
    return Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyDIluxiZpOipOoikhgby9rvstnZ48ROUxg',
        appId: '1:13643393201:web:2943f9b8f064ed3df39a90',
        messagingSenderId: '13643393201',
        projectId: 'karikaala-staff-planner',
        authDomain: 'karikaala-staff-planner.firebaseapp.com',
        storageBucket: 'karikaala-staff-planner.firebasestorage.app',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FirebaseApp>(
    future: _ready,
    builder: (context, setup) {
      if (setup.hasError)
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Login service could not be reached.'),
                FilledButton(
                  onPressed: () => setState(() => _ready = _initialize()),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        );
      if (!setup.hasData)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, session) {
          if (session.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (session.data?.uid == managerUid) {
            return SlotHome(
              key: ValueKey(session.data!.uid),
              store: cloudRosterEnabled
                  ? SharedSlotStore(widget.store)
                  : widget.store,
              today: widget.today,
            );
          }
          if (session.data != null && cloudRosterEnabled)
            return StaffAccessGate(
              email: (session.data!.email ?? '').toLowerCase(),
            );
          if (session.data != null)
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Staff login setup is not active yet. Please ask the manager.',
                    ),
                    TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: const Text('Back to login'),
                    ),
                  ],
                ),
              ),
            );
          return const ManagerLogin();
        },
      );
    },
  );
}

class ManagerLogin extends StatefulWidget {
  const ManagerLogin({super.key});
  @override
  State<ManagerLogin> createState() => _ManagerLoginState();
}

class _ManagerLoginState extends State<ManagerLogin> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _hidden = true;
  String? _error;
  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = _username.text.trim();
      final email = name.toLowerCase() == 'ramanan'
          ? managerEmail
          : name.contains('@')
          ? name
          : name.toLowerCase() + '@staff.karikaala.app';
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _password.text,
      );
      _password.clear();
    } on FirebaseAuthException catch (error) {
      if (mounted)
        setState(
          () => _error = error.code == 'network-request-failed'
              ? 'Check your internet connection and try again.'
              : error.code == 'too-many-requests'
              ? 'Too many attempts. Please try again later.'
              : 'Username or password is incorrect.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Login could not be completed. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'Black KARIKAALAKK.png',
                    height: 160,
                    fit: BoxFit.contain,
                    semanticLabel: 'Karikaala logo',
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Staff Planner',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Manager and staff login',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: rosterMuted),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _username,
                    enabled: !_busy,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Username or email',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Enter your username or email.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: _hidden,
                    autocorrect: false,
                    enableSuggestions: false,
                    onFieldSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _hidden ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _hidden = !_hidden),
                        icon: Icon(
                          _hidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        (value ?? '').isEmpty ? 'Enter your password.' : null,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _login,
                    child: Text(_busy ? 'Signing in…' : 'Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// Spark-plan shared roster and private staff projections.
class SharedSlotStore implements LiveSlotStore {
  SharedSlotStore(this.local);
  final SlotStore local;
  final db = FirebaseFirestore.instance;
  int? _revision;
  SlotPlan? _previous;
  DocumentReference<Map<String, dynamic>> get roster =>
      db.doc('planner/current');
  @override
  Stream<void> watch() => roster.snapshots().skip(1).map<void>((_) {});
  @override
  Future<SlotPlan> read() async {
    final saved = await roster.get(const GetOptions(source: Source.server));
    _revision = saved.exists ? saved.data()!['revision'] as int : 0;
    final plan = saved.exists
        ? SlotPlan.decode(saved.data()!['json'] as String)
        : await local.read();
    var combined = plan;
    var needsAvailabilitySync = false;
    if (staffSelfAvailabilityEnabled) {
      final accounts = await db.doc('planner/accounts').get();
      final links = Map<String, dynamic>.from(
        accounts.data()?['links'] as Map? ?? {},
      );
      for (final email in links.keys) {
        final profile = await db.doc('staffData/' + email).get();
        if (profile.data()?['publishedWeeks'] is! List ||
            profile.data()?['managerTimeOff'] is! List)
          needsAvailabilitySync = true;
      }
      final availability = await db
          .collection('staffAvailability')
          .get(const GetOptions(source: Source.server));
      combined = plan.copyWith(
        staffTimeOff: [
          for (final doc in availability.docs)
            if (doc.data()['available'] == false &&
                links[doc.data()['email']] != null)
              StaffTimeOff(
                staffId: links[doc.data()['email']] as String,
                date: (doc.data()['day'] as Timestamp).toDate().toUtc(),
                start: 0,
                end: 1440,
              ),
        ],
      );
    }
    _previous = combined;
    // Initialize once, preserving this manager's existing device roster.
    if (!saved.exists || needsAvailabilitySync) await write(combined);
    return combined;
  }

  @override
  Future<void> write(SlotPlan plan) async {
    if (_revision == null)
      throw const PlanValidationException(
        'Load the shared roster before saving.',
      );
    final encoded = plan.encode();
    if (utf8.encode(encoded).length > 800000)
      throw const PlanValidationException(
        'The shared roster is too large. Contact the manager.',
      );
    final previous = _previous!;
    final expected = _revision!;
    final operation = DateTime.now().microsecondsSinceEpoch.toString();
    await db.runTransaction((tx) async {
      final current = await tx.get(roster);
      final accountsRef = db.doc('planner/accounts');
      final accountsDoc = await tx.get(accountsRef);
      final actual = current.exists ? current.data()!['revision'] as int : 0;
      if (actual != expected)
        throw const PlanValidationException(
          'Another device changed the roster. Reload the shared plan before saving.',
        );
      var writes = 1;
      final links = Map<String, dynamic>.from(
        accountsDoc.data()?['links'] as Map? ?? {},
      );
      if (links.length > 100)
        throw const PlanValidationException(
          'This version supports up to 100 staff logins.',
        );
      final overrides = <String, Map<String, dynamic>>{};
      if (staffSelfAvailabilityEnabled) {
        // Read availability before writing so publication and staff changes serialize.
        final checks = <String, WorkSlot>{};
        for (final link in links.entries) {
          for (final p in plan.published.entries) {
            if (previous.published[p.key]?.revision == p.value.revision)
              continue;
            for (final s in p.value.slots.where(
              (s) => s.staffId == link.value,
            )) {
              checks[_availabilityId(link.key, s.date)] = s;
            }
          }
          for (final off in previous.staffTimeOff.where(
            (p) => p.staffId == link.value,
          )) {
            if (!plan.staffTimeOff.any(
              (p) =>
                  p.staffId == off.staffId &&
                  dateKey(p.date) == dateKey(off.date),
            )) {
              overrides[_availabilityId(link.key, off.date)] = {
                'email': link.key,
                'day': Timestamp.fromDate(_availabilityDay(off.date)),
                'available': true,
                'updatedAt': FieldValue.serverTimestamp(),
              };
            }
          }
        }
        for (final entry in checks.entries) {
          final avail = await tx.get(db.doc('staffAvailability/' + entry.key));
          if (avail.data()?['available'] == false &&
              !overrides.containsKey(entry.key))
            throw PlanValidationException(
              'Staff availability changed for ${shortDate(entry.value.date)}. Reload the plan and resolve the unavailable shift before publishing.',
            );
        }
      }
      for (final entry in overrides.entries) {
        tx.set(db.doc('staffAvailability/' + entry.key), entry.value);
        writes++;
      }
      tx.set(roster, {
        'json': encoded,
        'revision': expected + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final today = dateOnly(DateTime.now());
      for (final entry in links.entries) {
        final email = entry.key, staffId = entry.value as String;
        final member = plan.staff.where((p) => p.id == staffId).firstOrNull;
        final assigned = plan.slots.where((s) => s.staffId == staffId).toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        if (++writes > 450)
          throw const PlanValidationException(
            'Too many assignment messages in one save. Make changes in smaller groups.',
          );
        tx.set(db.doc('staffData/' + email), {
          'name': member?.name ?? 'Staff',
          if (staffSelfAvailabilityEnabled)
            'publishedWeeks': plan.published.values
                .map((p) => Timestamp.fromDate(_availabilityDay(p.week)))
                .toList(),
          if (staffSelfAvailabilityEnabled)
            'managerTimeOff': plan.timeOff
                .where((p) => p.staffId == staffId)
                .map((p) => p.toJson())
                .toList(),
          'shifts': assigned.map((s) => s.toJson()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        final oldById = {
          for (final s in previous.slots.where((s) => s.staffId == staffId))
            s.id: s,
        };
        final newById = {for (final s in assigned) s.id: s};
        for (final id in {...oldById.keys, ...newById.keys}) {
          final old = oldById[id], next = newById[id];
          final slot = next ?? old!;
          if (slot.date.isBefore(today)) continue;
          if (old != null &&
              next != null &&
              old.date == next.date &&
              old.start == next.start &&
              old.end == next.end &&
              old.nextDay == next.nextDay &&
              old.breakMinutes == next.breakMinutes)
            continue;
          final title = next == null
              ? 'Shift assignment removed'
              : old == null
              ? 'New shift assignment'
              : 'Shift assignment updated';
          if (++writes > 450)
            throw const PlanValidationException(
              'Too many assignment messages in one save. Make changes in smaller groups.',
            );
          tx.set(
            db
                .collection('staffData/' + email + '/messages')
                .doc(operation + '-' + id),
            {
              'title': title,
              'body':
                  '${dayNames[slot.date.weekday - 1]}, ${shortDate(slot.date)} ${slot.date.year} · ${slot.timeLabel}',
              'slotId': id,
              'date': dateKey(slot.date),
              'createdAt': FieldValue.serverTimestamp(),
              'read': false,
            },
          );
        }
      }
    }, maxAttempts: 3);
    _revision = expected + 1;
    _previous = plan;
  }
}

class StaffLoginLinks extends StatefulWidget {
  const StaffLoginLinks({
    required this.store,
    required this.getPlan,
    super.key,
  });
  final SlotStore store;
  final SlotPlan Function() getPlan;
  @override
  State<StaffLoginLinks> createState() => _StaffLoginLinksState();
}

class _StaffLoginLinksState extends State<StaffLoginLinks> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool createAccount = true, hidden = true;
  String? staffId, error;
  bool busy = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> save(Map<String, dynamic> links) async {
    if (busy) return;
    if (FirebaseAuth.instance.currentUser?.uid != managerUid) {
      setState(() => error = 'Only the manager can create staff logins.');
      return;
    }
    final username = email.text.trim().toLowerCase();
    if (createAccount &&
        (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$').hasMatch(username) ||
            username == 'ramanan' ||
            password.text.length < 8)) {
      setState(
        () => error = 'Use a unique username of 3–32 letters, numbers, dots, underscores or hyphens, and a password of at least 8 characters.',
      );
      return;
    }
    final address = createAccount
        ? username + '@staff.karikaala.app'
        : username;
    if (staffId == null ||
        !RegExp(r'^[^\s/@]+@[^\s/@]+\.[^\s/@]+$').hasMatch(address) ||
        address == managerEmail) {
      setState(
        () => error =
            'Choose a staff member and enter their Firebase login email.',
      );
      return;
    }
    if (links.containsKey(address) && links[address] != staffId) {
      setState(
        () => error = 'This email is already linked to another staff member. Remove that link first.',
      );
      return;
    }
    if (links.entries.any((e) => e.value == staffId && e.key != address)) {
      setState(
        () => error = 'This staff member already has a login. Remove their old link first.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    FirebaseApp? secondary;
    User? created;
    bool linked = false;
    try {
      if (createAccount) {
        secondary = await Firebase.initializeApp(
          name:
              'staff-create-' +
              DateTime.now().microsecondsSinceEpoch.toString(),
          options: Firebase.app().options,
        );
        created =
            (await FirebaseAuth.instanceFor(app: secondary)
                    .createUserWithEmailAndPassword(
                      email: address,
                      password: password.text,
                    ))
                .user;
      }
      final db = FirebaseFirestore.instance;
      await db.runTransaction((tx) async {
        final ref = db.doc('planner/accounts');
        final snap = await tx.get(ref);
        final oldAccess = await tx.get(db.doc('staffAccess/' + address));
        if (oldAccess.exists && oldAccess.data()?['staffId'] != staffId)
          throw const PlanValidationException(
            'This email was linked to a different person. Use a new staff email.',
          );
        final current = Map<String, dynamic>.from(
          snap.data()?['links'] as Map? ?? {},
        );
        if (current.containsKey(address) || current.values.contains(staffId))
          throw const PlanValidationException(
            'A login link already exists. Reload this page.',
          );
        current[address] = staffId;
        tx.set(ref, {'links': current});
        tx.set(db.doc('staffAccess/' + address), {
          'staffId': staffId,
          'active': true,
        });
        final plan = widget.getPlan();
        tx.set(db.doc('staffData/' + address), {
          'name': plan.person(staffId!).name,
          if (staffSelfAvailabilityEnabled)
            'publishedWeeks': plan.published.values
                .map((p) => Timestamp.fromDate(_availabilityDay(p.week)))
                .toList(),
          'shifts': plan.slots
              .where((s) => s.staffId == staffId)
              .map((s) => s.toJson())
              .toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      linked = true;
      email.clear();
      password.clear();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Staff login ready. Give the username and password to your staff member.',
            ),
          ),
        );
      if (mounted) setState(() => staffId = null);
    } catch (e) {
      var cleanupFailed = false;
      if (created != null && !linked) {
        try {
          await created.delete();
        } catch (_) {
          cleanupFailed = true;
        }
      }
      if (mounted)
        setState(
          () => error = cleanupFailed
              ? 'Account created but access could not be linked. Remove the unused account in Firebase before retrying.'
              : e is FirebaseAuthException
              ? (e.code == 'email-already-in-use'
                    ? 'This username is already taken. Choose another.'
                    : e.code == 'weak-password'
                    ? 'Choose a stronger password.'
                    : 'Account could not be created. Check the connection and try again.')
              : e is PlanValidationException
              ? e.message
              : 'Login access could not be saved. Check the connection and try again.',
        );
    } finally {
      if (secondary != null) {
        try {
          await FirebaseAuth.instanceFor(app: secondary).signOut();
          await secondary.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke(String address) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final db = FirebaseFirestore.instance;
      await db.runTransaction((tx) async {
        final ref = db.doc('planner/accounts');
        final snap = await tx.get(ref);
        final links = Map<String, dynamic>.from(
          snap.data()?['links'] as Map? ?? {},
        );
        links.remove(address);
        tx.set(ref, {'links': links});
        tx.update(db.doc('staffAccess/' + address), {'active': false});
      });
    } catch (_) {
      if (mounted)
        setState(() => error = 'Access could not be removed. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Staff login access')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.doc('planner/accounts').snapshots(),
      builder: (context, snap) {
        if (snap.hasError)
          return const Center(
            child: Text(
              'Login access could not be loaded. Check the connection.',
            ),
          );
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final links = Map<String, dynamic>.from(
          snap.data!.data()?['links'] as Map? ?? {},
        );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Choose a staff member, create a unique username and password, then give both to the staff member.',
            ),
            SwitchListTile(
              title: const Text('Link an existing email login'),
              value: !createAccount,
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      createAccount = !v;
                      email.clear();
                      password.clear();
                      error = null;
                    }),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: staffId,
              decoration: const InputDecoration(labelText: 'Staff member'),
              items: widget
                  .getPlan()
                  .staff
                  .map(
                    (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                  )
                  .toList(),
              onChanged: busy ? null : (v) => setState(() => staffId = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: email,
              enabled: !busy,
              keyboardType: createAccount
                  ? TextInputType.text
                  : TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: createAccount
                    ? 'Staff username'
                    : 'Staff login email',
              ),
            ),
            if (createAccount) ...[
              const SizedBox(height: 16),
              TextField(
                controller: password,
                enabled: !busy,
                obscureText: hidden,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Staff password',
                  suffixIcon: IconButton(
                    tooltip: hidden ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => hidden = !hidden),
                    icon: Icon(
                      hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ],
            if (error != null) InfoBox(error!, error: true),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : () => save(links),
              child: Text(
                busy
                    ? 'Saving…'
                    : (createAccount
                          ? 'Create staff login'
                          : 'Give staff access'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Approved staff logins',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            for (final link in links.entries)
              ListTile(
                title: Text(
                  widget
                          .getPlan()
                          .staff
                          .where((p) => p.id == link.value)
                          .firstOrNull
                          ?.name ??
                      'Staff',
                ),
                subtitle: Text(
                  link.key.endsWith('@staff.karikaala.app')
                      ? link.key.split('@').first
                      : link.key,
                ),
                trailing: TextButton(
                  onPressed: busy ? null : () => revoke(link.key),
                  child: const Text('Remove access'),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class StaffPersonalHome extends StatefulWidget {
  const StaffPersonalHome({required this.email, super.key});
  final String email;
  @override
  State<StaffPersonalHome> createState() => _StaffPersonalHomeState();
}

class _StaffPersonalHomeState extends State<StaffPersonalHome> {
  int tab = 0;
  String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 64,
      title: Text(
        tab == 2
            ? 'Messages'
            : tab == 1
            ? 'Availability'
            : 'Staff Planner',
      ),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          onPressed: () => FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: tab == 0
        ? StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .doc('staffData/' + widget.email)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError)
                return const Center(
                  child: Text(
                    'Your shifts could not be loaded. Check the connection.',
                  ),
                );
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              final data = snap.data!.data();
              final slots =
                  (data?['shifts'] as List? ?? [])
                      .map(
                        (s) => WorkSlot.fromJson(
                          Map<String, dynamic>.from(s as Map),
                        ),
                      )
                      .where((s) => !s.date.isBefore(dateOnly(DateTime.now())))
                      .toList()
                    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
              return StaffAgenda(
                name: data?['name'] as String? ?? 'Staff',
                slots: slots,
              );
            },
          )
        : tab == 1
        ? _StaffOwnAvailability(email: widget.email)
        : _MessagingInbox(manager: false),
    bottomNavigationBar: NavigationBar(
      height: 76,
      selectedIndex: tab,
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: [
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          label: 'My shifts',
        ),
        NavigationDestination(
          icon: Icon(Icons.event_available_outlined),
          label: 'Availability',
        ),
        NavigationDestination(icon: const _MessagingIcon(), label: 'Messages'),
      ],
    ),
  );
}

class StaffAccessGate extends StatelessWidget {
  const StaffAccessGate({required this.email, super.key});
  final String email;
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.doc('staffAccess/' + email).snapshots(),
    builder: (context, snap) {
      if (!snap.hasError && !snap.hasData)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      if (snap.data?.data()?['active'] == true)
        return StaffPersonalHome(email: email);
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snap.hasError
                      ? 'Staff access could not be checked. Check your connection.'
                      : 'Your account is not linked to a staff member. Ask the manager to approve your login.',
                ),
                TextButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('Back to login'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// Private team conversations. Membership and writes are enforced by Firestore rules.
typedef _ChatDoc = QueryDocumentSnapshot<Map<String, dynamic>>;
const _chatGreen = Color(0xFF24573D);
String get _chatEmail =>
    FirebaseAuth.instance.currentUser!.email!.toLowerCase();
CollectionReference<Map<String, dynamic>> get _chats =>
    FirebaseFirestore.instance.collection('chats');
CollectionReference<Map<String, dynamic>> _chatReads(String email) =>
    FirebaseFirestore.instance.collection('chatReads/$email/threads');
int _chatUnread(Map<String, dynamic> chat, int read) =>
    ((chat['sequence'] as int? ?? 0) - read).clamp(0, 1000000).toInt();
String _chatTitle(Map<String, dynamic> chat, String email) {
  if (chat['kind'] == 'group') return chat['title'] as String? ?? 'Group';
  final members = List<String>.from(chat['members'] as List? ?? []);
  final other = members.where((m) => m != email);
  final names = Map<String, dynamic>.from(chat['memberNames'] as Map? ?? {});
  return other.isEmpty
      ? 'Personal chat'
      : names[other.first] as String? ?? 'Staff';
}

String _chatTime(dynamic value) {
  if (value is! Timestamp) return '';
  final date = value.toDate();
  final today = dateOnly(DateTime.now());
  if (dateOnly(date) == today) return clock(date.hour * 60 + date.minute);
  if (dateOnly(date) == today.subtract(const Duration(days: 1)))
    return 'Yesterday';
  return shortDate(date);
}

class _ChatFeed extends StatelessWidget {
  const _ChatFeed({required this.builder});
  final Widget Function(
    BuildContext,
    List<_ChatDoc>,
    Map<String, int>,
    bool,
    bool,
  )
  builder;
  @override
  Widget build(BuildContext context) {
    final email = _chatEmail;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _chats.where('members', arrayContains: email).snapshots(),
      builder: (context, chats) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _chatReads(email).snapshots(),
            builder: (context, reads) {
              final docs = [...?chats.data?.docs];
              docs.sort((a, b) {
                final at = a.data()['lastAt'] as Timestamp?;
                final bt = b.data()['lastAt'] as Timestamp?;
                return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
                  at?.millisecondsSinceEpoch ?? 0,
                );
              });
              final cursors = {
                for (final doc in reads.data?.docs ?? <_ChatDoc>[])
                  doc.id: doc.data()['sequence'] as int? ?? 0,
              };
              return builder(
                context,
                docs,
                cursors,
                chats.hasError || reads.hasError,
                !chats.hasData || !reads.hasData,
              );
            },
          ),
    );
  }
}

class _MessagingIcon extends StatelessWidget {
  const _MessagingIcon();
  @override
  Widget build(BuildContext context) => _ChatFeed(
    builder: (context, docs, reads, failed, loading) {
      final count = docs.fold<int>(
        0,
        (sum, doc) => sum + _chatUnread(doc.data(), reads[doc.id] ?? 0),
      );
      return Badge(
        isLabelVisible: count > 0 && !failed && !loading,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(Icons.chat_bubble_outline),
      );
    },
  );
}

class _MessagingInbox extends StatefulWidget {
  const _MessagingInbox({required this.manager, this.getPlan});
  final bool manager;
  final SlotPlan Function()? getPlan;
  @override
  State<_MessagingInbox> createState() => _MessagingInboxState();
}

class _MessagingInboxState extends State<_MessagingInbox> {
  int filter = 0;
  bool unreadOnly = false;
  String query = '';
  void open(_ChatDoc doc) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => _ConversationScreen(chatId: doc.id),
    ),
  );
  void compose() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => _NewConversationPage(
        manager: widget.manager,
        getPlan: widget.getPlan,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => _ChatFeed(
    builder: (context, docs, reads, failed, loading) {
      final unread = docs.fold<int>(
        0,
        (sum, doc) => sum + _chatUnread(doc.data(), reads[doc.id] ?? 0),
      );
      final shown = docs.where((doc) {
        final chat = doc.data();
        return (filter == 0 ||
                (filter == 1
                    ? chat['kind'] == 'group'
                    : chat['kind'] == 'direct')) &&
            (!unreadOnly || _chatUnread(chat, reads[doc.id] ?? 0) > 0) &&
            _chatTitle(
              chat,
              _chatEmail,
            ).toLowerCase().contains(query.toLowerCase());
      }).toList();
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.manager
                        ? 'Team conversations'
                        : 'Your conversations',
                    style: const TextStyle(color: rosterMuted, fontSize: 13),
                  ),
                ),
                if (!widget.manager)
                  _ShiftAlertButton(email: _chatEmail)
                else
                  IconButton(
                    tooltip: unreadOnly
                        ? 'Show all conversations'
                        : 'Unread conversations',
                    onPressed: () => setState(() => unreadOnly = !unreadOnly),
                    icon: Badge(
                      isLabelVisible: unread > 0,
                      label: Text(unread > 99 ? '99+' : '$unread'),
                      child: Icon(
                        unreadOnly
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'New message',
                  onPressed: compose,
                  icon: const Icon(Icons.edit_square, color: _chatGreen),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: ChoiceChip(
                      label: Center(
                        child: Text(['All', 'Groups', 'Personal'][i]),
                      ),
                      selected: filter == i,
                      showCheckmark: false,
                      selectedColor: _chatGreen,
                      backgroundColor: rosterSurface,
                      labelStyle: TextStyle(
                        color: filter == i ? Colors.white : rosterInk,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => setState(() => filter = i),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: const InputDecoration(
                hintText: 'Search conversations',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          if (unreadOnly)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Unread conversations',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => unreadOnly = false),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: failed
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Chats could not be loaded. Check your connection and try again.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : loading
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.forum_outlined,
                            size: 38,
                            color: rosterMuted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            query.isNotEmpty || unreadOnly
                                ? 'No matching conversations.'
                                : 'No conversations yet.',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.manager
                                ? 'Message a staff member or create a group.'
                                : 'Message your manager, or join a group created by the manager.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: rosterMuted),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: compose,
                            icon: const Icon(Icons.add_comment_outlined),
                            label: Text(
                              widget.manager
                                  ? 'New conversation'
                                  : 'Message manager',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final doc = shown[index], chat = doc.data();
                      final title = _chatTitle(chat, _chatEmail);
                      final count = _chatUnread(chat, reads[doc.id] ?? 0);
                      final names = Map<String, dynamic>.from(
                        chat['memberNames'] as Map? ?? {},
                      );
                      final sender = chat['lastSender'] as String? ?? '';
                      final preview = chat['lastText'] as String? ?? '';
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        onTap: () => open(doc),
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFFE5F0E9),
                          child: chat['kind'] == 'group'
                              ? const Icon(
                                  Icons.groups_outlined,
                                  color: _chatGreen,
                                )
                              : Text(
                                  title.isEmpty
                                      ? '?'
                                      : title.characters.first.toUpperCase(),
                                  style: const TextStyle(
                                    color: _chatGreen,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: count > 0
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          preview.isEmpty
                              ? 'No messages yet'
                              : '${sender == _chatEmail ? 'You' : names[sender] ?? 'Staff'}: $preview',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: rosterMuted,
                          ),
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _chatTime(chat['lastAt']),
                              style: const TextStyle(
                                fontSize: 10,
                                color: rosterMuted,
                              ),
                            ),
                            const SizedBox(height: 5),
                            if (count > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _chatGreen,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  count > 99 ? '99+' : '$count',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}

class _ChatPerson {
  const _ChatPerson(this.email, this.name);
  final String email, name;
}

Future<String> _directConversation(_ChatPerson person, String ownName) async {
  final email = _chatEmail;
  final staffEmail = email == managerEmail ? person.email : email;
  final staffName = email == managerEmail ? person.name : ownName;
  final id = 'dm-$staffEmail';
  final ref = _chats.doc(id);
  await FirebaseFirestore.instance.runTransaction((tx) async {
    final old = await tx.get(ref);
    if (old.exists) return;
    tx.set(ref, {
      'kind': 'direct',
      'title': '',
      'members': [managerEmail, staffEmail],
      'memberNames': {managerEmail: 'Ramanan', staffEmail: staffName},
      'createdBy': email,
      'createdAt': FieldValue.serverTimestamp(),
      'lastAt': FieldValue.serverTimestamp(),
      'lastText': '',
      'lastSender': '',
      'lastMessageId': '',
      'sequence': 0,
    });
  });
  return id;
}

class _NewConversationPage extends StatefulWidget {
  const _NewConversationPage({required this.manager, this.getPlan});
  final bool manager;
  final SlotPlan Function()? getPlan;
  @override
  State<_NewConversationPage> createState() => _NewConversationPageState();
}

class _NewConversationPageState extends State<_NewConversationPage> {
  late final Future<List<_ChatPerson>> people = loadPeople();
  bool busy = false;
  String? error;
  String query = '';
  Future<List<_ChatPerson>> loadPeople() async {
    if (!widget.manager) return [const _ChatPerson(managerEmail, 'Ramanan')];
    final access = await FirebaseFirestore.instance
        .collection('staffAccess')
        .where('active', isEqualTo: true)
        .get();
    final names = {for (final p in widget.getPlan!().staff) p.id: p.name};
    final result = access.docs
        .map(
          (doc) => _ChatPerson(
            doc.id,
            names[doc.data()['staffId']] ?? doc.id.split('@').first,
          ),
        )
        .toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<void> direct(_ChatPerson person) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      var name = 'Staff';
      if (!widget.manager) {
        final profile = await FirebaseFirestore.instance
            .doc('staffData/$_chatEmail')
            .get();
        name = profile.data()?['name'] as String? ?? 'Staff';
      }
      final id = await _directConversation(person, name);
      if (mounted)
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => _ConversationScreen(chatId: id),
          ),
        );
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Conversation could not be opened. Check the connection and try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New conversation')),
    body: FutureBuilder<List<_ChatPerson>>(
      future: people,
      builder: (context, snap) {
        if (snap.hasError)
          return const Center(
            child: Text(
              'Staff list could not be loaded. Please reopen this screen.',
            ),
          );
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final shown = snap.data!
            .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
        return Column(
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: InfoBox(error!, error: true),
              ),
            if (widget.manager)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE5F0E9),
                  child: Icon(Icons.group_add_outlined, color: _chatGreen),
                ),
                title: const Text('Create group'),
                subtitle: const Text('All staff or selected staff'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy || snap.data!.isEmpty
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => _CreateGroupPage(people: snap.data!),
                        ),
                      ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  hintText: 'Search staff',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No staff logins available. Create staff logins before starting a chat.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFE5F0E9),
                          child: Text(
                            shown[i].name.characters.first.toUpperCase(),
                            style: const TextStyle(color: _chatGreen),
                          ),
                        ),
                        title: Text(shown[i].name),
                        subtitle: !widget.manager
                            ? const Text('Manager')
                            : null,
                        trailing: const Icon(
                          Icons.chat_bubble_outline,
                          color: _chatGreen,
                        ),
                        onTap: busy ? null : () => direct(shown[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    ),
  );
}

class _CreateGroupPage extends StatefulWidget {
  const _CreateGroupPage({required this.people});
  final List<_ChatPerson> people;
  @override
  State<_CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<_CreateGroupPage> {
  final name = TextEditingController();
  final selected = <String>{};
  bool all = true, busy = false;
  String query = '';
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> create() async {
    final title = name.text.trim();
    final members = widget.people
        .where((p) => all || selected.contains(p.email))
        .toList();
    if (title.isEmpty || members.isEmpty) {
      setState(
        () =>
            error = 'Enter a group name and select at least one staff member.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ref = _chats.doc();
      await ref.set({
        'kind': 'group',
        'title': title,
        'members': [managerEmail, ...members.map((p) => p.email)],
        'memberNames': {
          managerEmail: 'Ramanan',
          for (final p in members) p.email: p.name,
        },
        'createdBy': _chatEmail,
        'createdAt': FieldValue.serverTimestamp(),
        'lastAt': FieldValue.serverTimestamp(),
        'lastText': '',
        'lastSender': '',
        'lastMessageId': '',
        'sequence': 0,
      });
      if (mounted)
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => _ConversationScreen(chatId: ref.id),
          ),
        );
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Group could not be created. Check the connection and try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = all ? widget.people.length : selected.length;
    final shown = widget.people
        .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Create group')),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error != null) InfoBox(error!, error: true),
                TextField(
                  controller: name,
                  enabled: !busy,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Group name',
                    hintText: 'e.g. Weekend team',
                    isDense: true,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('All staff'),
                        selected: all,
                        onSelected: busy
                            ? null
                            : (_) => setState(() => all = true),
                      ),
                    ),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Selected staff'),
                        selected: !all,
                        onSelected: busy
                            ? null
                            : (_) => setState(() => all = false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$count staff selected · Manager included',
                  style: const TextStyle(fontSize: 12, color: rosterMuted),
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search staff',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final p = shown[i];
                return CheckboxListTile(
                  dense: true,
                  title: Text(p.name),
                  value: all || selected.contains(p.email),
                  activeColor: _chatGreen,
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          if (all) {
                            selected.addAll(widget.people.map((p) => p.email));
                            all = false;
                          }
                          if (value == true)
                            selected.add(p.email);
                          else
                            selected.remove(p.email);
                        }),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : create,
                  child: const Text('Create group'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationScreen extends StatefulWidget {
  const _ConversationScreen({required this.chatId});
  final String chatId;
  @override
  State<_ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<_ConversationScreen> {
  final text = TextEditingController();
  bool sending = false;
  int limit = 100, marked = 0;
  String? error;
  DocumentReference<Map<String, dynamic>> get ref => _chats.doc(widget.chatId);
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> markRead(int sequence) async {
    if (sequence <= marked) return;
    marked = sequence;
    try {
      final cursor = _chatReads(_chatEmail).doc(widget.chatId);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final old = await tx.get(cursor);
        if ((old.data()?['sequence'] as int? ?? 0) >= sequence) return;
        tx.set(cursor, {
          'sequence': sequence,
          'readAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (_) {
      marked = 0;
    }
  }

  Future<void> send() async {
    final body = text.text.trim();
    if (sending || body.isEmpty) return;
    if (body.length > 2000) {
      setState(() => error = 'Keep messages under 2,000 characters.');
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final email = _chatEmail;
      final message = ref.collection('messages').doc();
      final batch = FirebaseFirestore.instance.batch();
      batch.set(message, {
        'sender': email,
        'text': body,
        'sentAt': FieldValue.serverTimestamp(),
      });
      batch.update(ref, {
        'sequence': FieldValue.increment(1),
        'lastMessageId': message.id,
        'lastText': body,
        'lastSender': email,
        'lastAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (mounted) text.clear();
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Message was not sent. Check the connection and try again.',
        );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: ref.snapshots(),
    builder: (context, chat) {
      final data = chat.data?.data();
      final available = !chat.hasError && data != null;
      final group = data?['kind'] == 'group';
      final names = Map<String, dynamic>.from(
        data?['memberNames'] as Map? ?? {},
      );
      return Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                available ? _chatTitle(data!, _chatEmail) : 'Conversation',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (available)
                Text(
                  group
                      ? '${(data!['members'] as List).length} members'
                      : 'Personal chat',
                  style: const TextStyle(fontSize: 11, color: rosterMuted),
                ),
            ],
          ),
          actions: [
            if (available && group)
              IconButton(
                tooltip: 'Group members',
                icon: const Icon(Icons.group_outlined),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => SafeArea(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        const ListTile(
                          title: Text(
                            'Group members',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        for (final member in List<String>.from(
                          data!['members'] as List,
                        ))
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.person_outline),
                            title: Text(names[member] as String? ?? 'Staff'),
                            subtitle: member == managerEmail
                                ? const Text('Manager')
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            if (!available)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      chat.hasError
                          ? 'Conversation could not be loaded. Your access may have changed.'
                          : 'Loading conversation…',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: ref
                      .collection('messages')
                      .orderBy('sentAt', descending: true)
                      .limit(limit)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError)
                      return const Center(
                        child: Text(
                          'Messages could not be loaded. Please reopen the chat.',
                        ),
                      );
                    if (!snap.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final docs = snap.data!.docs;
                    if (docs.isNotEmpty &&
                        docs.first.id == data!['lastMessageId']) {
                      final sequence = data['sequence'] as int;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) markRead(sequence);
                      });
                    }
                    if (docs.isEmpty)
                      return const Center(
                        child: Text(
                          'Start the conversation.',
                          style: TextStyle(color: rosterMuted),
                        ),
                      );
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length + (docs.length == limit ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == docs.length)
                          return TextButton(
                            onPressed: () => setState(() => limit += 100),
                            child: const Text('Load older messages'),
                          );
                        final message = docs[index].data();
                        final mine = message['sender'] == _chatEmail;
                        final sent = message['sentAt'] as Timestamp?;
                        final date = sent?.toDate();
                        final previous = index + 1 < docs.length
                            ? docs[index + 1].data()['sentAt'] as Timestamp?
                            : null;
                        final showDate =
                            date != null &&
                            (previous == null ||
                                dateOnly(previous.toDate()) != dateOnly(date));
                        return Column(
                          children: [
                            if (showDate)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Text(
                                  '${shortDate(date!)} ${date.year}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: rosterMuted,
                                  ),
                                ),
                              ),
                            Align(
                              alignment: mine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.sizeOf(context).width * 0.78,
                                ),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  12,
                                  7,
                                ),
                                decoration: BoxDecoration(
                                  color: mine ? _chatGreen : rosterSurface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (group && !mine)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          names[message['sender']] as String? ??
                                              'Staff',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: _chatGreen,
                                          ),
                                        ),
                                      ),
                                    Text(
                                      message['text'] as String,
                                      style: TextStyle(
                                        color: mine ? Colors.white : rosterInk,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      sent == null
                                          ? 'Sending…'
                                          : clock(
                                              date!.hour * 60 + date.minute,
                                            ),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: mine
                                            ? const Color(0xFFD8E8DF)
                                            : rosterMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: InfoBox(error!, error: true),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: text,
                        enabled: available && !sending,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Write a message…',
                          isDense: true,
                          counterText: '',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Send message',
                      onPressed: available && !sending ? send : null,
                      icon: sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send, color: _chatGreen),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ShiftAlertButton extends StatelessWidget {
  const _ShiftAlertButton({required this.email});
  final String email;
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('staffData/$email/messages')
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snap) {
          final count =
              snap.data?.docs
                  .where((doc) => doc.data()['read'] != true)
                  .length ??
              0;
          return IconButton(
            tooltip: 'Shift alerts',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => _StaffShiftAlerts(email: email),
              ),
            ),
            icon: Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: const Icon(Icons.notifications_none),
            ),
          );
        },
      );
}

class _StaffShiftAlerts extends StatefulWidget {
  const _StaffShiftAlerts({required this.email});
  final String email;
  @override
  State<_StaffShiftAlerts> createState() => _StaffShiftAlertsState();
}

class _StaffShiftAlertsState extends State<_StaffShiftAlerts> {
  String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Shift alerts')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('staffData/' + widget.email + '/messages')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError)
          return const Center(
            child: Text('Messages could not be loaded. Check the connection.'),
          );
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Messages',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Shift assignment messages appear here when you open the app.',
            ),
            if (error != null) InfoBox(error!, error: true),
            if (snap.data!.docs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No messages yet.'),
              ),
            for (final doc in snap.data!.docs)
              Card(
                child: ListTile(
                  leading: Icon(
                    doc.data()['read'] == true
                        ? Icons.mark_email_read_outlined
                        : Icons.mark_email_unread_outlined,
                  ),
                  title: Text(
                    doc.data()['title'] as String,
                    style: TextStyle(
                      fontWeight: doc.data()['read'] == true
                          ? FontWeight.normal
                          : FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(doc.data()['body'] as String),
                  onTap: () async {
                    try {
                      await doc.reference.update({'read': true});
                    } catch (_) {
                      if (mounted)
                        setState(
                          () => error =
                              'Message could not be marked as read. Try again.',
                        );
                    }
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}

DateTime _availabilityDay(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day);
String _availabilityId(String email, DateTime day) =>
    email + '_' + _availabilityDay(day).millisecondsSinceEpoch.toString();

class _StaffOwnAvailability extends StatefulWidget {
  const _StaffOwnAvailability({required this.email});
  final String email;
  @override
  State<_StaffOwnAvailability> createState() => _StaffOwnAvailabilityState();
}

class _StaffOwnAvailabilityState extends State<_StaffOwnAvailability> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selected = dateOnly(DateTime.now());
  bool busy = false;
  String? error;
  Future<void> save(bool available) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await FirebaseFirestore.instance
          .doc('staffAvailability/' + _availabilityId(widget.email, selected))
          .set({
            'email': widget.email,
            'day': Timestamp.fromDate(_availabilityDay(selected)),
            'available': available,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } on FirebaseException catch (e) {
      if (mounted)
        setState(
          () => error = e.code == 'permission-denied'
              ? 'This date is locked or the week was just published. Contact the restaurant manager.'
              : 'Availability was not saved. Check your connection and try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!staffSelfAvailabilityEnabled)
      return const Center(
        child: Text('Availability access is being activated.'),
      );
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .doc('staffData/' + widget.email)
          .snapshots(),
      builder: (context, profile) {
        if (profile.hasError)
          return const Center(
            child: Text('Availability could not be loaded. Try again.'),
          );
        if (!profile.hasData)
          return const Center(child: CircularProgressIndicator());
        final data = profile.data!.data() ?? {};
        final ready = data['publishedWeeks'] is List;
        final published = (data['publishedWeeks'] as List? ?? [])
            .map((p) => dateKey((p as Timestamp).toDate().toUtc()))
            .toSet();
        final managerOff = (data['managerTimeOff'] as List? ?? [])
            .map(
              (p) => StaffTimeOff.fromJson(Map<String, dynamic>.from(p as Map)),
            )
            .toList();
        final today = _availabilityDay(DateTime.now().toUtc()),
            editableFrom = today.add(const Duration(days: 15));
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('staffAvailability')
              .where('email', isEqualTo: widget.email)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return const Center(
                child: Text('Availability could not be loaded. Try again.'),
              );
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final unavailable = {
              for (final doc in snapshot.data!.docs)
                if (doc.data()['available'] == false)
                  dateKey((doc.data()['day'] as Timestamp).toDate().toUtc()),
            };
            bool restricted(DateTime d) =>
                managerOff.any((p) => dateKey(p.date) == dateKey(d));
            bool off(DateTime d) =>
                unavailable.contains(dateKey(d)) || restricted(d);
            bool locked(DateTime d) =>
                !ready ||
                _availabilityDay(d).isBefore(editableFrom) ||
                published.contains(dateKey(mondayOf(d))) ||
                restricted(d);
            final first = DateTime(month.year, month.month, 1),
                start = addDays(first, -(first.weekday - 1));
            final count =
                ((first.weekday -
                        1 +
                        DateTime(month.year, month.month + 1, 0).day +
                        6) ~/
                    7) *
                7;
            final closed = restaurantClosed(selected),
                isLocked = locked(selected);
            final reason = !ready
                ? 'The manager needs to sync your availability access.'
                : published.contains(dateKey(mondayOf(selected)))
                ? 'This week is published. Contact the restaurant manager for changes.'
                : restricted(selected)
                ? 'The manager has recorded time off on this date. Contact the restaurant manager to change it.'
                : isLocked
                ? 'Today and the next 14 days are locked. Call the restaurant manager for short-notice changes.'
                : 'Your availability saves automatically and is shared with the manager.';
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Text(
                  'My availability',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Edit from ${shortDate(editableFrom)}. Published weeks are locked.',
                    style: const TextStyle(fontSize: 12, color: rosterMuted),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: busy
                          ? null
                          : () => setState(
                              () =>
                                  month = DateTime(month.year, month.month - 1),
                            ),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][month.month - 1]} ${month.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      onPressed: busy
                          ? null
                          : () => setState(
                              () =>
                                  month = DateTime(month.year, month.month + 1),
                            ),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (final label in const [
                      'M',
                      'T',
                      'W',
                      'T',
                      'F',
                      'S',
                      'S',
                    ])
                      Expanded(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: rosterMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: count,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    mainAxisExtent: 44,
                    crossAxisCount: 7,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemBuilder: (context, i) {
                    final d = addDays(start, i),
                        inMonth = d.month == month.month,
                        isClosed = restaurantClosed(d),
                        chosen = dateKey(d) == dateKey(selected),
                        unavailableDay = off(d),
                        dayLocked = locked(d);
                    return InkWell(
                      onTap: !inMonth || busy
                          ? null
                          : () => setState(() {
                              selected = d;
                              error = null;
                            }),
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                        decoration: BoxDecoration(
                          color: !inMonth
                              ? Colors.transparent
                              : isClosed
                              ? const Color(0xFFF3F3F3)
                              : unavailableDay
                              ? const Color(0xFFFFEFED)
                              : chosen
                              ? const Color(0xFFEDF4EF)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: chosen
                                ? const Color(0xFF24573D)
                                : unavailableDay && !isClosed
                                ? const Color(0xFFE4AAA5)
                                : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              inMonth ? '${d.day}' : '',
                              style: TextStyle(
                                fontWeight: chosen
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isClosed || dayLocked
                                    ? rosterMuted
                                    : unavailableDay
                                    ? const Color(0xFFA33B32)
                                    : rosterInk,
                              ),
                            ),
                            if (inMonth && !isClosed && dayLocked)
                              const Icon(
                                Icons.lock_outline,
                                size: 10,
                                color: rosterMuted,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  '${dayNames[selected.weekday - 1]}, ${shortDate(selected)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 8),
                if (closed)
                  const Text('Restaurant closed · No staff needed.')
                else ...[
                  SwitchListTile(
                    thumbColor: WidgetStateProperty.all(Colors.white),
                    trackColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? const Color(0xFF486451)
                          : const Color(0xFFA54C43),
                    ),
                    trackOutlineColor: WidgetStateProperty.all(
                      Colors.transparent,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    tileColor: off(selected)
                        ? const Color(0xFFFFEFED)
                        : const Color(0xFFEDF4EF),
                    title: Text(off(selected) ? 'Unavailable' : 'Available'),
                    subtitle: const Text('Whole day'),
                    value: !off(selected),
                    onChanged: busy || isLocked ? null : save,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    reason,
                    style: const TextStyle(fontSize: 12, color: rosterMuted),
                  ),
                ],
                if (busy) const LinearProgressIndicator(),
                if (error != null) InfoBox(error!, error: true),
              ],
            );
          },
        );
      },
    );
  }
}
