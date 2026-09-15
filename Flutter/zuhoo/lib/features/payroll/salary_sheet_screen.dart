import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/stat_card.dart';
import 'payroll_repository.dart';
import 'salary_sheet_models.dart';

/// The sheet for whichever month payroll is looking at.
final salarySheetProvider = FutureProvider.autoDispose<SalarySheet>((ref) {
  final period = ref.watch(payrollPeriodProvider);
  return ref.read(payrollRepositoryProvider).salarySheet(
        period.month,
        period.year,
      );
});

/// What the month costs, person by person.
///
/// Worked out live rather than read from anywhere: it reflects the structures
/// and the attendance recorded so far, and it moves as attendance is
/// corrected. A row that has been run carries a payroll id; the rest are
/// projections, and the screen says which is which.
class SalarySheetScreen extends ConsumerWidget {
  const SalarySheetScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SalarySheetScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final period = ref.watch(payrollPeriodProvider);
    final async = ref.watch(salarySheetProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Salary sheet'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                Fmt.monthYear(period.month, period.year),
                style: TextStyle(color: bos.muted, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async => ref.invalidate(salarySheetProvider),
        child: async.when(
          loading: () => const Loader(),
          error: (error, _) => ErrorState(
            message: error is ApiException
                ? error.message
                : 'Could not work out this month.',
            onRetry: () => ref.invalidate(salarySheetProvider),
          ),
          data: (sheet) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'Net to pay',
                      value: Fmt.money(sheet.totals.netPayable),
                      icon: Icons.payments_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatCard(
                      label: 'People',
                      value: sheet.rows.length.toString(),
                      icon: Icons.groups_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'Gross',
                      value: Fmt.money(sheet.totals.grossEarnings),
                      icon: Icons.trending_up_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatCard(
                      label: 'Deductions',
                      value: Fmt.money(sheet.totals.deductions),
                      icon: Icons.trending_down_rounded,
                    ),
                  ),
                ],
              ),
              if (sheet.perDayBasis != null) ...[
                const SizedBox(height: 12),
                Text(
                  'A day is worked out on ${Fmt.label(sheet.perDayBasis)}'
                  '${sheet.perDayDivisor > 0 ? " over ${sheet.perDayDivisor} days" : ""}'
                  '${sheet.overtimeEnabled && sheet.overtimeMultiplier != null ? ", overtime at ${sheet.overtimeMultiplier}x" : ""}.',
                  style: TextStyle(
                    color: bos.muted,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SectionHeader(
                'Line by line',
                icon: Icons.list_alt_rounded,
                trailing: Text(
                  '${sheet.rows.where((row) => row.isRun).length} run',
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ),
              if (sheet.rows.isEmpty)
                AppCard(
                  child: Text(
                    'Nobody has a salary structure that covers this month, so '
                    'there is nothing to work out.',
                    style: TextStyle(
                      color: bos.muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                )
              else
                for (final row in sheet.rows) _Row(row: row),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({required this.row});

  final SalarySheetRow row;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final row = widget.row;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: () => setState(() => _open = !_open),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.personLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        [
                          if (row.position != null) row.position!,
                          if (row.department != null) row.department!,
                          if (row.absentDays > 0) '${row.absentDays} absent',
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: bos.muted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Fmt.money(row.netPayable),
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      // The distinction that matters on this screen: run
                      // means paid or about to be, projected means nothing
                      // has happened yet.
                      row.isRun
                          ? Fmt.label(row.paymentStatus ?? 'RUN')
                          : 'projected',
                      style: TextStyle(
                        color: row.isRun ? bos.success : bos.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_open) ...[
              Divider(color: bos.border, height: 20),
              _Line('Basic', row.basic),
              if (row.houseRent > 0) _Line('House rent', row.houseRent),
              if (row.medical > 0) _Line('Medical', row.medical),
              if (row.transport > 0) _Line('Transport', row.transport),
              if (row.food > 0) _Line('Food', row.food),
              if (row.special > 0) _Line('Special', row.special),
              if (row.overtimePayment > 0)
                _Line(
                  'Overtime (${Fmt.plain(row.overtimeHours)}h)',
                  row.overtimePayment,
                ),
              if (row.bonus > 0) _Line('Bonus', row.bonus),
              if (row.otherEarnings > 0) _Line('Other', row.otherEarnings),
              _Line('Gross', row.grossEarnings, bold: true),
              if (row.absentDeduction > 0)
                _Line('Absence', -row.absentDeduction),
              if (row.tax > 0) _Line('Tax', -row.tax),
              if (row.providentFund > 0)
                _Line('Provident fund', -row.providentFund),
              if (row.otherDeductions > 0)
                _Line('Other deductions', -row.otherDeductions),
              _Line('Net', row.netPayable, bold: true),
              if (row.note != null && row.note!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    row.note!,
                    style: TextStyle(
                      color: bos.muted,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
              if (row.source != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'from ${Fmt.label(row.source)}',
                    style: TextStyle(color: bos.muted, fontSize: 11),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.amount, {this.bold = false});

  final String label;
  final double amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: bold ? bos.text : bos.muted,
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            Fmt.money(amount),
            style: TextStyle(
              color: amount < 0 ? bos.danger : bos.text,
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
