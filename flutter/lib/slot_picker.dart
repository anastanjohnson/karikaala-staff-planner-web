import 'package:flutter/material.dart';

import 'planner_model.dart';
import 'planner_theme.dart';
import 'slot_model.dart';

class SlotPresetPicker extends StatefulWidget {
  const SlotPresetPicker(
      {required this.day,
      required this.getPlan,
      required this.onSave,
      required this.createNew,
      super.key});
  final DateTime day;
  final SlotPlan Function() getPlan;
  final Future<void> Function(SlotPlan) onSave;
  final Future<bool> Function(BuildContext) createNew;
  @override
  State<SlotPresetPicker> createState() => _SlotPresetPickerState();
}

class _SlotPresetPickerState extends State<SlotPresetPicker> {
  bool _busy = false;
  String? _error;

  Future<void> _add(SlotPreset preset) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final slot = preset.onDay(
          widget.day, 'slot-${DateTime.now().microsecondsSinceEpoch}');
      await widget.onSave(widget.getPlan().updateSlot(slot));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is PlanValidationException
              ? error.message
              : 'Slot could not be added. Please try again.';
        });
      }
    }
  }

  Future<void> _create() async {
    final saved = await widget.createNew(context);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('Add time slot')),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: AbsorbPointer(
                absorbing: _busy,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                        '${dayNames[widget.day.weekday - 1]}, ${shortDate(widget.day)} ${widget.day.year}',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                        'Choose saved hours to add one open position to this day. You can assign staff afterwards.',
                        style: TextStyle(color: rosterMuted)),
                    const SizedBox(height: 24),
                    Text('Available slots',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer)),
                      ),
                    for (final preset in widget.getPlan().presets)
                      Card(
                        elevation: 0,
                        surfaceTintColor: Colors.transparent,
                        color: Colors.white,
                        shape: rosterOutline,
                        clipBehavior: Clip.antiAlias,
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          key: ValueKey('preset-${preset.key}'),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          title: Text(preset.timeLabel,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(preset.detailLabel),
                          trailing: const Icon(Icons.add),
                          enabled: !_busy,
                          onTap: () => _add(preset),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const ValueKey('create-new-slot'),
                      onPressed: _busy ? null : _create,
                      icon: const Icon(Icons.add),
                      label: const Text('Create new slot'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                        'New hours, breaks and roles are saved here for next time.',
                        style: TextStyle(color: rosterMuted, fontSize: 12)),
                  ],
                )),
          ))),
        ),
      );
}
