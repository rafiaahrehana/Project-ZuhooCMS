import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../payslips/payslip_models.dart' show Payslip;
import 'payroll_models.dart';

/// Running payroll for the company.
///
/// Two layers that are easy to confuse. A **run** is the monthly batch — one
/// per period, with its own approval chain and totals. A **payroll** is one
/// employee's line within it. The run endpoints live under `/hr/payroll-runs`
/// and the line endpoints under `/hr/payroll`; both are here because the screen
/// moves between them constantly.
class PayrollRepository {
  PayrollRepository(this._api);

  final ApiClient _api;

  static const _runs = '/hr/payroll-runs';
  static const _payroll = '/hr/payroll';

  // ── Runs ────────────────────────────────────────────────────

  /// A bare list, not a page — a company has one run per month and the whole
  /// history is short.
  Future<List<PayrollRun>> runs() async {
    final list = await _api.get<List<dynamic>>(_runs);
    return list
        .whereType<Map<String, dynamic>>()
        .map(PayrollRun.fromJson)
        .toList(growable: false);
  }

  /// The run for one period, or null when none has been started.
  ///
  /// A missing run is the normal state at the beginning of a month, not an
  /// error, so a 404 comes back as null rather than throwing.
  Future<PayrollRun?> runForPeriod(int month, int year) async {
    try {
      final json = await _api.get<Map<String, dynamic>>(
        '$_runs/period',
        query: {'month': month, 'year': year},
      );
      return PayrollRun.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Opens a run for a period. Refused when one already exists, with a message
  /// naming the run that does.
  Future<PayrollRun> createRun(int month, int year, String? remarks) async {
    final trimmed = remarks?.trim();
    final json = await _api.post<Map<String, dynamic>>(_runs, {
      'month': month,
      'year': year,
      if (trimmed != null && trimmed.isNotEmpty) 'remarks': trimmed,
    });
    return PayrollRun.fromJson(json);
  }

  Future<PayrollRun> recalculate(int id) => _runAction(id, 'recalculate');
  Future<PayrollRun> submit(int id) => _runAction(id, 'submit');
  Future<PayrollRun> approve(int id) => _runAction(id, 'approve');
  Future<PayrollRun> cancel(int id) => _runAction(id, 'cancel');

  /// The reason travels as a **body**, not a query parameter — this controller
  /// takes `@RequestBody RejectRequest(String reason)`, unlike the several
  /// reject endpoints elsewhere in the app that take a `@RequestParam`.
  Future<PayrollRun> reject(int id, String reason) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_runs/$id/reject',
      {'reason': reason.trim()},
    );
    return PayrollRun.fromJson(json);
  }

  /// Pays every unpaid line in the run.
  ///
  /// The reference prefix is optional: without one the backend uses the run
  /// number, and each line gets that plus a three-digit sequence.
  Future<PayrollRun> pay(
    int id, {
    required String paymentMethod,
    String? referencePrefix,
    String? paymentDate,
  }) async {
    final trimmed = referencePrefix?.trim();
    final json = await _api.post<Map<String, dynamic>>('$_runs/$id/pay', {
      'paymentMethod': paymentMethod,
      if (trimmed != null && trimmed.isNotEmpty) 'referencePrefix': trimmed,
      if (paymentDate != null) 'paymentDate': paymentDate,
    });
    return PayrollRun.fromJson(json);
  }

  Future<PayrollRun> _runAction(int id, String action) async {
    final json = await _api.post<Map<String, dynamic>>('$_runs/$id/$action');
    return PayrollRun.fromJson(json);
  }

  // ── Lines ───────────────────────────────────────────────────

  /// Everybody's payroll for one period.
  Future<PagedResponse<Payslip>> forPeriod(
    int month,
    int year, {
    int page = 0,
    int size = 50,
  }) =>
      _api.getPaged(
        _payroll,
        Payslip.fromJson,
        page: page,
        size: size,
        query: {'month': month, 'year': year},
      );

  Future<Payslip> line(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_payroll/$id');
    return Payslip.fromJson(json);
  }

  /// Builds a draft line for everybody with a salary structure.
  ///
  /// Both parameters are query parameters, and both are required. Anybody
  /// without a structure is skipped and named in the answer — see
  /// [BulkPayrollResult].
  Future<BulkPayrollResult> generate(int month, int year) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_payroll/generate?month=$month&year=$year',
    );
    return BulkPayrollResult.fromJson(json);
  }

  Future<Payslip> approveLine(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('$_payroll/$id/approve');
    return Payslip.fromJson(json);
  }

  /// Marks one line paid. Both parameters are optional query parameters.
  Future<Payslip> payLine(
    int id, {
    String? paymentReference,
    String? paymentMethod,
  }) async {
    final params = <String>[
      if (paymentReference != null && paymentReference.trim().isNotEmpty)
        'paymentReference=${Uri.encodeQueryComponent(paymentReference.trim())}',
      if (paymentMethod != null) 'paymentMethod=$paymentMethod',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final json =
        await _api.patch<Map<String, dynamic>>('$_payroll/$id/pay$query');
    return Payslip.fromJson(json);
  }

  /// `deleteText`: this endpoint declares `ResponseEntity<String>` and answers
  /// with a sentence rather than JSON.
  Future<void> deleteLine(int id) => _api.deleteText('$_payroll/$id');

  /// The bank disbursement file for a period, written to a temporary file.
  ///
  /// Comes back as **CSV text**, not JSON — the endpoint declares
  /// `produces = "text/csv"` — so it is fetched as bytes and saved rather than
  /// parsed. Returns the path, for the caller to hand to a viewer.
  Future<String> disbursementCsv(int month, int year) => _download(
        '$_payroll/disbursement',
        month,
        year,
        'disbursement',
        'csv',
      );

  /// The month's salary sheet as a PDF. Both parameters are optional
  /// server-side; the screen always knows which month it is looking at.
  Future<String> salarySheetPdf(int month, int year) => _download(
        '/hr/salary-sheet/export',
        month,
        year,
        'salary-sheet',
        'pdf',
      );

  /// Fetches bytes and writes them somewhere a viewer can open them. The same
  /// shape the payslip download already uses.
  Future<String> _download(
    String path,
    int month,
    int year,
    String name,
    String extension,
  ) async {
    final bytes =
        await _api.getBytes(path, query: {'month': month, 'year': year});
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      '$name-$year-${month.toString().padLeft(2, '0')}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // ── Dashboard and settings ──────────────────────────────────

  /// One month at a glance. Both parameters are optional; without them the
  /// backend answers for the current month.
  Future<PayrollDashboard> dashboard({int? month, int? year}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/hr/payroll-dashboard',
      query: {
        if (month != null) 'month': month,
        if (year != null) 'year': year,
      },
    );
    return PayrollDashboard.fromJson(json);
  }

  Future<PayrollSettings> settings() async {
    final json = await _api.get<Map<String, dynamic>>('/hr/payroll-settings');
    return PayrollSettings.fromJson(json);
  }

  /// Every field is null-guarded server-side, so this is one of the few updates
  /// in the codebase where omitting a key is genuinely safe. The form sends all
  /// of them anyway — see [PayrollSettingsRequest].
  Future<PayrollSettings> updateSettings(PayrollSettingsRequest request) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/hr/payroll-settings',
      request.toJson(),
    );
    return PayrollSettings.fromJson(json);
  }
}

final payrollRepositoryProvider = Provider<PayrollRepository>(
  (ref) => PayrollRepository(ref.watch(apiClientProvider)),
);

/// Which month the payroll screens are looking at.
///
/// Shared by the dashboard, the run and the lines, so moving month moves all
/// three together rather than leaving them disagreeing.
class PayrollPeriodController extends Notifier<({int month, int year})> {
  @override
  ({int month, int year}) build() {
    final now = DateTime.now();
    return (month: now.month, year: now.year);
  }

  void set(int month, int year) {
    if (state.month == month && state.year == year) return;
    state = (month: month, year: year);
  }

  /// Steps a whole month at a time, rolling the year over.
  void shift(int months) {
    final moved = DateTime(state.year, state.month + months);
    state = (month: moved.month, year: moved.year);
  }
}

final payrollPeriodProvider =
    NotifierProvider<PayrollPeriodController, ({int month, int year})>(
  PayrollPeriodController.new,
);

class PayrollRunsController extends AsyncNotifier<List<PayrollRun>> {
  @override
  Future<List<PayrollRun>> build() {
    ref.watch(currentUserProvider);
    return ref.read(payrollRepositoryProvider).runs();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(payrollRepositoryProvider).runs(),
    );
  }

  void apply(PayrollRun updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final payrollRunsProvider =
    AsyncNotifierProvider<PayrollRunsController, List<PayrollRun>>(
  PayrollRunsController.new,
);

/// The dashboard for whichever month is selected.
final payrollDashboardProvider =
    FutureProvider.autoDispose<PayrollDashboard>((ref) {
  final period = ref.watch(payrollPeriodProvider);
  return ref
      .read(payrollRepositoryProvider)
      .dashboard(month: period.month, year: period.year);
});

/// Everybody's lines for whichever month is selected.
final payrollLinesProvider =
    FutureProvider.autoDispose<List<Payslip>>((ref) async {
  final period = ref.watch(payrollPeriodProvider);
  final page = await ref
      .read(payrollRepositoryProvider)
      .forPeriod(period.month, period.year);
  return page.content;
});

final payrollSettingsProvider = FutureProvider<PayrollSettings>((ref) {
  ref.watch(currentUserProvider);
  return ref.read(payrollRepositoryProvider).settings();
});
