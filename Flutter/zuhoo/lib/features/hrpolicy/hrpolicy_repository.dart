import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'hrpolicy_models.dart';

/// The standing HR rules.
class HrPolicyRepository {
  HrPolicyRepository(this._api);

  final ApiClient _api;

  static const _holidays = '/hr/holidays';
  static const _policies = '/hr/leave-policies';
  static const _shifts = '/hr/shifts';
  static const _letters = '/hr/letters';

  // ── Holidays ────────────────────────────────────────────────

  /// One year's holidays. A bare list — a calendar year has a couple of dozen
  /// at most, and they only mean anything grouped by year.
  Future<List<Holiday>> holidaysForYear(int year) async {
    final list = await _api.get<List<dynamic>>('$_holidays/year/$year');
    return list
        .whereType<Map<String, dynamic>>()
        .map(Holiday.fromJson)
        .toList(growable: false);
  }

  Future<Holiday> createHoliday(HolidayRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_holidays, request.toJson());
    return Holiday.fromJson(json);
  }

  Future<Holiday> updateHoliday(int id, HolidayRequest request) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_holidays/$id',
      request.toJson(),
    );
    return Holiday.fromJson(json);
  }

  Future<void> deleteHoliday(int id) => _api.deleteText('$_holidays/$id');

  /// Proposes one holiday from an instruction — "Eid al-Fitr next year".
  /// Nothing is saved; the answer fills the form in.
  Future<({String name, String date, String type, String? description})>
      draftHoliday(String instructions) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_holidays/ai-draft',
      {'instructions': instructions.trim()},
    );
    return (
      name: json['name'] as String? ?? '',
      date: json['date'] as String? ?? '',
      type: json['type'] as String? ?? 'COMPANY',
      description: json['description'] as String?,
    );
  }

  // ── Leave policies ──────────────────────────────────────────

  Future<PagedResponse<LeavePolicy>> policies({
    int page = 0,
    int size = 50,
  }) =>
      _api.getPaged(_policies, LeavePolicy.fromJson, page: page, size: size);

  Future<LeavePolicy> createPolicy(LeavePolicyRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_policies, request.toJson());
    return LeavePolicy.fromJson(json);
  }

  Future<LeavePolicy> updatePolicy(int id, LeavePolicyRequest request) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_policies/$id',
      request.toJson(),
    );
    return LeavePolicy.fromJson(json);
  }

  Future<void> deletePolicy(int id) => _api.deleteText('$_policies/$id');

  /// Writes a leave policy document from the entitlements already configured.
  ///
  /// Returns prose, not a policy record — this drafts the *document* a company
  /// hands to staff, from the rules that already exist. Nothing is saved.
  Future<String> draftPolicyDocument({
    required bool remoteWorkAllowed,
    String? additionalContext,
  }) async {
    final trimmed = additionalContext?.trim();
    final json = await _api.post<Map<String, dynamic>>('$_policies/draft', {
      'remoteWorkAllowed': remoteWorkAllowed,
      if (trimmed != null && trimmed.isNotEmpty) 'additionalContext': trimmed,
    });
    return json['document'] as String? ?? '';
  }

  // ── Shifts ──────────────────────────────────────────────────

  Future<PagedResponse<Shift>> shifts({int page = 0, int size = 50}) =>
      _api.getPaged(_shifts, Shift.fromJson, page: page, size: size);

  Future<Shift> createShift(ShiftRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_shifts, request.toJson());
    return Shift.fromJson(json);
  }

  Future<Shift> updateShift(int id, ShiftRequest request) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_shifts/$id',
      request.toJson(),
    );
    return Shift.fromJson(json);
  }

  Future<Shift> toggleShift(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('$_shifts/$id/toggle');
    return Shift.fromJson(json);
  }

  Future<void> deleteShift(int id) => _api.deleteText('$_shifts/$id');

  // ── Letters ─────────────────────────────────────────────────

  Future<PagedResponse<HrLetter>> letters({int page = 0, int size = 30}) =>
      _api.getPaged(_letters, HrLetter.fromJson, page: page, size: size);

  /// Every letter about one person.
  Future<PagedResponse<HrLetter>> lettersFor(
    int employeeId, {
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '$_letters/employee/$employeeId',
        HrLetter.fromJson,
        page: page,
        size: size,
      );

  Future<HrLetter> createLetter(HrLetterRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_letters, request.toJson());
    return HrLetter.fromJson(json);
  }

  /// Marks it as issued. One way — there is no unissuing a letter that has
  /// been handed over.
  Future<HrLetter> issueLetter(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('$_letters/$id/issue');
    return HrLetter.fromJson(json);
  }

  Future<void> deleteLetter(int id) => _api.deleteText('$_letters/$id');

  /// Drafts a letter's body for a person and a type. Nothing is saved.
  Future<String> draftLetter({
    required String letterType,
    int? employeeId,
    int? jobApplicationId,
  }) async {
    final json = await _api.post<Map<String, dynamic>>('$_letters/draft', {
      'letterType': letterType,
      if (employeeId != null) 'employeeId': employeeId,
      if (jobApplicationId != null) 'jobApplicationId': jobApplicationId,
    });
    return json['content'] as String? ?? '';
  }
}

final hrPolicyRepositoryProvider = Provider<HrPolicyRepository>(
  (ref) => HrPolicyRepository(ref.watch(apiClientProvider)),
);

/// Which year of holidays is showing.
class HolidayYearController extends Notifier<int> {
  @override
  int build() => DateTime.now().year;

  void set(int year) {
    if (state == year) return;
    state = year;
  }
}

final holidayYearProvider =
    NotifierProvider<HolidayYearController, int>(HolidayYearController.new);

class HolidaysController extends AsyncNotifier<List<Holiday>> {
  @override
  Future<List<Holiday>> build() {
    ref.watch(currentUserProvider);
    ref.watch(holidayYearProvider);
    return _load();
  }

  Future<List<Holiday>> _load() => ref
      .read(hrPolicyRepositoryProvider)
      .holidaysForYear(ref.read(holidayYearProvider));

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(Holiday updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }

  void remove(int id) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current)
        if (row.id != id) row,
    ]);
  }
}

final holidaysProvider =
    AsyncNotifierProvider<HolidaysController, List<Holiday>>(
  HolidaysController.new,
);

class LeavePoliciesController extends AsyncNotifier<List<LeavePolicy>> {
  @override
  Future<List<LeavePolicy>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<LeavePolicy>> _load() async {
    final page = await ref.read(hrPolicyRepositoryProvider).policies();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(LeavePolicy updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }

  void remove(int id) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current)
        if (row.id != id) row,
    ]);
  }
}

final leavePoliciesProvider =
    AsyncNotifierProvider<LeavePoliciesController, List<LeavePolicy>>(
  LeavePoliciesController.new,
);

class ShiftsController extends AsyncNotifier<List<Shift>> {
  @override
  Future<List<Shift>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<Shift>> _load() async {
    final page = await ref.read(hrPolicyRepositoryProvider).shifts();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(Shift updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }

  void remove(int id) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current)
        if (row.id != id) row,
    ]);
  }
}

final hrShiftsProvider =
    AsyncNotifierProvider<ShiftsController, List<Shift>>(ShiftsController.new);

class LettersController extends AsyncNotifier<List<HrLetter>> {
  @override
  Future<List<HrLetter>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<HrLetter>> _load() async {
    final page = await ref.read(hrPolicyRepositoryProvider).letters();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(HrLetter updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }

  void remove(int id) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current)
        if (row.id != id) row,
    ]);
  }
}

final lettersProvider =
    AsyncNotifierProvider<LettersController, List<HrLetter>>(
  LettersController.new,
);

/// Every letter about one person, for their file.
final lettersForEmployeeProvider =
    FutureProvider.autoDispose.family<List<HrLetter>, int>(
  (ref, employeeId) async {
    final page =
        await ref.read(hrPolicyRepositoryProvider).lettersFor(employeeId);
    return page.content;
  },
);
