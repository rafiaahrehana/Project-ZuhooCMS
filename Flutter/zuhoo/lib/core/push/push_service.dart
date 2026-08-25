import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../auth/auth_controller.dart';
import '../network/api_client.dart';
import '../providers.dart';

const _androidChannel = AndroidNotificationChannel(
  'zuhoo_default',
  'Notifications',
  description: 'Updates about your requests, approvals and account.',
  importance: Importance.high,
);

/// Handles a data message that arrives while no UI is running.
///
/// Must be a top-level function: the platform relaunches a separate isolate to
/// run it, which has none of the running app's state — no `ProviderScope`, no
/// signed-in session — so it re-initialises just enough to show something,
/// rather than reaching into an app that is not there.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _showDataMessage(message.data, FlutterLocalNotificationsPlugin());
}

/// Renders one data-only FCM payload as a local notification.
///
/// Every message this backend sends is data-only by design (see
/// `FcmPushService.java` — it calls `.putData(...)`, never `.setNotification`),
/// so the client decides what is shown rather than the OS rendering whatever
/// happened to be in the payload. That also means nothing appears on screen —
/// in the foreground or the background — unless this runs.
Future<void> _showDataMessage(
  Map<String, dynamic> data,
  FlutterLocalNotificationsPlugin plugin,
) async {
  final title = data['title'] as String?;
  final body = data['body'] as String?;
  if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
    return;
  }

  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_androidChannel);

  final id = int.tryParse(data['notificationId'] as String? ?? '') ??
      DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);

  await plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
    payload: jsonEncode(data),
  );
}

/// Push notifications end to end: permission, token lifecycle, and turning a
/// tapped notification into a screen.
///
/// Token registration is deliberately tied to sign-in/sign-out rather than to
/// app launch. `RegisterDeviceTokenRequest`'s own doc comment explains why:
/// there is no "which account is this for" field beyond whoever last
/// registered the token — the owner comes from the JWT at registration time —
/// so a device left signed into someone else's account would otherwise go on
/// receiving their notifications after a switch.
class PushService {
  PushService(this._ref);

  final Ref _ref;
  final _local = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _refreshSub;

  ApiClient get _api => _ref.read(apiClientProvider);

  /// Only Android has a `google-services.json` registered so far — calling
  /// into Firebase on any other platform would throw on the very first call
  /// rather than degrade quietly.
  bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<void> init() async {
    if (!_supported) return;

    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      // Fires whenever the process is alive to receive it — foreground or
      // merely backgrounded, which covers the ordinary "tap the notification
      // I just saw" case. Only a fully killed process needs a different path,
      // handled below via the launch details.
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    await FirebaseMessaging.instance.requestPermission();

    // A message that arrives while the app is on screen. Still shown as a
    // local notification rather than, say, an in-app banner — a data-only
    // FCM message has no other visible form, and consistency with the
    // background case (which can only ever show a system notification)
    // matters more than a nicer foreground treatment would.
    FirebaseMessaging.onMessage.listen(
      (message) => _showDataMessage(message.data, _local),
    );

    _refreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      if (_ref.read(currentUserProvider) != null) unawaited(_register(token));
    });

    // The process was fully killed and Android relaunched it because the
    // person tapped the local notification the background handler created.
    // `FirebaseMessaging.getInitialMessage()` does not apply here — that only
    // answers for a notification the FCM SDK itself rendered from a
    // `notification:` payload, which this backend never sends.
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _handlePayload(launch!.notificationResponse?.payload);
    }
  }

  void _onNotificationTapped(NotificationResponse response) =>
      _handlePayload(response.payload);

  void _handlePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      _navigateFor((jsonDecode(payload) as Map).cast<String, dynamic>());
    } catch (_) {
      // A malformed payload should not crash the tap handler.
    }
  }

  // ── Token lifecycle ─────────────────────────────────────────

  /// Call once a session exists — right after login, and after a cold start
  /// that restores one — so a token minted or rotated while signed out still
  /// gets registered.
  Future<void> registerToken() async {
    if (!_supported) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
    } catch (_) {
      // No Google Play services, permission refused, no network at that
      // moment — none of these should block signing in.
    }
  }

  Future<void> _register(String token) => _api.postText(
        '/notifications/device-tokens',
        {'token': token, 'platform': 'ANDROID'},
      );

  /// Call before the session is cleared — the endpoint needs the
  /// `Authorization` header the current tokens still provide.
  Future<void> unregisterToken() async {
    if (!_supported) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _api.deleteText('/notifications/device-tokens/$token');
      }
      // Forces a fresh token on the next sign-in, so a shared device does not
      // keep this one associated with whoever just signed out.
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Best-effort: the local session is gone regardless of whether this
      // succeeds.
    }
  }

  // ── Notification → screen ───────────────────────────────────

  /// Opens the module a notification is about, not the specific record: no
  /// screen in this app takes a record id from its route today (each one
  /// fetches its own list on open), so a tap lands on the right tab and the
  /// person finds the item themselves from there.
  void _navigateFor(Map<String, dynamic> data) {
    final isClient = _ref.read(currentUserProvider)?.isClient ?? false;
    final path = isClient
        ? _clientRouteFor(data['type'] as String?)
        : _staffRouteFor(data['type'] as String?);

    // Posted after the current frame: a tap that launches the app from cold
    // reaches this before `GoRouter`'s navigator has necessarily attached, and
    // pushing into one that is not there yet throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ref.read(routerProvider).push(path);
    });
  }

  String _staffRouteFor(String? type) => switch (type) {
        'REQUEST_SUBMITTED' ||
        'REQUEST_ASSIGNED' ||
        'REQUEST_UPDATED' ||
        'COMPLETED' ||
        'REJECTED' ||
        'CANCELLED' ||
        'SLA_WARNING' ||
        'SLA_BREACHED' =>
          Routes.requests,
        'PAYMENT_DUE' ||
        'PAYMENT_RECEIVED' ||
        'INVOICE_GENERATED' ||
        'REFUND_PROCESSED' ||
        'REFUND_REJECTED' ||
        'RECONCILIATION_OVERDUE' ||
        'DEPRECIATION_DUE' =>
          Routes.finance,
        'LICENSE_EXPIRING' ||
        'LICENSE_EXPIRED' ||
        'WARRANTY_EXPIRING' ||
        'WARRANTY_EXPIRED' ||
        'ASSET_ASSIGNED' ||
        'OFFBOARDING_CREATED' =>
          Routes.itam,
        'LEAVE_REQUESTED' || 'LEAVE_APPROVED' || 'LEAVE_REJECTED' =>
          Routes.leave,
        'PAYSLIP_READY' => Routes.payslips,
        'PERFORMANCE_REVIEW_STAGE' ||
        'PERFORMANCE_REVIEW_FINALISED' ||
        'PERFORMANCE_REVIEW_OVERDUE' =>
          Routes.performance,
        'LEAD_ASSIGNED' ||
        'OPPORTUNITY_WON' ||
        'OPPORTUNITY_LOST' ||
        'OPPORTUNITY_STAGE_CHANGED' ||
        'FOLLOW_UP_DUE' =>
          Routes.crm,
        _ => Routes.alerts,
      };

  // The client portal has no alerts tab and none of the staff-only modules
  // above, so an unmatched type falls back to the portal's own home rather
  // than a route the redirect in router.dart would immediately bounce away
  // from.
  String _clientRouteFor(String? type) => switch (type) {
        'REQUEST_SUBMITTED' ||
        'REQUEST_ASSIGNED' ||
        'REQUEST_UPDATED' ||
        'COMPLETED' ||
        'REJECTED' ||
        'CANCELLED' ||
        'SLA_WARNING' ||
        'SLA_BREACHED' =>
          PortalRoutes.requests,
        'PAYMENT_DUE' ||
        'PAYMENT_RECEIVED' ||
        'INVOICE_GENERATED' ||
        'REFUND_PROCESSED' ||
        'REFUND_REJECTED' =>
          PortalRoutes.billing,
        _ => PortalRoutes.home,
      };

  void dispose() => _refreshSub?.cancel();
}

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// Runs [PushService.init] exactly once for the life of the app.
///
/// A `FutureProvider` rather than a call from some widget's `initState`, so it
/// survives whichever screen happens to be first on display and never reruns
/// on an unrelated rebuild — the same reason `sharedPreferencesProvider` is
/// resolved once in `main()` rather than by whoever first needs it.
final pushInitProvider = FutureProvider<void>(
  (ref) => ref.read(pushServiceProvider).init(),
);
