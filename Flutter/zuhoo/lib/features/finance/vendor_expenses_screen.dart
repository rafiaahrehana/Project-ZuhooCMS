import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'finance_models.dart';
import 'finance_repository.dart';

/// Everything claimed against one supplier.
final vendorExpensesProvider =
    FutureProvider.autoDispose.family<List<Expense>, String>(
  (ref, vendorName) async {
    final page = await ref
        .read(financeRepositoryProvider)
        .expensesByVendor(vendorName, size: 50);
    return page.content;
  },
);

/// What has been spent with one supplier.
///
/// Matched on the name as recorded on each claim rather than on a vendor
/// record — an expense stores a name, not a link — so a supplier spelt two
/// ways appears as two suppliers. That is worth knowing when the totals here
/// look lower than expected.
class VendorExpensesScreen extends ConsumerWidget {
  const VendorExpensesScreen({super.key, required this.vendorName});

  final String vendorName;

  static void open(BuildContext context, {required String vendorName}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VendorExpensesScreen(vendorName: vendorName),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(vendorExpensesProvider(vendorName));

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: Text(vendorName)),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async =>
            ref.invalidate(vendorExpensesProvider(vendorName)),
        child: async.when(
          loading: () => const Loader(),
          error: (error, _) => ErrorState(
            message: error is ApiException
                ? error.message
                : 'Could not load those claims.',
            onRetry: () => ref.invalidate(vendorExpensesProvider(vendorName)),
          ),
          data: (expenses) {
            if (expenses.isEmpty) {
              return const EmptyState(
                icon: Icons.receipt_outlined,
                title: 'Nothing here',
                message: 'No claims recorded against that name.',
              );
            }

            // Only what has actually been settled. Pending and rejected
            // claims are shown but left out of the figure, since neither is
            // money that has left the company.
            final settled = expenses
                .where((expense) => expense.status == ExpenseStatus.paid)
                .fold<double>(0, (sum, expense) => sum + expense.amount);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Fmt.money(settled),
                              style: TextStyle(
                                color: bos.text,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'paid out across ${expenses.length} '
                              '${expenses.length == 1 ? "claim" : "claims"}',
                              style:
                                  TextStyle(color: bos.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (final expense in expenses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  expense.headline,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: bos.text,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    expense.expenseNumber,
                                    Fmt.dateShort(expense.expenseDate),
                                    if (expense.category != null)
                                      Fmt.label(expense.category),
                                  ].join('  ·  '),
                                  style: TextStyle(
                                    color: bos.muted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                Fmt.money(expense.amount),
                                style: TextStyle(
                                  color: bos.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              StatusChip(expense.status, dense: true),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
