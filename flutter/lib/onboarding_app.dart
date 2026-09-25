import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_copy.dart';
import 'onboarding.dart';
import 'services.dart';
import 'widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(
    OnboardingApp(
      store: PreferencesStore(),
      notifications: AndroidNotifications(),
    ),
  );
}

class OnboardingApp extends StatefulWidget {
  const OnboardingApp({
    required this.store,
    required this.notifications,
    super.key,
  });
  final SetupStore store;
  final Notifications notifications;
  @override
  State<OnboardingApp> createState() => _OnboardingAppState();
}

class _OnboardingAppState extends State<OnboardingApp> {
  SetupState? _state;
  bool _loadFailed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final value = await widget.store.read();
      if (mounted) setState(() => _state = value);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppCopy.name,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: const ColorScheme.light(
            primary: Palette.ink,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Palette.ink,
            outline: Palette.line,
          ),
          scaffoldBackgroundColor: Colors.white,
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: Palette.muted,
              minimumSize: const Size(48, 48),
            ),
          ),
          checkboxTheme: CheckboxThemeData(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        home: _loadFailed
            ? Scaffold(
                body: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const BodyCopy(
                            'Your saved setup could not be loaded. Please try again.',
                            center: true,
                          ),
                          const SizedBox(height: 24),
                          ActionButton('Try again', onPressed: _load),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : _state == null
                ? const Scaffold(
                    body: Center(child: CircularProgressIndicator()))
                : OnboardingFlow(
                    initial: _state!,
                    store: widget.store,
                    notifications: widget.notifications,
                  ),
      );
}
