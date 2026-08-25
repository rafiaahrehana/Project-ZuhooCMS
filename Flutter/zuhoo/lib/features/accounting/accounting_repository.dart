import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'accounting_models.dart';

/// The books.
///
/// Three layers, in the order things move through them: an **account** is a
/// bucket, a **journal entry** proposes a set of debits and credits against
/// those buckets, and posting it writes **ledger lines** that nothing can edit
/// afterwards.
class AccountingRepository {
  AccountingRepository(this._api);

  final ApiClient _api;

  static const _accounts = '/company/finance/chart-of-accounts';
  static const _entries = '/company/finance/journal-entries';
  static const _ledger = '/company/finance/general-ledger';

  // ── Chart of accounts ───────────────────────────────────────

  /// The whole chart, or one type of account.
  ///
  /// The type filter is a path segment. Sorted by code server-side, which is
  /// the order a chart is read in.
  Future<PagedResponse<Account>> accounts({
    String? type,
    int page = 0,
    int size = 100,
  }) =>
      _api.getPaged(
        type == null ? _accounts : '$_accounts/type/$type',
        Account.fromJson,
        page: page,
        size: size,
      );

  Future<Account> account(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_accounts/$id');
    return Account.fromJson(json);
  }

  Future<Account> createAccount(AccountRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_accounts, request.toJson());
    return Account.fromJson(json);
  }

  /// Sends the whole account — see [AccountRequest] for why an omitted flag is
  /// worse than a false one here.
  Future<Account> updateAccount(int id, AccountRequest request) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_accounts/$id',
      request.toJson(),
    );
    return Account.fromJson(json);
  }

  /// Company owner only, and refused outright once anything has been posted to
  /// it: "Cannot delete account with existing ledger entries."
  Future<void> deleteAccount(int id) => _api.delete<dynamic>('$_accounts/$id');

  // ── Journal entries ─────────────────────────────────────────

  Future<PagedResponse<JournalEntry>> entries({
    int page = 0,
    int size = 25,
  }) =>
      _api.getPaged(_entries, JournalEntry.fromJson, page: page, size: size);

  /// The list omits the lines on some backends; the detail always carries them,
  /// so a screen showing legs re-reads rather than trusting the row.
  Future<JournalEntry> entry(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_entries/$id');
    return JournalEntry.fromJson(json);
  }

  Future<JournalEntry> createEntry(JournalEntryRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_entries, request.toJson());
    return JournalEntry.fromJson(json);
  }

  /// Signs it off. **A different user than the one who created it** — the
  /// backend refuses with "You created this journal entry - a different user
  /// must approve it", which is segregation of duties, not a bug.
  ///
  /// Answers with an empty body, so the caller re-reads.
  Future<void> approveEntry(int id) =>
      _api.post<dynamic>('$_entries/$id/approve');

  /// Writes it to the ledger. Must be approved first. Also an empty body.
  Future<void> postEntry(int id) => _api.post<dynamic>('$_entries/$id/post');

  /// Posts an opposite entry against the same accounts and returns it. Only a
  /// posted, un-reversed entry can be reversed.
  Future<JournalEntry> reverseEntry(int id) async {
    final json = await _api.post<Map<String, dynamic>>('$_entries/$id/reverse');
    return JournalEntry.fromJson(json);
  }

  /// Company owner only, and only before posting — after that the ledger has
  /// moved and a reversal is the only way back.
  Future<JournalEntry> deleteEntry(int id) async {
    final json = await _api.delete<Map<String, dynamic>>('$_entries/$id');
    return JournalEntry.fromJson(json);
  }

  // ── General ledger ──────────────────────────────────────────

  /// Everything posted, one account's lines, or a date range.
  ///
  /// Three endpoints behind one method because they answer the same question
  /// with different filters, and only one filter applies at a time.
  Future<PagedResponse<LedgerLine>> ledger({
    int? accountId,
    String? start,
    String? end,
    int page = 0,
    int size = 30,
  }) {
    final String path;
    final query = <String, dynamic>{};
    if (accountId != null) {
      path = '$_ledger/account/$accountId';
    } else if (start != null && end != null) {
      path = '$_ledger/date-range';
      query['start'] = start;
      query['end'] = end;
    } else {
      path = _ledger;
    }
    return _api.getPaged(
      path,
      LedgerLine.fromJson,
      page: page,
      size: size,
      query: query,
    );
  }

  Future<LedgerLine> ledgerLine(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_ledger/$id');
    return LedgerLine.fromJson(json);
  }

  /// What one account currently stands at.
  ///
  /// Answers with a **bare number**, not an object — the endpoint declares
  /// `ResponseEntity<BigDecimal>`, so the body is `1234.56` and there is
  /// nothing to unwrap.
  Future<double> accountBalance(int accountId) async {
    final value = await _api.get<dynamic>('$_ledger/account/$accountId/balance');
    return (value as num?)?.toDouble() ?? 0;
  }

  /// Ticks a ledger line off against a bank statement. The note is an optional
  /// query parameter, and the response is empty.
  Future<void> reconcileLine(int id, String? notes) {
    final trimmed = notes?.trim();
    final query = (trimmed == null || trimmed.isEmpty)
        ? ''
        : '?notes=${Uri.encodeQueryComponent(trimmed)}';
    return _api.post<dynamic>('$_ledger/$id/reconcile$query');
  }
}

final accountingRepositoryProvider = Provider<AccountingRepository>(
  (ref) => AccountingRepository(ref.watch(apiClientProvider)),
);

/// Which type of account the chart is narrowed to. Null is the whole chart.
class AccountTypeFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? type) {
    if (state == type) return;
    state = type;
  }
}

final accountTypeFilterProvider =
    NotifierProvider<AccountTypeFilterController, String?>(
  AccountTypeFilterController.new,
);

class AccountsController extends AsyncNotifier<List<Account>> {
  @override
  Future<List<Account>> build() {
    ref.watch(currentUserProvider);
    ref.watch(accountTypeFilterProvider);
    return _load();
  }

  Future<List<Account>> _load() async {
    final page = await ref
        .read(accountingRepositoryProvider)
        .accounts(type: ref.read(accountTypeFilterProvider));
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(Account updated) {
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

final accountsProvider =
    AsyncNotifierProvider<AccountsController, List<Account>>(
  AccountsController.new,
);

/// Every account a journal entry line may name.
///
/// Kept separate from the filtered list the chart screen shows: a line picker
/// must never offer a header account, whatever the chart is currently filtered
/// to.
final postableAccountsProvider = FutureProvider<List<Account>>((ref) async {
  final page = await ref.read(accountingRepositoryProvider).accounts();
  return [
    for (final account in page.content)
      if (account.canPostTo) account,
  ];
});

class JournalEntriesController extends AsyncNotifier<List<JournalEntry>> {
  @override
  Future<List<JournalEntry>> build() {
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<List<JournalEntry>> _load() async {
    final page = await ref.read(accountingRepositoryProvider).entries();
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(JournalEntry updated) {
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

final journalEntriesProvider =
    AsyncNotifierProvider<JournalEntriesController, List<JournalEntry>>(
  JournalEntriesController.new,
);

/// One entry with its lines, re-read after every action.
final journalEntryProvider =
    FutureProvider.autoDispose.family<JournalEntry, int>(
  (ref, id) => ref.read(accountingRepositoryProvider).entry(id),
);

/// Which account the ledger is narrowed to, or null for everything.
class LedgerAccountFilterController extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? accountId) {
    if (state == accountId) return;
    state = accountId;
  }
}

final ledgerAccountFilterProvider =
    NotifierProvider<LedgerAccountFilterController, int?>(
  LedgerAccountFilterController.new,
);

class LedgerController extends AsyncNotifier<List<LedgerLine>> {
  @override
  Future<List<LedgerLine>> build() {
    ref.watch(currentUserProvider);
    ref.watch(ledgerAccountFilterProvider);
    return _load();
  }

  Future<List<LedgerLine>> _load() async {
    final page = await ref
        .read(accountingRepositoryProvider)
        .ledger(accountId: ref.read(ledgerAccountFilterProvider));
    return page.content;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  void apply(LedgerLine updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final row in current) if (row.id == updated.id) updated else row,
    ]);
  }
}

final ledgerProvider =
    AsyncNotifierProvider<LedgerController, List<LedgerLine>>(
  LedgerController.new,
);

/// What one account stands at right now.
final accountBalanceProvider =
    FutureProvider.autoDispose.family<double, int>(
  (ref, accountId) =>
      ref.read(accountingRepositoryProvider).accountBalance(accountId),
);
