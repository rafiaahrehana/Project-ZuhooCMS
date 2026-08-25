import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/finance/finance_models.dart';
import 'package:zuhoo/features/portal/portal_models.dart'
    show Invoice, InvoiceItem;

/// Money is the one place where a display bug is indistinguishable from a
/// data bug to the person reading it. These pin the derivations that decide
/// what a figure *means* — a change that reads as growth, a charge that reads
/// as a top-up, a percentage that claims something is known when it is not.
void main() {
  FinanceOverview overview({
    double revenue = 0,
    double expenses = 0,
    double profit = 0,
    double outstanding = 0,
    double overdue = 0,
    double? revenueChange,
  }) =>
      FinanceOverview(
        month: 8,
        year: 2026,
        totalRevenue: revenue,
        totalExpenses: expenses,
        netProfit: profit,
        outstanding: outstanding,
        overdue: overdue,
        revenueChangePercent: revenueChange,
      );

  group('FinanceOverview', () {
    test('break-even counts as profitable, not a loss', () {
      expect(overview(profit: 0).isProfitable, isTrue);
      expect(overview(profit: 1).isProfitable, isTrue);
      expect(overview(profit: -1).isProfitable, isFalse);
    });

    test('overdue share is null when nothing is owed', () {
      // An empty bar would read as "all healthy" rather than "nothing is out".
      expect(overview().overdueShare, isNull);
      expect(overview(outstanding: 1000, overdue: 250).overdueShare, 0.25);
    });

    test('overdue share cannot exceed the whole', () {
      // Defensive: a stale overdue figure must not overflow the bar.
      expect(overview(outstanding: 100, overdue: 500).overdueShare, 1.0);
    });

    test('a null change stays null rather than becoming zero', () {
      // There is no earlier month to compare against on the first month with
      // data. Rendering 0% would claim the figure held steady.
      expect(overview().revenueChangePercent, isNull);
      expect(overview(revenueChange: 0).revenueChangePercent, 0);
    });

    test('parses the dashboard payload, including its invoice lines', () {
      final parsed = FinanceOverview.fromJson(const {
        'payMonth': 8,
        'payYear': 2026,
        'totalRevenue': 250000,
        'totalExpenses': 90000,
        'netProfit': 160000,
        'outstanding': 40000,
        'overdue': 10000,
        'revenueChangePercent': 12.5,
        'expenseChangePercent': null,
        'recentInvoices': [
          {
            'id': 3,
            'invoiceNumber': 'INV-0003',
            'totalAmount': 20000,
            'balanceAmount': 20000,
            'status': 'SENT',
            'overdue': true,
          },
        ],
      });

      expect(parsed.totalRevenue, 250000.0);
      expect(parsed.revenueChangePercent, 12.5);
      expect(parsed.expenseChangePercent, isNull);
      expect(parsed.recentInvoices, hasLength(1));
      expect(parsed.recentInvoices.first.overdue, isTrue);
      expect(parsed.overdueShare, 0.25);
    });

    test('survives a payload with nothing in it', () {
      final parsed = FinanceOverview.fromJson(const {});
      expect(parsed.totalRevenue, 0);
      expect(parsed.recentInvoices, isEmpty);
      expect(parsed.overdueShare, isNull);
    });
  });

  group('Expense', () {
    Expense expense({String status = ExpenseStatus.pending, String? reimbursed}) =>
        Expense(
          id: 1,
          expenseNumber: 'EXP-0001',
          description: 'Taxi to the client site',
          amount: 850,
          expenseDate: '2026-08-02',
          status: status,
          createdAt: '2026-08-02T10:00:00',
          reimbursedDate: reimbursed,
        );

    test('awaiting reimbursement means approved but not yet paid out', () {
      expect(expense(status: ExpenseStatus.approved).awaitingReimbursement, isTrue);
      expect(
        expense(status: ExpenseStatus.approved, reimbursed: '2026-08-09')
            .awaitingReimbursement,
        isFalse,
      );
      expect(expense().awaitingReimbursement, isFalse,
          reason: 'still pending, so nobody owes anything yet');
      expect(expense(status: ExpenseStatus.rejected).awaitingReimbursement, isFalse);
    });

    test('the tidy title wins over the raw description when present', () {
      const raw = Expense(
        id: 1,
        expenseNumber: 'EXP-1',
        description: 'taxi ~850 to meet finance lead',
        amount: 850,
        expenseDate: '2026-08-02',
        status: ExpenseStatus.pending,
        createdAt: '2026-08-02T10:00:00',
        title: 'Taxi to client site',
      );
      expect(raw.headline, 'Taxi to client site');

      expect(expense().headline, 'Taxi to the client site');
    });

    test('an empty title falls back rather than showing nothing', () {
      const blank = Expense(
        id: 1,
        expenseNumber: 'EXP-1',
        description: 'Taxi',
        amount: 100,
        expenseDate: '2026-08-02',
        status: ExpenseStatus.pending,
        createdAt: '2026-08-02T10:00:00',
        title: '   ',
      );
      expect(blank.headline, 'Taxi');
    });

    test('a receipt url must be non-empty to count', () {
      expect(expense().hasReceipt, isFalse);
      expect(
        Expense.fromJson(const {'id': 1, 'receiptUrl': ''}).hasReceipt,
        isFalse,
      );
      expect(
        Expense.fromJson(const {'id': 1, 'receiptUrl': '/f/a.jpg'}).hasReceipt,
        isTrue,
      );
    });
  });

  group('CreateExpenseRequest', () {
    test('trims, and omits optionals that are blank', () {
      final json = const CreateExpenseRequest(
        description: '  Taxi  ',
        amount: 850.5,
        expenseDate: '2026-08-02',
        vendorName: '   ',
        category: '',
      ).toJson();

      expect(json['description'], 'Taxi');
      expect(json['amount'], 850.5);
      expect(json['expenseDate'], '2026-08-02');
      expect(json.containsKey('vendorName'), isFalse);
      expect(json.containsKey('category'), isFalse);
    });
  });

  group('WalletTransaction', () {
    WalletTransaction tx(String type) => WalletTransaction(
          id: 1,
          type: type,
          amount: 500,
          balanceAfter: 1500,
          transactedAt: '2026-08-02T10:00:00',
        );

    test('direction comes from the type, not the sign of the amount', () {
      // The backend stores positive magnitudes on both sides. Reading the sign
      // would paint every charge as a top-up — money appearing out of nowhere.
      expect(tx('TOP_UP').isCredit, isTrue);
      expect(tx('REFUND').isCredit, isTrue);
      expect(tx('CREDIT').isCredit, isTrue);

      expect(tx('PAYMENT').isCredit, isFalse);
      expect(tx('CHARGE').isCredit, isFalse);
      expect(tx('WITHDRAWAL').isCredit, isFalse);
    });

    test('an unrecognised type is treated as a debit', () {
      // The safe direction: showing an unknown movement as money out is a
      // smaller error than showing it as money in.
      expect(tx('SOME_NEW_TYPE').isCredit, isFalse);
    });
  });

  group('Wallet', () {
    test('credit is only flagged when there is some', () {
      const none = Wallet(
        id: 1,
        balance: 1000,
        creditBalance: 0,
        totalAvailable: 1000,
        currency: 'BDT',
      );
      expect(none.hasCredit, isFalse);

      const some = Wallet(
        id: 1,
        balance: 1000,
        creditBalance: 250,
        totalAvailable: 1250,
        currency: 'BDT',
      );
      expect(some.hasCredit, isTrue);
    });
  });

  group('InvoiceRequest', () {
    const line = InvoiceItem(
      description: 'Consultancy',
      quantity: 2,
      unitPrice: 500,
    );

    test('always sends the fields update assigns unconditionally', () {
      final json = const InvoiceRequest(
        clientId: 7,
        invoiceDate: '2026-08-01',
        dueDate: '2026-08-31',
        items: [line],
      ).toJson();

      // Omitting any of these does not leave them alone — it clears them.
      for (final key in const [
        'taxAmount',
        'taxRatePercent',
        'discountAmount',
        'paymentTerms',
        'description',
        'notes',
      ]) {
        expect(json.containsKey(key), isTrue, reason: '$key must be sent');
      }
    });

    test('defaults the two money fields that must not arrive null', () {
      final json = const InvoiceRequest(
        clientId: 7,
        invoiceDate: '2026-08-01',
        dueDate: '2026-08-31',
        items: [line],
      ).toJson();

      expect(json['taxAmount'], 0);
      expect(json['discountAmount'], 0);
    });

    test('always carries the lines, because PATCH is @Valid like POST', () {
      final json = const InvoiceRequest(
        clientId: 7,
        invoiceDate: '2026-08-01',
        dueDate: '2026-08-31',
        items: [line],
      ).toJson();

      final items = json['items'] as List<dynamic>;
      expect(items, hasLength(1));
      expect((items.first as Map)['description'], 'Consultancy');
      expect((items.first as Map)['quantity'], 2);
    });

    test('seeds an edit from the invoice so nothing shown is lost', () {
      const invoice = Invoice(
        id: 3,
        invoiceNumber: 'INV-003',
        status: 'DRAFT',
        subtotal: 1000,
        taxAmount: 150,
        totalAmount: 1150,
        paidAmount: 0,
        balanceAmount: 1150,
        clientId: 7,
        taxRatePercent: 15,
        items: [line],
        invoiceDate: '2026-08-01',
        dueDate: '2026-08-31',
        notes: 'Net thirty',
      );

      final json = InvoiceRequest.from(invoice).toJson();

      expect(json['clientId'], 7);
      expect(json['taxRatePercent'], 15);
      expect(json['notes'], 'Net thirty');
      expect(json['items'], hasLength(1));
    });

    test('a line total is derived when the server has not sent one', () {
      expect(line.amount, 1000);
      expect(
        const InvoiceItem(description: 'x', quantity: 1, unitPrice: 9, lineTotal: 42)
            .amount,
        42,
      );
    });
  });

  group('CreatePaymentReceiptRequest', () {
    test('omits the invoice when the payment is on account', () {
      final json = const CreatePaymentReceiptRequest(
        clientId: 7,
        amount: 500,
        paymentDate: '2026-08-20',
        paymentMethod: 'BANK_TRANSFER',
      ).toJson();

      expect(json.containsKey('invoiceId'), isFalse);
      expect(json['paymentMethod'], 'BANK_TRANSFER');
    });
  });

  group('ExpenseComposeRequest', () {
    test('sends only the notes when nothing else is typed yet', () {
      final json =
          const ExpenseComposeRequest(roughNotes: '  cab to airport  ').toJson();

      expect(json['roughNotes'], 'cab to airport');
      expect(json.containsKey('vendorName'), isFalse);
      expect(json.containsKey('amount'), isFalse);
    });

    test('carries what is already on the form as context', () {
      final json = const ExpenseComposeRequest(
        roughNotes: 'cab to airport',
        vendorName: 'Uber',
        amount: '1200',
        category: 'Travel',
      ).toJson();

      expect(json['vendorName'], 'Uber');
      // A string, not a number: it is prompt context, not a figure.
      expect(json['amount'], '1200');
      expect(json['category'], 'Travel');
    });
  });
}
