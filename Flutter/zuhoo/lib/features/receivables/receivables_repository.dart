import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'receivables_models.dart';

/// What happens to an invoice after it is raised.
///
/// The invoice itself — creating, listing, editing — already lives in the
/// finance module. This is everything that happens next: sending it, taking
/// money for it, crediting it and refunding it.
class ReceivablesRepository {
  ReceivablesRepository(this._api);

  final ApiClient _api;

  static const _invoices = '/company/finance/invoices';
  static const _receipts = '/company/finance/payment-receipts';

  // ── Invoice actions ─────────────────────────────────────────

  /// Emails it to the client. Empty response.
  Future<void> sendInvoice(int id) =>
      _api.post<dynamic>('$_invoices/$id/send');

  /// Empty response.
  Future<void> cancelInvoice(int id) =>
      _api.post<dynamic>('$_invoices/$id/cancel');

  // ── Credit notes ────────────────────────────────────────────

  Future<PagedResponse<CreditNote>> creditNotes({
    int? invoiceId,
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '$_invoices/credit-notes',
        CreditNote.fromJson,
        page: page,
        size: size,
        query: {if (invoiceId != null) 'invoiceId': invoiceId},
      );

  Future<CreditNote> issueCreditNote(CreditNoteRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_invoices/credit-notes',
      request.toJson(),
    );
    return CreditNote.fromJson(json);
  }

  // ── Refunds ─────────────────────────────────────────────────

  Future<PagedResponse<Refund>> refunds({
    String? status,
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '$_invoices/refunds',
        Refund.fromJson,
        page: page,
        size: size,
        query: {if (status != null) 'status': status},
      );

  /// Sends the money back. Empty response.
  Future<void> processRefund(int id) =>
      _api.post<dynamic>('$_invoices/refunds/$id/process');

  /// Turns it down. The reason is an optional **query parameter**.
  Future<void> rejectRefund(int id, String? reason) {
    final trimmed = reason?.trim();
    final query = (trimmed == null || trimmed.isEmpty)
        ? ''
        : '?reason=${Uri.encodeQueryComponent(trimmed)}';
    return _api.post<dynamic>('$_invoices/refunds/$id/reject$query');
  }

  // ── Payment receipts ────────────────────────────────────────

  Future<PagedResponse<PaymentReceipt>> receipts({
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        _receipts,
        PaymentReceipt.fromJson,
        page: page,
        size: size,
      );

  /// Says the money has cleared. Empty response, so the caller re-reads.
  Future<void> confirmReceipt(int id) =>
      _api.post<dynamic>('$_receipts/$id/confirm');

  /// Records which bank it was paid into. The bank is a **required** query
  /// parameter — the controller declares `@RequestParam String bank` with no
  /// `required = false`, so an empty one is a 400.
  Future<void> depositReceipt(int id, String bank) => _api.post<dynamic>(
        '$_receipts/$id/deposit?bank=${Uri.encodeQueryComponent(bank.trim())}',
      );

  /// Undoes it — a bounced cheque, a payment applied to the wrong invoice. The
  /// reason is optional.
  Future<void> reverseReceipt(int id, String? reason) {
    final trimmed = reason?.trim();
    final query = (trimmed == null || trimmed.isEmpty)
        ? ''
        : '?reason=${Uri.encodeQueryComponent(trimmed)}';
    return _api.post<dynamic>('$_receipts/$id/reverse$query');
  }

  Future<void> deleteReceipt(int id) => _api.delete<dynamic>('$_receipts/$id');
}

final receivablesRepositoryProvider = Provider<ReceivablesRepository>(
  (ref) => ReceivablesRepository(ref.watch(apiClientProvider)),
);

class ReceiptsController extends AsyncNotifier<List<PaymentReceipt>> {
  @override
  Future<List<PaymentReceipt>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<PaymentReceipt>> _load() async {
    final page = await ref.read(receivablesRepositoryProvider).receipts();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
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

final receiptsProvider =
    AsyncNotifierProvider<ReceiptsController, List<PaymentReceipt>>(
  ReceiptsController.new,
);

/// Which status the refund list is narrowed to. Null is all of them.
class RefundFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? status) {
    if (state == status) return;
    state = status;
  }
}

final refundFilterProvider =
    NotifierProvider<RefundFilterController, String?>(
  RefundFilterController.new,
);

class RefundsController extends AsyncNotifier<List<Refund>> {
  @override
  Future<List<Refund>> build() {
    ref.watch(currentUserProvider);
    ref.watch(refundFilterProvider);
    return _load();
  }

  Future<List<Refund>> _load() async {
    final page = await ref
        .read(receivablesRepositoryProvider)
        .refunds(status: ref.read(refundFilterProvider));
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }
}

final refundsProvider =
    AsyncNotifierProvider<RefundsController, List<Refund>>(
  RefundsController.new,
);

class CreditNotesController extends AsyncNotifier<List<CreditNote>> {
  @override
  Future<List<CreditNote>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<CreditNote>> _load() async {
    final page = await ref.read(receivablesRepositoryProvider).creditNotes();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }
}

final creditNotesProvider =
    AsyncNotifierProvider<CreditNotesController, List<CreditNote>>(
  CreditNotesController.new,
);
