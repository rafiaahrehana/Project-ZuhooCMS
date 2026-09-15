/// A per-category spending cap for a fiscal year, with a live rollup of what
/// has actually been spent against it.
abstract final class BudgetPermissions {
  static const view = 'BUDGET_VIEW';
  static const manage = 'BUDGET_MANAGE';
}

class Budget {
  const Budget({
    required this.id,
    required this.category,
    required this.fiscalYear,
    required this.amount,
    required this.actualSpend,
    required this.remaining,
    required this.usedPercent,
    required this.overBudget,
    this.notes,
  });

  final int id;
  final String category;
  final int fiscalYear;
  final double amount;
  final String? notes;

  /// Approved/paid expenses plus posted vendor bills against this category,
  /// for the company's fiscal year window — computed server-side, never
  /// entered by hand.
  final double actualSpend;
  final double remaining;
  final double usedPercent;
  final bool overBudget;

  /// For the progress bar. `usedPercent` can run past 100 when over budget,
  /// which would overflow the bar rather than just fill it.
  double get progress => amount <= 0 ? 0 : (actualSpend / amount).clamp(0, 1);

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
        id: (json['id'] as num?)?.toInt() ?? 0,
        category: json['category'] as String? ?? '',
        fiscalYear: (json['fiscalYear'] as num?)?.toInt() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        notes: json['notes'] as String?,
        actualSpend: (json['actualSpend'] as num?)?.toDouble() ?? 0,
        remaining: (json['remaining'] as num?)?.toDouble() ?? 0,
        usedPercent: (json['usedPercent'] as num?)?.toDouble() ?? 0,
        overBudget: json['overBudget'] as bool? ?? false,
      );
}

/// POST and PUT /company/finance/budgets
///
/// One budget per category+fiscalYear — the backend refuses a duplicate on
/// create with a message naming both.
class BudgetRequest {
  const BudgetRequest({
    required this.category,
    required this.fiscalYear,
    required this.amount,
    this.notes,
  });

  final String category;
  final int fiscalYear;
  final double amount;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'category': category.trim(),
        'fiscalYear': fiscalYear,
        'amount': amount,
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
      };
}
