import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/storage/json_cache.dart';
import '../profile/employee_repository.dart';

/// A company announcement, from GET /api/announcements/active.
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.priority = 0,
    this.publishedAt,
    this.createdAt,
    this.createdByName,
  });

  final int id;
  final String title;
  final String body;
  final int priority;
  final String? publishedAt;
  final String? createdAt;
  final String? createdByName;

  /// Published date if it has one, falling back to when it was written.
  String? get shownAt => publishedAt ?? createdAt;

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        priority: (json['priority'] as num?)?.toInt() ?? 0,
        publishedAt: json['publishedAt'] as String?,
        createdAt: json['createdAt'] as String?,
        createdByName: json['createdByName'] as String?,
      );
}

class Holiday {
  const Holiday({
    required this.id,
    required this.name,
    required this.holidayDate,
    this.holidayType,
  });

  final int id;
  final String name;
  final String holidayDate;
  final String? holidayType;

  /// Whole days from today. Negative once the date has passed.
  int get daysAway {
    final date = DateTime.tryParse(holidayDate);
    if (date == null) return 0;
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    return DateTime(date.year, date.month, date.day).difference(midnight).inDays;
  }

  String get countdownLabel => switch (daysAway) {
        0 => 'Today',
        1 => 'Tomorrow',
        final d when d < 0 => 'Passed',
        final d => 'in $d days',
      };

  factory Holiday.fromJson(Map<String, dynamic> json) => Holiday(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        holidayDate: json['holidayDate'] as String? ?? '',
        holidayType: json['holidayType'] as String?,
      );
}

/// The notice board and the two extra dashboard figures.
///
/// Every call here is optional. An employee without ANNOUNCEMENT_VIEW, or a
/// company that has not configured holidays, gets a 403 or an empty list — and
/// the right response to that is a shorter dashboard, not an error screen. So
/// each fetch swallows its own failure and returns nothing.
class HomeRepository {
  HomeRepository(this._api, this._cache);

  final ApiClient _api;
  final JsonCache _cache;

  static const _announcementsCacheKey = 'home_announcements';
  static const _holidaysCacheKey = 'home_holidays';

  Future<CachedList<Announcement>> activeAnnouncements() => _cachedList(
        '/announcements/active',
        Announcement.fromJson,
        _announcementsCacheKey,
      );

  Future<CachedList<Holiday>> currentYearHolidays() => _cachedList(
        '/hr/holidays/current-year',
        Holiday.fromJson,
        _holidaysCacheKey,
      );

  /// Service requests assigned to this employee that are still open.
  Future<int?> openRequestCount() async {
    try {
      final json = await _api.get<dynamic>(
        '/service-requests/assigned-to-me',
        query: {'page': 0, 'size': 50},
      );
      final content = json is Map ? json['content'] : json;
      if (content is! List) return null;
      const closed = {'COMPLETED', 'CANCELLED', 'REJECTED'};
      return content
          .whereType<Map<String, dynamic>>()
          .where((r) => !closed.contains(r['status'] as String? ?? ''))
          .length;
    } on ApiException {
      return null;
    }
  }

  /// The score on this employee's most recent performance review.
  Future<double?> latestReviewScore(int employeeId) async {
    try {
      final json = await _api.get<dynamic>(
        '/hr/performance/employee/$employeeId',
        query: {'page': 0, 'size': 1},
      );
      final content = json is Map ? json['content'] : json;
      if (content is! List || content.isEmpty) return null;
      final first = content.first;
      if (first is! Map) return null;
      return (first['overallScore'] as num?)?.toDouble();
    } on ApiException {
      return null;
    }
  }

  /// Fetches a plain list, falling back to the last cached copy when the
  /// request fails because the network itself is unreachable — not for a
  /// real "no" from the server (403, an empty company-wide list), only for
  /// "could not ask at all". A cache miss on top of that just means an empty
  /// list, same as before this existed.
  Future<CachedList<T>> _cachedList<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
    String cacheKey,
  ) async {
    try {
      final list = await _api.get<List<dynamic>>(path);
      final maps = list.whereType<Map<String, dynamic>>().toList(growable: false);
      unawaited(_cache.write(cacheKey, maps));
      return CachedList(items: maps.map(fromJson).toList(growable: false));
    } on ApiException catch (e) {
      if (e.isNetwork) {
        final cached = _cache.read(cacheKey);
        if (cached is List) {
          final items = cached
              .whereType<Map<String, dynamic>>()
              .map(fromJson)
              .toList(growable: false);
          if (items.isNotEmpty) {
            return CachedList(items: items, stale: true);
          }
        }
      }
      return const CachedList(items: []);
    }
  }
}

/// The result of [HomeRepository._cachedList]: what to show, and whether it
/// is what was actually asked for or a saved copy shown in its place because
/// the network request itself could not be made.
@immutable
class CachedList<T> {
  const CachedList({required this.items, this.stale = false});

  final List<T> items;
  final bool stale;
}

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(ref.watch(apiClientProvider), ref.watch(jsonCacheProvider)),
);

@immutable
class NoticeBoard {
  const NoticeBoard({
    this.announcements = const [],
    this.holidays = const [],
    this.openRequests,
    this.offline = false,
  });

  final List<Announcement> announcements;

  /// Upcoming only, soonest first.
  final List<Holiday> holidays;

  /// Null means "could not be determined", which renders as a dash. Zero is a
  /// real answer and renders as zero.
  final int? openRequests;

  /// True when either list above is a cached copy shown because the network
  /// request itself failed — not because the server said no. The dashboard
  /// uses this to add a small "showing saved data" note rather than pretend
  /// the figures are current.
  final bool offline;
}

/// Kept separate from [noticeBoardProvider] because it is keyed on the
/// employee id, so it can only run once the employee record has arrived.
final latestReviewScoreProvider = FutureProvider<double?>((ref) async {
  final employee = await ref.watch(myEmployeeProvider.future);
  if (employee == null) return null;
  return ref.watch(homeRepositoryProvider).latestReviewScore(employee.id);
});

final noticeBoardProvider = FutureProvider<NoticeBoard>((ref) async {
  final repo = ref.watch(homeRepositoryProvider);

  final announcementsCall = repo.activeAnnouncements();
  final holidaysCall = repo.currentYearHolidays();
  final requestsCall = repo.openRequestCount();

  // Each needs its own listener attached now, not just at the awaits below:
  // if one of these throws first, this function returns before the other two
  // are awaited, and a call nobody is still waiting on reports its own
  // rejection as an unhandled exception even though the caller already saw
  // the failure through the one that threw first.
  announcementsCall.ignore();
  holidaysCall.ignore();
  requestsCall.ignore();

  final announcementsResult = await announcementsCall;
  final holidaysResult = await holidaysCall;

  final upcoming = holidaysResult.items.where((h) => h.daysAway >= 0).toList()
    ..sort((a, b) => a.daysAway.compareTo(b.daysAway));

  final sorted = [...announcementsResult.items]..sort((a, b) {
      // Higher priority first, then most recent.
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      return (b.shownAt ?? '').compareTo(a.shownAt ?? '');
    });

  return NoticeBoard(
    announcements: sorted,
    holidays: upcoming,
    openRequests: await requestsCall,
    offline: announcementsResult.stale || holidaysResult.stale,
  );
});

/// GET /hr/dashboard/summary, trimmed to what a phone tile shows.
///
/// The response carries far more — department distribution, headcount trend,
/// the recruitment pipeline, pending approvals. Those are charts, and charts
/// on a home screen are a different feature; this parses the handful of
/// figures that answer "how is today going".
class HrSnapshot {
  const HrSnapshot({
    required this.totalEmployees,
    required this.presentToday,
    required this.onLeaveToday,
    required this.absentToday,
    required this.openPositions,
  });

  final int totalEmployees;
  final int presentToday;
  final int onLeaveToday;
  final int absentToday;
  final int openPositions;

  factory HrSnapshot.fromJson(Map<String, dynamic> json) {
    int i(String key) => (json[key] as num?)?.toInt() ?? 0;
    return HrSnapshot(
      totalEmployees: i('totalEmployees'),
      presentToday: i('presentToday'),
      onLeaveToday: i('onLeaveToday'),
      absentToday: i('absentToday'),
      openPositions: i('openPositions'),
    );
  }
}

/// GET /crm/dashboard/summary, trimmed the same way.
class CrmSnapshot {
  const CrmSnapshot({
    required this.pipelineValue,
    required this.wonThisMonth,
    required this.qualifiedLeads,
    required this.openOpportunities,
  });

  final double pipelineValue;
  final double wonThisMonth;
  final int qualifiedLeads;
  final int openOpportunities;

  factory CrmSnapshot.fromJson(Map<String, dynamic> json) => CrmSnapshot(
        pipelineValue: (json['pipelineValue'] as num?)?.toDouble() ?? 0,
        wonThisMonth: (json['wonThisMonth'] as num?)?.toDouble() ?? 0,
        qualifiedLeads: (json['qualifiedLeadsCount'] as num?)?.toInt() ?? 0,
        openOpportunities:
            (json['openOpportunitiesCount'] as num?)?.toInt() ?? 0,
      );
}

/// Today's HR figures, or null when the reader is not entitled to them.
///
/// Null rather than an error: the summary is gated on EMPLOYEE_VIEW, and a
/// home screen that fails because one optional tile 403s is worse than a home
/// screen with one fewer tile.
final hrSnapshotProvider = FutureProvider<HrSnapshot?>((ref) async {
  ref.watch(currentUserProvider);
  try {
    final json = await ref
        .read(apiClientProvider)
        .get<Map<String, dynamic>>('/hr/dashboard/summary');
    return HrSnapshot.fromJson(json);
  } on ApiException catch (e) {
    if (e.isForbidden || e.isNotFound) return null;
    rethrow;
  }
});

/// The same, for CRM.
final crmSnapshotProvider = FutureProvider<CrmSnapshot?>((ref) async {
  ref.watch(currentUserProvider);
  try {
    final json = await ref
        .read(apiClientProvider)
        .get<Map<String, dynamic>>('/crm/dashboard/summary');
    return CrmSnapshot.fromJson(json);
  } on ApiException catch (e) {
    if (e.isForbidden || e.isNotFound) return null;
    rethrow;
  }
});
