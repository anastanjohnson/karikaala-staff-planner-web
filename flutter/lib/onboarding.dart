import 'package:flutter/material.dart';

import 'app_copy.dart';
import 'services.dart';
import 'widgets.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    required this.initial,
    required this.store,
    required this.notifications,
    super.key,
  });
  final SetupState initial;
  final SetupStore store;
  final Notifications notifications;
  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow>
    with WidgetsBindingObserver {
  late SetupState _setup;
  late bool _home;
  int _step = 0;
  bool _busy = false;
  bool _osNotifications = false;

  @override
  void initState() {
    super.initState();
    _setup = widget.initial;
    _home = _setup.completed;
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    try {
      final enabled = await widget.notifications.isEnabled();
      if (mounted) setState(() => _osNotifications = enabled);
    } catch (_) {
      if (mounted) setState(() => _osNotifications = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _save(SetupState next) async {
    try {
      await widget.store.write(next);
      if (!mounted) return false;
      setState(() => _setup = next);
      return true;
    } catch (_) {
      _message('Your changes could not be saved. Please try again.');
      return false;
    }
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (_) {
      _message('That action could not be completed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _go(int step) {
    if (_busy) return;
    setState(() {
      _step = step;
      _home = false;
    });
  }

  Future<void> _toggleInterest(int index) => _run(() async {
    final next = {..._setup.interests};
    if (!next.add(index)) next.remove(index);
    await _save(_setup.copyWith(interests: next));
  });

  Future<void> _enableNotifications() => _run(() async {
    if (!widget.notifications.supported) {
      if (!_home) setState(() => _step = 4);
      return;
    }
    final allowed = await widget.notifications.request();
    if (!mounted) return;
    setState(() => _osNotifications = allowed);
    if (await _save(_setup.copyWith(notificationsWanted: allowed))) {
      if (mounted && !_home) setState(() => _step = 4);
      if (!allowed) {
        _message(
          'Notifications are off. You can enable them later in Android settings.',
        );
      }
    }
  });

  Future<void> _finish() => _run(() async {
    if (await _save(_setup.copyWith(completed: true)) && mounted) {
      setState(() => _home = true);
    }
  });

  Future<void> _sendTest() => _run(() async {
    final enabled = await widget.notifications.isEnabled();
    if (mounted) setState(() => _osNotifications = enabled);
    if (!_setup.notificationsWanted || !enabled) {
      _message('Enable notifications before sending a test.');
      return;
    }
    final sent = await widget.notifications.sendTest();
    _message(
      sent
          ? 'Test notification sent.'
          : 'Notifications are blocked in Android settings.',
    );
  });

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset your setup?'),
        content: const Text(
          'This removes your saved interests and restarts the introduction. Android notification permission is unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      if (await _save(const SetupState()) && mounted) {
        setState(() {
          _step = 0;
          _home = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && (_home || _step == 0),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_busy && !_home && _step > 0) _go(_step - 1);
    },
    child: Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _home ? _settings() : _onboarding(),
              ),
            ),
            if (_busy)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  semanticsLabel: 'Saving',
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _onboarding() => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      key: ValueKey('onboarding-scroll-$_step'),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: _adaptiveHeight(
          context,
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_step == 0)
                      const Flexible(
                        child: Text(
                          AppCopy.name,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      Flexible(
                        child: TextButton(
                          onPressed: _busy ? null : () => _go(_step - 1),
                          child: const Text('← Back'),
                        ),
                      ),
                    if (_step < 4)
                      TextButton(
                        key: const ValueKey('skip'),
                        onPressed: _busy
                            ? null
                            : () => _go(_step < 2 ? 2 : _step + 1),
                        child: Text(_step == 3 ? 'Later' : 'Skip'),
                      )
                    else
                      const SizedBox(height: 48),
                  ],
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: 'Step ${_step + 1} of 5',
                  liveRegion: true,
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${(_step + 1).toString().padLeft(2, '0')} OF 05',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Palette.muted,
                            ),
                          ),
                        ),
                        for (var i = 0; i < 5; i++)
                          Container(
                            width: 16,
                            height: 4,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: BoxDecoration(
                              color: _step == i ? Palette.ink : Palette.line,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                ..._content(),
                const SizedBox(height: 32),
                if (MediaQuery.textScalerOf(context).scale(16) <= 20)
                  const Spacer(),
                ..._footer(),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _adaptiveHeight(BuildContext context, Widget child) =>
      MediaQuery.textScalerOf(context).scale(16) > 20
      ? child
      : IntrinsicHeight(child: child);

  List<Widget> _content() {
    switch (_step) {
      case 0:
        return [
          const WireframeImage('welcome', height: 248),
          const SizedBox(height: 32),
          const TitleCopy('Welcome to\n${AppCopy.name}'),
          const SizedBox(height: 16),
          const BodyCopy(AppCopy.welcome),
        ];
      case 1:
        return [
          const WireframeImage('benefit', height: 214),
          const SizedBox(height: 32),
          const TitleCopy(AppCopy.benefitTitle),
          const SizedBox(height: 16),
          const BodyCopy(AppCopy.benefitBody),
          const SizedBox(height: 24),
          for (final benefit in AppCopy.benefits)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•   ', style: TextStyle(fontSize: 18)),
                  Expanded(
                    child: Text(
                      benefit,
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
        ];
      case 2:
        return [
          const TitleCopy('Make it yours'),
          const SizedBox(height: 16),
          const BodyCopy(AppCopy.interestsBody),
          const SizedBox(height: 28),
          const Text(
            'Select any that apply',
            style: TextStyle(fontSize: 13, color: Palette.muted),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < AppCopy.interests.length; i++) _interest(i),
        ];
      case 3:
        return [
          const WireframeImage('notifications', height: 206),
          const SizedBox(height: 32),
          const TitleCopy('Stay in the loop'),
          const SizedBox(height: 16),
          const BodyCopy(AppCopy.notificationBody),
          if (!widget.notifications.supported) ...[
            const SizedBox(height: 16),
            const BodyCopy(
              'Notification permission and delivery can be tested in the Android app.',
            ),
          ],
          const SizedBox(height: 28),
          const HintCard(
            title: AppCopy.name,
            body: AppCopy.notificationExample,
          ),
        ];
      default:
        return [
          const SizedBox(height: 40),
          Center(
            child: ExcludeSemantics(
              child: Image.asset(
                'assets/figma/complete.png',
                width: 104,
                height: 104,
              ),
            ),
          ),
          const SizedBox(height: 52),
          const TitleCopy("You're ready.", center: true),
          const SizedBox(height: 16),
          const BodyCopy(AppCopy.readyBody, center: true),
          const SizedBox(height: 40),
          const HintCard(title: 'FIRST STEP', body: AppCopy.firstStep),
        ];
    }
  }

  Widget _interest(int index) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: _setup.interests.contains(index) ? Palette.soft : Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: _setup.interests.contains(index) ? Palette.ink : Palette.line,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CheckboxListTile(
        key: ValueKey('interest-$index'),
        value: _setup.interests.contains(index),
        onChanged: _busy ? null : (_) => _toggleInterest(index),
        title: Text(
          AppCopy.interests[index],
          style: const TextStyle(fontSize: 16),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  List<Widget> _footer() => [
    ActionButton(
      switch (_step) {
        0 => 'Get started',
        3 =>
          widget.notifications.supported
              ? 'Enable notifications'
              : 'Continue preview',
        4 => 'Open ${AppCopy.name}',
        _ => 'Continue',
      },
      key: const ValueKey('primary'),
      onPressed: _busy
          ? null
          : () {
              if (_step == 3) {
                _enableNotifications();
              } else if (_step == 4) {
                _finish();
              } else {
                _go(_step + 1);
              }
            },
    ),
    const SizedBox(height: 12),
    if (_step == 0)
      TextButton(
        onPressed: _busy ? null : () => _go(2),
        child: const Text('Skip introduction'),
      ),
    if (_step == 1)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text(
          '[Optional short reassurance]',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Palette.muted),
        ),
      ),
    if (_step == 2)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text(
          'You can change these later.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Palette.muted),
        ),
      ),
    if (_step == 3)
      ActionButton(
        'Not now',
        onPressed: _busy ? null : () => _go(4),
        secondary: true,
      ),
    if (_step == 4)
      TextButton(
        onPressed: _busy ? null : () => _go(0),
        child: const Text('Review introduction'),
      ),
  ];

  Widget _settings() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 24),
      const TitleCopy('Your setup'),
      const SizedBox(height: 12),
      const BodyCopy(
        'Review your preferences or go through the introduction again.',
      ),
      const SizedBox(height: 28),
      HintCard(
        title: 'YOUR INTERESTS',
        body: _setup.interests.isEmpty
            ? 'No interests selected.'
            : (_setup.interests.toList()..sort())
                  .map((i) => AppCopy.interests[i])
                  .join('\n'),
      ),
      const SizedBox(height: 16),
      HintCard(
        title: 'NOTIFICATIONS',
        body: _setup.notificationsWanted && _osNotifications
            ? 'Enabled on this device.'
            : 'Off. You can change this whenever you like.',
      ),
      const SizedBox(height: 24),
      ActionButton('Change interests', onPressed: _busy ? null : () => _go(2)),
      const SizedBox(height: 12),
      if (!widget.notifications.supported)
        const BodyCopy(
          'Notifications are available in the Android app. This browser preview lets you check the screens and your saved preferences.',
        )
      else if (!_setup.notificationsWanted || !_osNotifications)
        ActionButton(
          'Enable notifications',
          onPressed: _busy ? null : _enableNotifications,
          secondary: true,
        )
      else
        ActionButton(
          'Turn off notifications',
          onPressed: _busy
              ? null
              : () => _run(() async {
                  await _save(_setup.copyWith(notificationsWanted: false));
                }),
          secondary: true,
        ),
      const SizedBox(height: 12),
      if (widget.notifications.supported)
        ActionButton(
          'Send test notification',
          onPressed: _busy || !_setup.notificationsWanted || !_osNotifications
              ? null
              : _sendTest,
          secondary: true,
        ),
      if (widget.notifications.supported)
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(widget.notifications.openSettings),
          child: const Text('Android notification settings'),
        ),
      const SizedBox(height: 20),
      const BodyCopy(
        'Your preferences stay on this device. No account is required.',
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: _busy ? null : () => _go(0),
        child: const Text('Review introduction'),
      ),
      TextButton(
        onPressed: _busy ? null : _reset,
        child: const Text('Reset saved setup'),
      ),
      TextButton(
        onPressed: () => showAboutDialog(
          context: context,
          applicationName: AppCopy.name,
          applicationVersion: '0.1.0',
          children: [
            const Text(
              'This preview stores onboarding preferences locally and can send a local test notification. It does not connect to a server or send analytics.',
            ),
          ],
        ),
        child: const Text('About & privacy'),
      ),
    ],
  );
}
