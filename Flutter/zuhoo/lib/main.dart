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

  // Only Android has a `google-services.json` registered so far (see
  // `core/push/push_service.dart`) — calling this without one configured
  // would throw before the app ever shows a frame.
  if (!kIsWeb && Platform.isAndroid) {
    await Firebase.initializeApp();
    // Must be registered here, at the top level, before `runApp` — the
    // platform reads this reference to know what to relaunch into a fresh
    // isolate for a message that arrives with no UI running.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // Awaited here rather than inside a provider so that the theme is known
  // before the first frame. Resolving it lazily would paint one frame in the
  // default theme and then flip — a white flash on every cold start for anyone
  // using dark mode, which is exactly what the web app's pre-paint script in
  // index.html exists to avoid.
  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const ZuhooApp(),
    ),
  );
}
