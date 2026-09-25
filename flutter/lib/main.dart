import 'package:flutter/material.dart';

import 'slot_model.dart';
import 'slot_planner.dart';

// Preserve imports used by earlier FlutLab onboarding tests.
export 'onboarding_app.dart' show OnboardingApp;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SlotPlannerApp(store: LocalSlotStore()));
}
