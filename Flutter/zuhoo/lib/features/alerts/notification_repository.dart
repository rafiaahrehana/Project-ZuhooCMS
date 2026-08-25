import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.read,
    this.type,
    this.link,
    this.createdAt,
  });

  final int id;
  final String title;
  final String message;
  final bool read;
  final String? type;
  final String? link;
  final String? createdAt;

  AppNotification asRead() => AppNotification(
        id: id,
        title: title,
        message: message,
        read: true,
        type: type,
        link: link,
        createdAt: createdAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        message: json['message'] as String? ?? json['body'] as String? ?? '',
        // The DTO has used both spellings; accept either rather than silently
        // showing every notification as unread.
        read: json['read'] as bool? ?? json['isRead'] as bool? ?? false,
        type: json['type'] as String?,
        link: json['link'] as String? ?? json['actionUrl'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

/// `GET/PUT/DELETE /api/notification-preferences`. Every field is a plain
/// on/off switch, no permission gate — everyone manages their own.
///
/// `PUT` is a full replacement, not a patch (see `UpdateNotificationPreferenceRequest`
/// — it has no nullable fields), so every toggle in the UI must send the whole
/// object back, not just the one that changed.
class NotificationPreferences {
  const NotificationPreferences({
    this.emailOnServiceRequest = true,
    this.emailOnStatusChange = true,
    this.emailOnInvoice = true,
    this.emailOnPayment = true,
    this.emailOnTaskAssigned = true,
    this.emailOnLeaveUpdate = true,
    this.inAppOnServiceRequest = true,
    this.inAppOnStatusChange = true,
    this.emailMarketing = false,
  });

  final bool emailOnServiceRequest;
  final bool emailOnStatusChange;
  final bool emailOnInvoice;
  final bool emailOnPayment;
  final bool emailOnTaskAssigned;
  final bool emailOnLeaveUpdate;
  final bool inAppOnServiceRequest;
  final bool inAppOnStatusChange;
  final bool emailMarketing;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        emailOnServiceRequest: json['emailOnServiceRequest'] as bool? ?? true,
        emailOnStatusChange: json['emailOnStatusChange'] as bool? ?? true,
        emailOnInvoice: json['emailOnInvoice'] as bool? ?? true,
        emailOnPayment: json['emailOnPayment'] as bool? ?? true,
        emailOnTaskAssigned: json['emailOnTaskAssigned'] as bool? ?? true,
        emailOnLeaveUpdate: json['emailOnLeaveUpdate'] as bool? ?? true,
        inAppOnServiceRequest: json['inAppOnServiceRequest'] as bool? ?? true,
        inAppOnStatusChange: json['inAppOnStatusChange'] as bool? ?? true,
        emailMarketing: json['emailMarketing'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'emailOnServiceRequest': emailOnServiceRequest,
        'emailOnStatusChange': emailOnStatusChange,
        'emailOnInvoice': emailOnInvoice,
        'emailOnPayment': emailOnPayment,
        'emailOnTaskAssigned': emailOnTaskAssigned,
        'emailOnLeaveUpdate': emailOnLeaveUpdate,
        'inAppOnServiceRequest': inAppOnServiceRequest,
        'inAppOnStatusChange': inAppOnStatusChange,
        'emailMarketing': emailMarketing,
      };

  NotificationPreferences copyWith({
    bool? emailOnServiceRequest,
    bool? emailOnStatusChange,
    bool? emailOnInvoice,
    bool? emailOnPayment,
    bool? emailOnTaskAssigned,
    bool? emailOnLeaveUpdate,
    bool? inAppOnServiceRequest,
    bool? inAppOnStatusChange,
    bool? emailMarketing,
  }) =>
      NotificationPreferences(
        emailOnServiceRequest:
            emailOnServiceRequest ?? this.emailOnServiceRequest,
        emailOnStatusChange: emailOnStatusChange ?? this.emailOnStatusChange,
        emailOnInvoice: emailOnInvoice ?? this.emailOnInvoice,
        emailOnPayment: emailOnPayment ?? this.emailOnPayment,
        emailOnTaskAssigned: emailOnTaskAssigned ?? this.emailOnTaskAssigned,
        emailOnLeaveUpdate: emailOnLeaveUpdate ?? this.emailOnLeaveUpdate,
        inAppOnServiceRequest:
            inAppOnServiceRequest ?? this.inAppOnServiceRequest,
        inAppOnStatusChange: inAppOnStatusChange ?? this.inAppOnStatusChange,
        emailMarketing: emailMarketing ?? this.emailMarketing,
      );
}

class NotificationRepository {
  NotificationRepository(this._api);

  final ApiClient _api;

  static const _base = '/notifications';
  static const _preferences = '/notification-preferences';

  Future<NotificationPreferences> getPreferences() async {
    final json = await _api.get<Map<String, dynamic>>(_preferences);
    return NotificationPreferences.fromJson(json);
  }

  Future<NotificationPreferences> updatePreferences(
    NotificationPreferences preferences,
  ) async {
    final json =
        await _api.put<Map<String, dynamic>>(_preferences, preferences.toJson());
    return NotificationPreferences.fromJson(json);
  }

  Future<NotificationPreferences> resetPreferences() async {
    final json = await _api.delete<Map<String, dynamic>>(_preferences);
    return NotificationPreferences.fromJson(json);
  }

  Future<PagedResponse<AppNotification>> list({
    bool unreadOnly = false,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        _base,
        AppNotification.fromJson,
        page: page,
        size: size,
        query: {'unreadOnly': unreadOnly},
      );

  Future<int> unreadCount() async {
    final json = await _api.get<Map<String, dynamic>>('$_base/count');
    return (json['unreadCount'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(int id) => _api.patchText('$_base/$id/read');

  Future<void> markAllRead() => _api.patchText('$_base/read-all');
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(apiClientProvider)),
);

class NotificationPreferencesController
    extends AsyncNotifier<NotificationPreferences> {
  @override
  Future<NotificationPreferences> build() {
    ref.watch(currentUserProvider);
    return ref.read(notificationRepositoryProvider).getPreferences();
  }

  /// Optimistic, like marking a notification read: a switch that visibly
  /// flips back on failure is a clearer signal than one that just sits there
  /// while a request is in flight.
  ///
  /// Named `save` rather than `update` — `AsyncNotifier` already declares an
  /// `update` method of its own, and overriding it with an incompatible
  /// signature does not compile.
  Future<void> save(NotificationPreferences updated) async {
    final previous = state.value;
    state = AsyncValue.data(updated);
    try {
      await ref.read(notificationRepositoryProvider).updatePreferences(updated);
    } catch (_) {
      if (previous != null) state = AsyncValue.data(previous);
      rethrow;
    }
  }

  Future<void> resetToDefaults() async {
    final previous = state.value;
    try {
      state = AsyncValue.data(
        await ref.read(notificationRepositoryProvider).resetPreferences(),
      );
    } catch (_) {
      if (previous != null) state = AsyncValue.data(previous);
      rethrow;
    }
  }
}

final notificationPreferencesProvider = AsyncNotifierProvider<
    NotificationPreferencesController, NotificationPreferences>(
  NotificationPreferencesController.new,
);

/// Unread badge count, polled while the app is running.
///
/// The backend has no push channel wired to this yet — it has a device-token
/// endpoint but nothing delivers through it — so a poll is what keeps the
/// badge honest. Sixty seconds matches the web app; anything tighter would
/// spend a phone's battery to shave seconds off a badge nobody is watching.
class UnreadCountController extends Notifier<int> {
  Timer? _timer;

  @override
  int build() {
    final signedIn = ref.watch(currentUserProvider) != null;

    _timer?.cancel();
    if (!signedIn) return 0;

    unawaited(_tick());
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _tick());
    ref.onDispose(() => _timer?.cancel());
    return 0;
  }

  Future<void> _tick() async {
    try {
      state = await ref.read(notificationRepositoryProvider).unreadCount();
    } catch (_) {
      // Keep the last known count and try again on the next tick; a badge is
      // not worth an error state.
    }
  }

  /// Called straight after marking things read, so the badge does not lag a
  /// minute behind the list the user is looking at.
  Future<void> refresh() => _tick();
}

final unreadCountProvider =
    NotifierProvider<UnreadCountController, int>(UnreadCountController.new);

@immutable
class NotificationsState {
  const NotificationsState({
    this.items = const [],
    this.page = 0,
    this.totalPages = 0,
    this.loadingMore = false,
  });

  final List<AppNotification> items;
  final int page;
  final int totalPages;
  final bool loadingMore;

  bool get hasMore => page + 1 < totalPages;
  bool get hasUnread => items.any((n) => !n.read);

  NotificationsState copyWith({
    List<AppNotification>? items,
    int? page,
    int? totalPages,
    bool? loadingMore,
  }) =>
      NotificationsState(
        items: items ?? this.items,
        page: page ?? this.page,
        totalPages: totalPages ?? this.totalPages,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

class NotificationsController extends AsyncNotifier<NotificationsState> {
  @override
  Future<NotificationsState> build() {
    // Same reason as the other controllers: notifications are per-user, and
    // this provider outlives a sign-out.
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<NotificationsState> _load() async {
    final page = await ref.read(notificationRepositoryProvider).list();
    return NotificationsState(
      items: page.content,
      page: page.currentPage,
      totalPages: page.totalPages,
    );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncValue.data(current.copyWith(loadingMore: true));
    try {
      final next = await ref
          .read(notificationRepositoryProvider)
          .list(page: current.page + 1);
      state = AsyncValue.data(
        current.copyWith(
          items: [...current.items, ...next.content],
          page: next.currentPage,
          totalPages: next.totalPages,
          loadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncValue.data(current.copyWith(loadingMore: false));
      rethrow;
    }
  }

  /// Marks one read, updating the row immediately.
  ///
  /// Optimistic on purpose: tapping a notification should stop it looking
  /// unread at once. If the call fails the row is put back, because a
  /// notification that quietly stays unread on the server but looks read here
  /// is worse than a moment of flicker.
  Future<void> markRead(int id) async {
    final current = state.value;
    if (current == null) return;

    final index = current.items.indexWhere((n) => n.id == id);
    if (index < 0 || current.items[index].read) return;

    final optimistic = [...current.items]..[index] = current.items[index].asRead();
    state = AsyncValue.data(current.copyWith(items: optimistic));

    try {
      await ref.read(notificationRepositoryProvider).markRead(id);
      await ref.read(unreadCountProvider.notifier).refresh();
    } catch (_) {
      state = AsyncValue.data(current);
      rethrow;
    }
  }

  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null) return;

    state = AsyncValue.data(
      current.copyWith(items: current.items.map((n) => n.asRead()).toList()),
    );

    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
      await ref.read(unreadCountProvider.notifier).refresh();
    } catch (_) {
      state = AsyncValue.data(current);
      rethrow;
    }
  }
}

final notificationsControllerProvider =
    AsyncNotifierProvider<NotificationsController, NotificationsState>(
  NotificationsController.new,
);
