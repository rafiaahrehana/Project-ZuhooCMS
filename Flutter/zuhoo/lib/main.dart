import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/providers.dart';
import 'core/push/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Started before either is awaited, so the two still run concurrently for a
  // fast cold start — but Firebase's outcome is isolated from
  // SharedPreferences': a device with no Google Play Services, a missing or
  // broken google-services.json, or any other Firebase setup problem must
  // cost this app its push notifications, not its ability to launch at all.
  final prefsFuture = SharedPreferences.getInstance();
  final firebaseFuture = (!kIsWeb && Platform.isAndroid)
      ? Firebase.initializeApp().then((_) => true).catchError((_) => false)
      : Future.value(false);

  final preferences = await prefsFuture;
  final firebaseReady = await firebaseFuture;

  if (firebaseReady) {
    // Must be registered here, at the top level, before `runApp` — the
    // platform reads this reference to know what to relaunch into a fresh
    // isolate for a message that arrives with no UI running.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const ZuhooApp(),
    ),
  );
}
