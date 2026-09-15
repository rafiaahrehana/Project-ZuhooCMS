import '../../shared/util/formatters.dart';
import '../portal/portal_models.dart' show Invoice, InvoiceItem;

/// Permission codes this module gates on. Each screen asks for the one the
/// backend enforces for its own endpoints, so a user sees exactly the tabs
/// they could actually load.
abstract final class FinancePermissions {
  static const reportView = 'FINANCIAL_REPORT_VIEW';
  static const invoiceView = 'INVOICE_VIEW';
  static const expenseView = 'EXPENSE_VIEW';

  // Deciding a claim is a different entitlement from reading one, and the
  // two decisions are separate again: ExpenseServiceImpl checks
  // EXPENSE_APPROVE to approve and EXPENSE_REJECT to reject. Gating either
  // button on expenseView shows both to every claimant in the company.
  static const expenseApprove = 'EXPENSE_APPROVE';
  static const expenseReject = 'EXPENSE_REJECT';
  static const walletView = 'WALLET_VIEW';

  static const invoiceCreate = 'INVOICE_CREATE';
  static const invoiceUpdate = 'INVOICE_UPDATE';

  /// Deleting an invoice is `hasRole('COMPANY_OWNER')` at the controller —
  /// the permission code exists but the role is what actually decides, so the
  /// UI checks both rather than showing an action only an owner can complete.
  static const invoiceDelete = 'INVOICE_DELETE';

  static const receiptCreate = 'PAYMENT_RECEIPT_CREATE';
}

abstract final class ExpenseStatus {
  static const pending = 'PENDING';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED';
  static const paid = 'PAID';
  static const cancelled = 'CANCELLED';

  static const all = [pending, approved, rejected, paid, cancelled];
}

/// Headline figures for one month — GET /finance/dashboard?month&year.
///
/// The wide parts of the web dashboard (budget lines, category breakdown, the
/// twelve-month trend table) are deliberately not modelled: they are
/// multi-column comparisons that a phone cannot show enough of to be useful,
/// and half a comparison is worse than none.
class FinanceOverview {
  const FinanceOverview({
    required this.month,
    required this.year,
    this.totalRevenue = 0,
    this.totalExpenses = 0,
    this.netProfit = 0,
    this.cashCollected = 0,
    this.outstanding = 0,
    this.overdue = 0,
    this.payables = 0,
    this.payablesOverdue = 0,
    this.payrollCost = 0,
    this.revenueChangePercent,
    this.expenseChangePercent,
    this.recentInvoices = const [],
  });

  final int month;
  final int year;
  final double totalRevenue;
  final double totalExpenses;
  final double netProfit;
  final double cashCollected;

  /// Invoiced but not yet collected.
  final double outstanding;

  /// The part of [outstanding] that is late.
  final double overdue;

  final double payables;
  final double payablesOverdue;
  final double payrollCost;

  /// Month-on-month movement. Null on the first month with data — there is
  /// nothing to compare against, and 0% would claim there was.
  final double? revenueChangePercent;
  final double? expenseChangePercent;

  final List<InvoiceLine> recentInvoices;

  bool get isProfitable => netProfit >= 0;

  /// Share of what is owed that has gone past due, or null when nothing is
  /// owed at all — 0% would read as "all healthy" rather than "nothing out".
  double? get overdueShare {
    if (outstanding <= 0) return null;
    return (overdue / outstanding).clamp(0.0, 1.0);
  }

  factory FinanceOverview.fromJson(Map<String, dynamic> json) {
    double d(String key) => (json[key] as num?)?.toDouble() ?? 0;
    final now = DateTime.now();
    return FinanceOverview(
      month: (json['payMonth'] as num?)?.toInt() ?? now.month,
      year: (json['payYear'] as num?)?.toInt() ?? now.year,
      totalRevenue: d('totalRevenue'),
      totalExpenses: d('totalExpenses'),
      netProfit: d('netProfit'),
      cashCollected: d('cashCollected'),
      outstanding: d('outstanding'),
      overdue: d('overdue'),
      payables: d('payables'),
      payablesOverdue: d('payablesOverdue'),
      payrollCost: d('payrollCost'),
      revenueChangePercent: (json['revenueChangePercent'] as num?)?.toDouble(),
      expenseChangePercent: (json['expenseChangePercent'] as num?)?.toDouble(),
      recentInvoices: (json['recentInvoices'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(InvoiceLine.fromJson)
              .toList() ??
          const [],
    );
  }
}

/// A compact invoice row as the dashboard returns it — fewer fields than the
/// full invoice, and it carries its own `overdue` flag rather than making the
/// caller work it out.
class InvoiceLine {
  const InvoiceLine({
    required this.id,
    required this.invoiceNumber,
    required this.totalAmount,
    required this.balanceAmount,
    required this.status,
    required this.overdue,
    this.clientName,
    this.dueDate,
  });

  final int id;
  final String invoiceNumber;
  final double totalAmount;
  final double balanceAmount;
  final String status;
  final bool overdue;
  final String? clientName;
  final String? dueDate;

  factory InvoiceLine.fromJson(Map<String, dynamic> json) => InvoiceLine(
        id: (json['id'] as num?)?.toInt() ?? 0,
        invoiceNumber: json['invoiceNumber'] as String? ?? '',
        totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
        balanceAmount: (json['balanceAmount'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? '',
        overdue: json['overdue'] as bool? ?? false,
        clientName: json['clientName'] as String?,
        dueDate: json['dueDate'] as String?,
      );
}

class Expense {
  const Expense({
    required this.id,
    required this.expenseNumber,
    required this.description,
    required this.amount,
    required this.expenseDate,
    required this.status,
    required this.createdAt,
    this.title,
    this.vendorName,
    this.category,
    this.expenseAccountId,
    this.expenseAccountName,
    this.receiptUrl,
    this.submittedByName,
    this.approvedByName,
    this.approvalNotes,
    this.submittedAt,
    this.notes,
    this.currency,
    this.reimbursedDate,
    this.reimbursementMethod,
    this.referenceNumber,
  });

  final int id;
  final String expenseNumber;
  final String description;
  final double amount;
  final String expenseDate;
  final String status;
  final String createdAt;
  final String? title;
  final String? vendorName;
  final String? category;
  /// The chart-of-accounts row this expense posts to when it is paid. The id
  /// matters as much as the name: an edit that omitted it would detach the
  /// expense from its account, because the update assigns the account without
  /// a null check.
  final int? expenseAccountId;

  final String? expenseAccountName;
  final String? receiptUrl;
  final String? submittedByName;
  final String? approvedByName;
  final String? approvalNotes;
  final String? submittedAt;
  final String? notes;
  final String? currency;
  final String? reimbursedDate;
  final String? reimbursementMethod;
  final String? referenceNumber;

  bool get isPending => status == ExpenseStatus.pending;
  bool get isApproved => status == ExpenseStatus.approved;
  bool get isPaid => status == ExpenseStatus.paid;

  /// Approved but not yet reimbursed — the state someone is waiting on money in.
  bool get awaitingReimbursement => isApproved && reimbursedDate == null;

  bool get hasReceipt => receiptUrl != null && receiptUrl!.trim().isNotEmpty;

  /// What to show as the row's heading. `title` is the tidy one-liner the AI
  /// composer writes; `description` is what a person typed.
  String get headline {
    final t = title?.trim();
    return (t != null && t.isNotEmpty) ? t : description;
  }

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: (json['id'] as num?)?.toInt() ?? 0,
        expenseNumber: json['expenseNumber'] as String? ?? '',
        description: json['description'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        expenseDate: json['expenseDate'] as String? ?? '',
        status: json['status'] as String? ?? ExpenseStatus.pending,
        createdAt: json['createdAt'] as String? ?? '',
        title: json['title'] as String?,
        vendorName: json['vendorName'] as String?,
        category: json['category'] as String?,
        expenseAccountId: (json['expenseAccountId'] as num?)?.toInt(),
        expenseAccountName: json['expenseAccountName'] as String?,
        receiptUrl: json['receiptUrl'] as String?,
        submittedByName: json['submittedByName'] as String?,
        approvedByName: json['approvedByName'] as String?,
        approvalNotes: json['approvalNotes'] as String?,
        submittedAt: json['submittedAt'] as String?,
        notes: json['notes'] as String?,
        currency: json['currency'] as String?,
        reimbursedDate: json['reimbursedDate'] as String?,
        reimbursementMethod: json['reimbursementMethod'] as String?,
        referenceNumber: json['referenceNumber'] as String?,
      );
}

/// POST /company/finance/expenses
class CreateExpenseRequest {
  const CreateExpenseRequest({
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.title,
    this.vendorName,
    this.category,
    this.notes,
    this.receiptUrl,
  });

  final String description;
  final double amount;

  /// `yyyy-MM-dd`.
  final String expenseDate;

  final String? title;
  final String? vendorName;
  final String? category;
  final String? notes;

  /// Set from `ApiClient.uploadDocument`'s response — the receipt itself is
  /// uploaded first, and only the URL it comes back with travels with the
  /// claim.
  final String? receiptUrl;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'description': description.trim(),
      'amount': amount,
      'expenseDate': expenseDate,
      if (clean(title) != null) 'title': clean(title),
      if (clean(vendorName) != null) 'vendorName': clean(vendorName),
      if (clean(category) != null) 'category': clean(category),
      if (clean(notes) != null) 'notes': clean(notes),
      if (clean(receiptUrl) != null) 'receiptUrl': clean(receiptUrl),
    };
  }
}

class Wallet {
  const Wallet({
    required this.id,
    required this.balance,
    required this.creditBalance,
    required this.totalAvailable,
    required this.currency,
  });

  final int id;
  final double balance;

  /// Promotional or refunded credit, spendable but not withdrawable.
  final double creditBalance;

  /// Cash plus credit. Server-computed, so the two cannot disagree.
  final double totalAvailable;

  final String currency;

  bool get hasCredit => creditBalance > 0;

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        id: (json['id'] as num?)?.toInt() ?? 0,
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        creditBalance: (json['creditBalance'] as num?)?.toDouble() ?? 0,
        totalAvailable: (json['totalAvailable'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? '',
      );
}

/// The only wallet transaction type that takes money out.
const walletDebitType = 'DEBIT';

/// Every type the backend's `credit()` path records.
///
/// `WalletServiceImpl` has exactly one debit path and one credit path; these
/// four are everything the credit path can write. Pinned by a test, so a
/// fifth added upstream fails loudly here instead of quietly rendering as a
/// withdrawal.
const walletCreditTypes = {
  'CREDIT',
  'CREDIT_APPLIED',
  'REFUND_CREDIT',
  'REFERRAL_REWARD',
};

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.transactedAt,
    this.reference,
    this.notes,
  });

  final int id;
  final String type;
  final double amount;
  final double balanceAfter;
  final String transactedAt;
  final String? reference;
  final String? notes;

  /// Whether this put money in or took it out.
  ///
  /// Decided from the type rather than the sign of [amount]: the backend
  /// stores amounts as positive magnitudes on both sides, so reading the sign
  /// would show every debit as a credit.
  /// The credits are listed rather than inferred from "not DEBIT", so a type
  /// nobody has seen before shows as money out — the smaller error, and the
  /// rule this has always followed.
  ///
  /// What was wrong was the list itself. It was invented: TOP_UP, DEPOSIT,
  /// BONUS and ADJUSTMENT_CREDIT are not types the backend has, and three of
  /// the four it does have were missing — so an applied credit, a refund and
  /// a referral reward each drew a red arrow pointing out of the wallet.
  /// Angular has had the right five all along.
  bool get isCredit => walletCreditTypes.contains(type);

  factory WalletTransaction.fromJson(Map<String, dynamic> json) =>
      WalletTransaction(
        id: (json['id'] as num?)?.toInt() ?? 0,
        type: json['type'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        balanceAfter: (json['balanceAfter'] as num?)?.toDouble() ?? 0,
        transactedAt: json['transactedAt'] as String? ?? '',
        reference: json['reference'] as String?,
        notes: json['notes'] as String?,
      );
}

/// How long a client has to pay.
const paymentTermsOptions = <String>[
  'DUE_ON_RECEIPT',
  'NET_15',
  'NET_30',
  'NET_45',
  'NET_60',
  'NET_90',
];

/// How a payment arrived. Money coming *in*, so every rail is valid.
const paymentMethods = <String>[
  'BKASH',
  'NAGAD',
  'ROCKET',
  'SSLCOMMERZ',
  'BANK_TRANSFER',
  'CASH',
  'WALLET',
  'CHEQUE',
];

/// A payment method as a person writes it.
///
/// `Fmt.label` title-cases each word, which is right for BANK_TRANSFER and
/// wrong for the brands: it renders bKash as "Bkash" and SSLCommerz as
/// "Sslcommerz". These are proper nouns with their own capitalisation, and
/// three of them are the rails most of this app's payments actually run on.
///
/// Angular prints the raw enum through titlecase and has the same flaw; this
/// is not a difference between the two clients, just the better rendering.
String paymentMethodLabel(String? method) => switch (method) {
      'BKASH' => 'bKash',
      'NAGAD' => 'Nagad',
      'ROCKET' => 'Rocket',
      'SSLCOMMERZ' => 'SSLCommerz',
      null => Fmt.dash,
      _ => Fmt.label(method),
    };

/// How a salary went *out*, which is a smaller set.
///
/// `PaymentMethod` is shared across invoices, expenses and payroll, so it
/// carries collection rails that cannot pay anybody. SSLCommerz moves money
/// to the company from a payer's card — it has no payout API, so recording a
/// salary as paid by it describes something that cannot have happened. WALLET
/// is a company-level balance with no per-employee counterparty.
///
/// `PayrollServiceImpl.guardPayoutMethod` rejects both with a 400, and the
/// run-level pay loops over payslips calling the same guarded method — so
/// offering them here does not merely fail, it can fail part-way through a
/// run. Both payroll sheets used to get this wrong in opposite directions:
/// one offered all eight, the other only three, hiding the mobile-money
/// rails most Bangladeshi payrolls actually use.
///
/// The order matches the backend's own error message, and Angular's
/// `PAYROLL_PAYMENT_METHODS`.
const payrollPaymentMethods = <String>[
  'BANK_TRANSFER',
  'BKASH',
  'NAGAD',
  'ROCKET',
  'CHEQUE',
  'CASH',
];

/// POST and PATCH /company/finance/invoices
///
/// One class for both, because the backend uses one DTO for both — and that
/// is the whole difficulty here. `PATCH` is `@Valid` against the *create*
/// shape, so an edit has to satisfy every rule a create does: a client, both
/// dates, and `@NotEmpty` items. Nothing about it is a patch.
///
/// On top of that, `update` assigns `invoiceDate`, `dueDate`, `taxAmount`,
/// `taxRatePercent`, `paymentTerms`, `description` and `notes`
/// **unconditionally**. Between the two rules, the only safe way to edit an
/// invoice is to send the whole thing back — which is what
/// [InvoiceRequest.from] exists to make easy.
///
/// Only a DRAFT invoice can be updated at all.
class InvoiceRequest {
  const InvoiceRequest({
    required this.clientId,
    required this.invoiceDate,
    required this.dueDate,
    required this.items,
    this.taxAmount,
    this.taxRatePercent,
    this.discountAmount,
    this.paymentTerms,
    this.description,
    this.notes,
  });

  final int clientId;
  final String invoiceDate;
  final String dueDate;

  /// `@NotEmpty`. An invoice with no lines is refused on create *and* update.
  final List<InvoiceItem> items;

  final double? taxAmount;
  final double? taxRatePercent;
  final double? discountAmount;
  final String? paymentTerms;
  final String? description;
  final String? notes;

  /// Seeds an edit from the invoice as it stands, so the fields the form does
  /// not show are still sent back rather than blanked.
  factory InvoiceRequest.from(Invoice invoice) => InvoiceRequest(
        clientId: invoice.clientId ?? 0,
        invoiceDate: invoice.invoiceDate ?? '',
        dueDate: invoice.dueDate ?? '',
        items: invoice.items,
        taxAmount: invoice.taxAmount,
        taxRatePercent: invoice.taxRatePercent,
        discountAmount: invoice.discountAmount,
        paymentTerms: invoice.paymentTerms,
        description: invoice.description,
        notes: invoice.notes,
      );

  InvoiceRequest copyWith({
    String? invoiceDate,
    String? dueDate,
    List<InvoiceItem>? items,
    double? taxRatePercent,
    double? discountAmount,
    String? paymentTerms,
    String? description,
    String? notes,
  }) =>
      InvoiceRequest(
        clientId: clientId,
        invoiceDate: invoiceDate ?? this.invoiceDate,
        dueDate: dueDate ?? this.dueDate,
        items: items ?? this.items,
        taxAmount: taxAmount,
        taxRatePercent: taxRatePercent ?? this.taxRatePercent,
        discountAmount: discountAmount ?? this.discountAmount,
        paymentTerms: paymentTerms ?? this.paymentTerms,
        description: description ?? this.description,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'clientId': clientId,
      'invoiceDate': invoiceDate,
      'dueDate': dueDate,
      'items': [for (final item in items) item.toJson()],
      // Unconditional, all of them: see the class comment.
      'taxAmount': taxAmount ?? 0,
      'taxRatePercent': taxRatePercent,
      'discountAmount': discountAmount ?? 0,
      'paymentTerms': paymentTerms,
      'description': clean(description),
      'notes': clean(notes),
    };
  }
}

/// POST /company/finance/payment-receipts
///
/// Records money received. Client, amount, date and method are all `@NotNull`;
/// linking it to an invoice is optional, and that is how an on-account payment
/// is expressed.
class CreatePaymentReceiptRequest {
  const CreatePaymentReceiptRequest({
    required this.clientId,
    required this.amount,
    required this.paymentDate,
    required this.paymentMethod,
    this.invoiceId,
    this.transactionReference,
    this.notes,
  });

  final int clientId;
  final double amount;
  final String paymentDate;
  final String paymentMethod;
  final int? invoiceId;
  final String? transactionReference;
  final String? notes;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'clientId': clientId,
      'amount': amount,
      'paymentDate': paymentDate,
      'paymentMethod': paymentMethod,
      if (invoiceId != null) 'invoiceId': invoiceId,
      if (clean(transactionReference) != null)
        'transactionReference': clean(transactionReference),
      if (clean(notes) != null) 'notes': clean(notes),
    };
  }
}

/// POST /company/finance/expenses/ai-compose
///
/// Turns rough notes into a title and description for a claim. Whatever the
/// claimant has already typed — vendor, amount, category — goes along as
/// context, so the draft matches the rest of the form rather than contradicting
/// it. Only `roughNotes` is required.
class ExpenseComposeRequest {
  const ExpenseComposeRequest({
    required this.roughNotes,
    this.vendorName,
    this.amount,
    this.category,
  });

  final String roughNotes;
  final String? vendorName;

  /// A string, not a number: the DTO takes it as free text because it is
  /// context for a prompt rather than a figure to compute with.
  final String? amount;

  final String? category;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'roughNotes': roughNotes.trim(),
      if (clean(vendorName) != null) 'vendorName': clean(vendorName),
      if (clean(amount) != null) 'amount': clean(amount),
      if (clean(category) != null) 'category': clean(category),
    };
  }
}

/// What the assistant drafted. Suggestions only — the claimant edits them
/// before anything is submitted, and nothing is saved until they do.
class ExpenseDraft {
  const ExpenseDraft({required this.title, required this.description});

  final String title;
  final String description;

  factory ExpenseDraft.fromJson(Map<String, dynamic> json) => ExpenseDraft(
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );
}


/// Changing an expense that has not been decided on yet.
///
/// A `PATCH` that mostly is not one. `ExpenseServiceImpl.update` guards only
/// title, currency and the vendor name; description, amount, category, the
/// expense account, the date, the receipt and the notes are all assigned
/// straight from the request. Omitting one clears it.
///
/// So this always sends the lot, and [UpdateExpenseRequest.from] seeds it from
/// the expense as it stands — including the account id, which no form here
/// shows. Two other things the backend enforces and this mirrors: only a
/// PENDING expense may be changed at all, and somebody without EXPENSE_UPDATE
/// may only change their own.
class UpdateExpenseRequest {
  const UpdateExpenseRequest({
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.title,
    this.currency,
    this.vendorName,
    this.category,
    this.expenseAccountId,
    this.receiptUrl,
    this.notes,
  });

  final String description;
  final double amount;
  final String expenseDate;
  final String? title;
  final String? currency;
  final String? vendorName;
  final String? category;
  final int? expenseAccountId;
  final String? receiptUrl;
  final String? notes;

  factory UpdateExpenseRequest.from(Expense expense) => UpdateExpenseRequest(
        description: expense.description,
        amount: expense.amount,
        expenseDate: expense.expenseDate,
        title: expense.title,
        currency: expense.currency,
        vendorName: expense.vendorName,
        category: expense.category,
        expenseAccountId: expense.expenseAccountId,
        receiptUrl: expense.receiptUrl,
        notes: expense.notes,
      );

  UpdateExpenseRequest copyWith({
    String? description,
    double? amount,
    String? expenseDate,
    String? title,
    String? vendorName,
    String? category,
    String? notes,
  }) =>
      UpdateExpenseRequest(
        description: description ?? this.description,
        amount: amount ?? this.amount,
        expenseDate: expenseDate ?? this.expenseDate,
        title: title ?? this.title,
        currency: currency,
        vendorName: vendorName ?? this.vendorName,
        category: category ?? this.category,
        expenseAccountId: expenseAccountId,
        receiptUrl: receiptUrl,
        notes: notes ?? this.notes,
      );

  /// Every key, nulls included — an absent one is not "leave it alone" here.
  Map<String, dynamic> toJson() => {
        'description': description.trim(),
        'amount': amount,
        'expenseDate': expenseDate,
        'title': title,
        'currency': currency,
        'vendorName': vendorName,
        'category': category,
        'expenseAccountId': expenseAccountId,
        'receiptUrl': receiptUrl,
        'notes': notes,
      };
}
