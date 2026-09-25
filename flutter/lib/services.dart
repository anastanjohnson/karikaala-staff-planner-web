import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SetupState {
  const SetupState({
    this.completed = false,
    this.interests = const {},
    this.notificationsWanted = false,
  });
  final bool completed;
  final Set<int> interests;
  final bool notificationsWanted;

  SetupState copyWith({
    bool? completed,
    Set<int>? interests,
    bool? notificationsWanted,
  }) => SetupState(
    completed: completed ?? this.completed,
    interests: Set.unmodifiable(interests ?? this.interests),
    notificationsWanted: notificationsWanted ?? this.notificationsWanted,
  );

  String encode() => jsonEncode({
    'version': 1,
    'completed': completed,
    'interests': interests.toList()..sort(),
    'notificationsWanted': notificationsWanted,
  });

  factory SetupState.decode(String? value) {
    if (value == null) return const SetupState();
    try {
      final data = jsonDecode(value);
      if (data is! Map<String, dynamic> || data['version'] != 1) {
        return const SetupState();
      }
      final raw = data['interests'];
      return SetupState(
        completed: data['completed'] == true,
        interests: raw is List
            ? Set.unmodifiable(
                raw.whereType<int>().where((n) => n >= 0 && n < 4),
              )
            : const {},
        notificationsWanted: data['notificationsWanted'] == true,
      );
    } on FormatException {
      return const SetupState();
    }
  }
}

abstract interface class SetupStore {
  Future<SetupState> read();
  Future<void> write(SetupState value);
}

class PreferencesStore implements SetupStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static const _key = 'onboarding.setup.v1';
  @override
  Future<SetupState> read() async =>
      SetupState.decode(await _preferences.getString(_key));
  @override
  Future<void> write(SetupState value) =>
      _preferences.setString(_key, value.encode());
}

abstract interface class Notifications {
  bool get supported;
  Future<bool> isEnabled();
  Future<bool> request();
  Future<bool> sendTest();
  Future<void> openSettings();
}

class AndroidNotifications implements Notifications {
  static const _channel = MethodChannel('onboarding/notifications');
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<bool> _call(String method) async {
    if (!supported) return false;
    return await _channel.invokeMethod<bool>(method) ?? false;
  }

  @override
  Future<bool> isEnabled() => _call('isEnabled');
  @override
  Future<bool> request() => _call('request');
  @override
  Future<bool> sendTest() => _call('sendTest');
  @override
  Future<void> openSettings() async {
    if (supported) await _channel.invokeMethod<void>('openSettings');
  }
}
