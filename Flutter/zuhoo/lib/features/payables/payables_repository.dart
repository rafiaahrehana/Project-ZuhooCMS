import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../reports/report_models.dart' show Ageing;
import 'payables_models.dart';

/// Accounts payable.
class PayablesRepository {
  PayablesRepository(this._api);

  final ApiClient _api;

  static const _vendors = '/company/finance/vendors';
  static const _bills = '/company/finance/vendor-bills';

  // ── Vendors ─────────────────────────────────────────────────

  Future<PagedResponse<Vendor>> vendors({
    String? search,
    int page = 0,
    int size = 50,
  }) =>
      _api.getPaged(
        _vendors,
        Vendor.fromJson,
        page: page,
        size: size,
        query: {if (search != null && search.isNotEmpty) 'search': search},
      );

  /// Those still trading with, as a bare list. What a bill form picks from.
  Future<List<Vendor>> activeVendors() async {
    final list = await _api.get<List<dynamic>>('$_vendors/active');
    return list
        .whereType<Map<String, dynamic>>()
        .map(Vendor.fromJson)
        .toList(growable: false);
  }

  Future<Vendor> createVendor(VendorRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_vendors, request.toJson());
    return Vendor.fromJson(json);
  }

  Future<Vendor> updateVendor(int id, VendorRequest request) async {
    final json = await _api.put<Map<String, dynamic>>(
      '$_vendors/$id',
      request.toJson(),
    );
    return Vendor.fromJson(json);
  }

  Future<Vendor> toggleVendor(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('$_vendors/$id/toggle');
    return Vendor.fromJson(json);
  }

  Future<void> deleteVendor(int id) => _api.delete<dynamic>('$_vendors/$id');

  // ── Bills ───────────────────────────────────────────────────

  /// Both filters are **query parameters** here, unlike most of the finance
  /// module where they are path segments — and unusually, both can apply at
  /// once.
  Future<PagedResponse<VendorBill>> bills({
    String? status,
    int? vendorId,
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        _bills,
        VendorBill.fromJson,
        page: page,
        size: size,
        query: {
          if (status != null) 'status': status,
          if (vendorId != null) 'vendorId': vendorId,
        },
      );

  Future<VendorBill> createBill(VendorBillRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_bills, request.toJson());
    return VendorBill.fromJson(json);
  }

  /// Signs it off. **A different user than the one who entered it** — the same
  /// segregation of duties the journal entries enforce, with the same kind of
  /// message: "You entered this bill - a different user must approve it".
  Future<VendorBill> approveBill(int id) async {
    final json = await _api.post<Map<String, dynamic>>('$_bills/$id/approve');
    return VendorBill.fromJson(json);
  }

  /// Records a payment against it. The amount is a **query parameter**, and it
  /// is refused if it exceeds the outstanding balance — the message names the
  /// balance, so it is worth showing as written.
  Future<VendorBill> payBill(int id, double amount) async {
    final json =
        await _api.post<Map<String, dynamic>>('$_bills/$id/pay?amount=$amount');
    return VendorBill.fromJson(json);
  }

  /// Refused once anything has been paid against it.
  Future<VendorBill> cancelBill(int id) async {
    final json = await _api.post<Map<String, dynamic>>('$_bills/$id/cancel');
    return VendorBill.fromJson(json);
  }

  /// What is owed out, bucketed by how late it is.
  ///
  /// The same shape as the receivables ageing report, so it reuses that model
  /// — the line fields differ only in being about bills and vendors rather
  /// than invoices and clients, which [Ageing] reads either way.
  Future<Ageing> apAgeing({String? asOfDate}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_bills/ap-ageing',
      query: {if (asOfDate != null) 'asOfDate': asOfDate},
    );
    return Ageing.fromJson(json);
  }
}

final payablesRepositoryProvider = Provider<PayablesRepository>(
  (ref) => PayablesRepository(ref.watch(apiClientProvider)),
);

class VendorsController extends AsyncNotifier<List<Vendor>> {
  @override
  Future<List<Vendor>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<Vendor>> _load() async {
    final page = await ref.read(payablesRepositoryProvider).vendors();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(Vendor updated) {
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

final vendorsProvider =
    AsyncNotifierProvider<VendorsController, List<Vendor>>(
  VendorsController.new,
);

/// Vendors a new bill can be raised against.
final activeVendorsProvider = FutureProvider<List<Vendor>>(
  (ref) => ref.read(payablesRepositoryProvider).activeVendors(),
);

/// Which status the bill list is narrowed to. Null is all of them.
class BillStatusFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? status) {
    if (state == status) return;
    state = status;
  }
}

final billStatusFilterProvider =
    NotifierProvider<BillStatusFilterController, String?>(
  BillStatusFilterController.new,
);

class BillsController extends AsyncNotifier<List<VendorBill>> {
  @override
  Future<List<VendorBill>> build() {
    ref.watch(currentUserProvider);
    ref.watch(billStatusFilterProvider);
    return _load();
  }

  Future<List<VendorBill>> _load() async {
    final page = await ref
        .read(payablesRepositoryProvider)
        .bills(status: ref.read(billStatusFilterProvider));
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(VendorBill updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final billsProvider =
    AsyncNotifierProvider<BillsController, List<VendorBill>>(
  BillsController.new,
);

/// What is owed out, as at today.
final apAgeingProvider = FutureProvider.autoDispose<Ageing>(
  (ref) => ref.read(payablesRepositoryProvider).apAgeing(),
);
