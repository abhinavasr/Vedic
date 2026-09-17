import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../ai/assistant.dart';
import '../panchang/device_place.dart';

// A word in the morning: the day's verse, when the day's verse changes.
//
// Nothing is pushed from anywhere — there is no server in this. The phone
// schedules its own notice for five in the morning, which is the same moment
// the verse of the day turns over, and repeats it daily.
//
// Off until asked for. A scripture app that starts notifying on install has
// taken something without asking, and the first thing anyone does about an
// app like that is turn it off for good.

/// When the notice arrives: five in the morning, with the new verse.
const noticeHour = 5;

class DailyVerseNotice {
  DailyVerseNotice({
    required this.settings,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin() {
    _on = settings?.read(_key) == 'true';
  }

  /// The app's.
  static DailyVerseNotice? instance;

  static const _key = 'notify.dailyVerse';
  static const _id = 1;
  static const _channel = 'com.batiyao.veda.daily';

  final AssistantSettings? settings;
  final FlutterLocalNotificationsPlugin _plugin;

  late bool _on;
  var _ready = false;

  /// Whether the reader has asked for it.
  bool get enabled => _on;

  /// Prepares the plugin and the timezone database.
  ///
  /// The timezone matters: the notice is for five in the morning where the
  /// reader is, and a phone that travels should not go on ringing on the old
  /// clock.
  Future<void> prepare() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    final zone = await deviceZone();
    if (zone != null) {
      try {
        tz.setLocalLocation(tz.getLocation(zone));
      } on Object {
        // An unknown zone leaves the package's own default, which is UTC.
      }
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Asked for when the reader turns the notice on, not at launch.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Turns the notice on or off, and remembers which.
  Future<void> set({required bool on}) async {
    _on = on;
    settings?.write(_key, on ? 'true' : 'false');
    await prepare();
    if (on) {
      await _permission();
      await _schedule();
    } else {
      await _plugin.cancel(id: _id);
    }
  }

  /// Puts the schedule back after a restart, if it was asked for.
  Future<void> restore() async {
    if (!_on) return;
    await prepare();
    await _schedule();
  }

  Future<void> _permission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: false, sound: true);
    } on Object catch (error) {
      debugPrint('SADHANA: could not ask about notifications: $error');
    }
  }

  Future<void> _schedule() async {
    try {
      await _plugin.zonedSchedule(
        id: _id,
        title: 'Today’s verse',
        body: 'A new verse is waiting for you.',
        scheduledDate: _nextFive(),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channel,
            'Daily verse',
            channelDescription: 'One verse each morning.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // Inexact on purpose: this is a verse, not an alarm clock, and exact
        // alarms need a permission of their own that Android is right to
        // guard. A few minutes either side of five is nobody's problem.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } on Object catch (error) {
      debugPrint('SADHANA: could not schedule the daily verse: $error');
    }
  }

  /// The next five in the morning, in the reader's own time.
  tz.TZDateTime _nextFive() {
    final now = tz.TZDateTime.now(tz.local);
    final today = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      noticeHour,
    );
    return today.isAfter(now)
        ? today
        : tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, noticeHour);
  }
}
