import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onboarding_flutter/main.dart';
import 'package:onboarding_flutter/services.dart';

class MemoryStore implements SetupStore {
  SetupState value = const SetupState();
  bool failWrites = false;
  bool failReads = false;
  @override
  Future<SetupState> read() async {
    if (failReads) throw StateError('Storage unavailable');
    return value;
  }

  @override
  Future<void> write(SetupState next) async {
    if (failWrites) throw StateError('Disk full');
    value = next;
  }
}

class FakeNotifications implements Notifications {
  @override
  bool get supported => true;
  bool allowed = false;
  int requests = 0;
  int sends = 0;
  @override
  Future<bool> isEnabled() async => allowed;
  @override
  Future<bool> request() async {
    requests++;
    return allowed;
  }

  @override
  Future<bool> sendTest() async {
    sends++;
    return allowed;
  }

  @override
  Future<void> openSettings() async {}
}

Future<void> start(
  WidgetTester tester,
  MemoryStore store,
  FakeNotifications notifications, {
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    OnboardingApp(store: store, notifications: notifications),
  );
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

final primary = find.byKey(const ValueKey('primary'));

void main() {
  test('corrupt or out-of-range saved data safely recovers', () {
    expect(SetupState.decode('{bad').completed, isFalse);
    expect(SetupState.decode('[]').interests, isEmpty);
    expect(
      SetupState.decode('{"version":1,"interests":[0,1,1,-1,8,"2"]}').interests,
      {0, 1},
    );
    final original = SetupState(
      completed: true,
      interests: const {1, 3},
      notificationsWanted: true,
    );
    final restored = SetupState.decode(original.encode());
    expect(restored.interests, {1, 3});
    expect(restored.completed, isTrue);
    expect(restored.notificationsWanted, isTrue);
  });

  testWidgets(
    'complete all screens, persist preferences, restore after restart',
    (tester) async {
      final store = MemoryStore();
      final notifications = FakeNotifications();
      await start(tester, store, notifications);
      expect(find.text('Welcome to\n[App name]'), findsOneWidget);
      await press(tester, primary);
      expect(find.text('[Main benefit]'), findsOneWidget);
      await press(tester, primary);
      await press(tester, find.byKey(const ValueKey('interest-1')));
      await press(tester, find.byKey(const ValueKey('interest-3')));
      expect(store.value.interests, {1, 3});
      await press(tester, primary);
      expect(notifications.requests, 0);
      await press(tester, find.text('Not now'));
      expect(find.text("You're ready."), findsOneWidget);
      await press(tester, primary);
      expect(find.text('Your setup'), findsOneWidget);
      expect(store.value.completed, isTrue);
      expect(notifications.requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        OnboardingApp(store: store, notifications: notifications),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your setup'), findsOneWidget);
      expect(find.text('[Interest 2]\n[Interest 4]'), findsOneWidget);
    },
  );

  testWidgets(
    'permission denial allows completion without pretending consent',
    (tester) async {
      final store = MemoryStore();
      final notifications = FakeNotifications();
      await start(tester, store, notifications);
      await press(tester, find.byKey(const ValueKey('skip')));
      await press(tester, primary);
      await press(tester, primary);
      expect(notifications.requests, 1);
      expect(store.value.notificationsWanted, isFalse);
      expect(find.text("You're ready."), findsOneWidget);
    },
  );

  testWidgets('failed save stays on confirmation and can retry', (
    tester,
  ) async {
    final store = MemoryStore();
    await start(tester, store, FakeNotifications());
    await press(tester, find.byKey(const ValueKey('skip')));
    await press(tester, primary);
    await press(tester, find.text('Not now'));
    store.failWrites = true;
    await press(tester, primary);
    expect(store.value.completed, isFalse);
    expect(find.text("You're ready."), findsOneWidget);
    expect(
      find.text('Your changes could not be saved. Please try again.'),
      findsOneWidget,
    );
    store.failWrites = false;
    await press(tester, primary);
    expect(find.text('Your setup'), findsOneWidget);
  });

  testWidgets(
    'back and skip preserve selections; narrow large text remains scrollable',
    (tester) async {
      final store = MemoryStore();
      await start(
        tester,
        store,
        FakeNotifications(),
        size: const Size(320, 568),
        scale: 2,
      );
      await press(tester, primary);
      await press(tester, primary);
      await press(tester, find.byKey(const ValueKey('interest-0')));
      await press(tester, find.text('← Back'));
      await press(tester, primary);
      expect(store.value.interests, {0});
      await press(tester, primary);
      await press(tester, find.text('Not now'));
      await press(tester, primary);
      expect(find.text('Your setup'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reset requires confirmation and clears only saved setup', (
    tester,
  ) async {
    final store = MemoryStore()
      ..value = const SetupState(completed: true, interests: {2});
    final notifications = FakeNotifications()..allowed = true;
    await start(tester, store, notifications);
    await press(tester, find.text('Reset saved setup'));
    await press(tester, find.text('Cancel'));
    expect(store.value.completed, isTrue);
    await press(tester, find.text('Reset saved setup'));
    await press(tester, find.text('Reset'));
    expect(store.value.completed, isFalse);
    expect(store.value.interests, isEmpty);
    expect(notifications.allowed, isTrue);
    expect(find.text('Welcome to\n[App name]'), findsOneWidget);
  });

  testWidgets('loading failure is recoverable', (tester) async {
    final store = MemoryStore()..failReads = true;
    await start(tester, store, FakeNotifications());
    expect(find.text('Try again'), findsOneWidget);
    store.failReads = false;
    await press(tester, find.text('Try again'));
    expect(find.text('Welcome to\n[App name]'), findsOneWidget);
  });
}
