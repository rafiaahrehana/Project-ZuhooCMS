import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/accounting/accounting_models.dart';
import 'package:zuhoo/features/assets_periods/assets_periods_models.dart';
import 'package:zuhoo/features/payables/payables_models.dart';
import 'package:zuhoo/features/reports/report_models.dart';

/// The books are the one place a wrong request costs real money, so what is
/// pinned here is the validation the app does *before* asking: whether an entry
/// balances, whether an account may be posted to, and which actions are still
/// open at each stage.
void main() {
  group('AccountRequest', () {
    const account = Account(
      id: 1,
      accountCode: '1010',
      accountName: 'Cash at bank',
      type: 'ASSET',
      isHeaderAccount: false,
      isBankAccount: true,
      allowDirectPosting: true,
      active: true,
    );

    test('sends the two pinned JSON keys, not the stripped ones', () {
      // The backend forces @JsonProperty("isHeaderAccount") because Jackson
      // would otherwise send "headerAccount" from Lombok's getter.
      final json = AccountRequest.from(account).toJson();
      expect(json.containsKey('isHeaderAccount'), isTrue);
      expect(json.containsKey('isBankAccount'), isTrue);
      expect(json.containsKey('headerAccount'), isFalse);
      expect(json.containsKey('bankAccount'), isFalse);
    });

    test('always sends all four flags', () {
      // allowDirectPosting and active default to *true* on the DTO, so an
      // omitted key would quietly switch an account back on.
      final json = AccountRequest.from(account).toJson();
      expect(json['allowDirectPosting'], isTrue);
      expect(json['active'], isTrue);
      expect(json['isBankAccount'], isTrue);
      expect(json['isHeaderAccount'], isFalse);
    });

    test('leaves the opening balance out unless there is one', () {
      expect(
        AccountRequest.from(account).toJson().containsKey('openingBalance'),
        isFalse,
      );
    });
  });

  group('Account', () {
    Account account({
      bool header = false,
      bool direct = true,
      bool active = true,
    }) =>
        Account(
          id: 1,
          accountCode: '1010',
          accountName: 'x',
          type: 'ASSET',
          isHeaderAccount: header,
          isBankAccount: false,
          allowDirectPosting: direct,
          active: active,
        );

    test('a heading cannot be posted to whatever else it says', () {
      expect(account().canPostTo, isTrue);
      expect(account(header: true).canPostTo, isFalse);
      expect(account(direct: false).canPostTo, isFalse);
      expect(account(active: false).canPostTo, isFalse);
    });

    test('reads either spelling of the two pinned flags', () {
      expect(
        Account.fromJson(const {'id': 1, 'headerAccount': true})
            .isHeaderAccount,
        isTrue,
      );
      expect(
        Account.fromJson(const {'id': 1, 'isHeaderAccount': true})
            .isHeaderAccount,
        isTrue,
      );
    });

    test('groups types the way a balance sheet reads', () {
      expect(accountGroup('CONTRA_ASSET'), 'Assets');
      expect(accountGroup('CONTRA_REVENUE'), 'Revenue');
      expect(accountGroup('EQUITY'), 'Equity');
    });
  });

  group('JournalEntryRequest', () {
    JournalEntryRequest entry(List<JournalLineRequest> lines) =>
        JournalEntryRequest(entryDate: '2026-08-31', lines: lines);

    test('needs at least two lines', () {
      expect(
        entry([const JournalLineRequest(accountId: 1, debitAmount: 100)])
            .problem,
        'A journal entry needs at least two lines.',
      );
    });

    test('refuses a line that is both a debit and a credit', () {
      expect(
        entry([
          const JournalLineRequest(
            accountId: 1,
            debitAmount: 100,
            creditAmount: 100,
          ),
          const JournalLineRequest(accountId: 2, creditAmount: 100),
        ]).problem,
        'A line can be a debit or a credit, not both.',
      );
    });

    test('refuses a line that is neither', () {
      expect(
        entry([
          const JournalLineRequest(accountId: 1),
          const JournalLineRequest(accountId: 2, creditAmount: 100),
        ]).problem,
        'Every line needs a debit or a credit.',
      );
    });

    test('refuses a line with no account', () {
      expect(
        entry([
          const JournalLineRequest(debitAmount: 100),
          const JournalLineRequest(accountId: 2, creditAmount: 100),
        ]).problem,
        'Every line needs an account.',
      );
    });

    test('says by how much an unbalanced entry is out', () {
      final problem = entry([
        const JournalLineRequest(accountId: 1, debitAmount: 100),
        const JournalLineRequest(accountId: 2, creditAmount: 90),
      ]).problem;
      expect(problem, contains('10.00'));
    });

    test('accepts a balanced entry of three legs', () {
      final request = entry([
        const JournalLineRequest(accountId: 1, debitAmount: 100),
        const JournalLineRequest(accountId: 2, creditAmount: 60),
        const JournalLineRequest(accountId: 3, creditAmount: 40),
      ]);
      expect(request.problem, isNull);
      expect(request.balances, isTrue);
    });

    test('tolerates floating point rather than reporting a false difference', () {
      // 0.1 + 0.2 is not 0.3 in binary; the comparison is to the paisa.
      final request = entry([
        const JournalLineRequest(accountId: 1, debitAmount: 0.1),
        const JournalLineRequest(accountId: 2, debitAmount: 0.2),
        const JournalLineRequest(accountId: 3, creditAmount: 0.3),
      ]);
      expect(request.balances, isTrue);
      expect(request.problem, isNull);
    });

    test('sends both sides of every line, one of them zero', () {
      final json = entry([
        const JournalLineRequest(accountId: 1, debitAmount: 100),
        const JournalLineRequest(accountId: 2, creditAmount: 100),
      ]).toJson();
      final lines = json['lines']! as List;
      expect((lines.first as Map)['debitAmount'], 100);
      expect((lines.first as Map)['creditAmount'], 0);
    });
  });

  group('JournalEntry', () {
    JournalEntry entry({
      bool approved = false,
      bool posted = false,
      bool reversed = false,
    }) =>
        JournalEntry(
          id: 1,
          journalEntryNumber: 'JE-001',
          approved: approved,
          posted: posted,
          reversed: reversed,
          amount: 100,
        );

    test('names where it is in one word', () {
      expect(entry().status, 'DRAFT');
      expect(entry(approved: true).status, 'APPROVED');
      expect(entry(approved: true, posted: true).status, 'POSTED');
      expect(
        entry(approved: true, posted: true, reversed: true).status,
        'REVERSED',
      );
    });

    test('posting needs approval first, reversing needs posting', () {
      expect(entry().canPost, isFalse);
      expect(entry(approved: true).canPost, isTrue);
      expect(entry(approved: true).canReverse, isFalse);
      expect(entry(approved: true, posted: true).canReverse, isTrue);
    });

    test('a posted entry can no longer be deleted', () {
      // The ledger has moved; only a reversal undoes it.
      expect(entry(approved: true).canDelete, isTrue);
      expect(entry(approved: true, posted: true).canDelete, isFalse);
    });

    test('an already-reversed entry cannot be reversed again', () {
      expect(
        entry(approved: true, posted: true, reversed: true).canReverse,
        isFalse,
      );
    });
  });

  group('VendorBill', () {
    VendorBill bill({
      String status = BillStatus.draft,
      double paid = 0,
      double balance = 1000,
    }) =>
        VendorBill(
          id: 1,
          billNumber: 'B-001',
          status: status,
          subtotal: 1000,
          taxAmount: 0,
          totalAmount: 1000,
          paidAmount: paid,
          balanceAmount: balance,
        );

    test('only a draft can be approved', () {
      expect(bill().canApprove, isTrue);
      expect(bill(status: BillStatus.approved).canApprove, isFalse);
    });

    test('a partly-paid bill can still take a payment', () {
      expect(bill(status: BillStatus.approved).canPay, isTrue);
      expect(
        bill(status: BillStatus.partiallyPaid, paid: 400, balance: 600).canPay,
        isTrue,
      );
      expect(bill(status: BillStatus.overdue).canPay, isTrue);
      expect(bill(status: BillStatus.draft).canPay, isFalse);
      // Nothing left to pay.
      expect(bill(status: BillStatus.approved, balance: 0).canPay, isFalse);
    });

    test('cancelling closes once anything has been paid', () {
      expect(bill().canCancel, isTrue);
      expect(bill(paid: 1, balance: 999).canCancel, isFalse);
      expect(bill(status: BillStatus.cancelled).canCancel, isFalse);
    });
  });

  group('AgeingLine', () {
    test('reads a receivables line and a payables line the same way', () {
      final receivable = AgeingLine.fromJson(const {
        'invoiceId': 3,
        'invoiceNumber': 'INV-3',
        'clientName': 'Acme',
        'balanceAmount': 500,
        'daysOverdue': 12,
      });
      final payable = AgeingLine.fromJson(const {
        'billId': 4,
        'billNumber': 'B-4',
        'vendorName': 'Supplier',
        'balanceAmount': 500,
        'daysOverdue': -3,
      });

      expect(receivable.documentId, 3);
      expect(receivable.reference, 'INV-3');
      expect(receivable.counterparty, 'Acme');
      expect(receivable.isOverdue, isTrue);

      expect(payable.documentId, 4);
      expect(payable.reference, 'B-4');
      expect(payable.counterparty, 'Supplier');
      // Negative days means not yet due.
      expect(payable.isOverdue, isFalse);
    });
  });

  group('reports', () {
    test('a margin on no revenue is undefined, not zero', () {
      const nothing =
          ProfitLoss(totalRevenue: 0, totalExpense: 500, netProfit: -500);
      expect(nothing.margin, isNull);
      expect(nothing.isProfit, isFalse);

      const earning =
          ProfitLoss(totalRevenue: 1000, totalExpense: 750, netProfit: 250);
      expect(earning.margin, 0.25);
    });

    test('a trial balance is compared to the paisa', () {
      const off = TrialBalance(totalDebit: 1000, totalCredit: 999.999);
      expect(off.balances, isTrue);
      const wrong = TrialBalance(totalDebit: 1000, totalCredit: 990);
      expect(wrong.balances, isFalse);
      expect(wrong.difference, 10);
    });

    test('ageing separates what is merely outstanding from what is late', () {
      const ageing = Ageing(
        current: 100,
        days1to30: 50,
        days31to60: 25,
        days61to90: 0,
        over90: 10,
        totalOutstanding: 185,
      );
      expect(ageing.overdue, 85);
      expect(ageing.buckets.length, 5);
      expect(ageing.buckets.first.label, 'Current');
    });
  });

  group('FiscalYear and FixedAsset', () {
    test('a year is only closeable once every period is', () {
      const partway = FiscalYear(
        fiscalYear: 2026,
        totalPeriods: 12,
        openPeriods: 3,
        closedPeriods: 9,
      );
      expect(partway.fullyClosed, isFalse);
      expect(partway.progress, 0.75);

      const done = FiscalYear(
        fiscalYear: 2026,
        totalPeriods: 12,
        openPeriods: 0,
        closedPeriods: 12,
      );
      expect(done.fullyClosed, isTrue);
    });

    test('a year with no periods is not "fully closed"', () {
      const empty = FiscalYear(
        fiscalYear: 2026,
        totalPeriods: 0,
        openPeriods: 0,
        closedPeriods: 0,
      );
      expect(empty.fullyClosed, isFalse);
      expect(empty.progress, isNull);
    });

    test('an asset stops counting down once disposed', () {
      const held = FixedAsset(
        id: 1,
        name: 'Van',
        cost: 12000,
        usefulLifeMonths: 60,
        status: AssetStatus.active,
        accumulatedDepreciation: 3000,
        bookValue: 9000,
        monthlyDepreciation: 200,
      );
      expect(held.depreciated, 0.25);
      expect(held.monthsRemaining, 45);
      expect(held.canDispose, isTrue);

      const gone = FixedAsset(
        id: 1,
        name: 'Van',
        cost: 12000,
        usefulLifeMonths: 60,
        status: AssetStatus.disposed,
        bookValue: 9000,
        monthlyDepreciation: 200,
      );
      expect(gone.monthsRemaining, isNull);
      expect(gone.canDispose, isFalse);
    });

    test('the scrap value is not depreciated away', () {
      const asset = FixedAsset(
        id: 1,
        name: 'Machine',
        cost: 10000,
        usefulLifeMonths: 50,
        status: AssetStatus.active,
        salvageValue: 2000,
        bookValue: 4000,
        monthlyDepreciation: 160,
      );
      // 4000 book less 2000 scrap, at 160 a month.
      expect(asset.monthsRemaining, 13);
    });

    test('a monthly figure is derived for the form to show', () {
      const request = FixedAssetRequest(
        name: 'Van',
        cost: 12000,
        usefulLifeMonths: 60,
        acquisitionDate: '2026-01-01',
        salvageValue: 0,
      );
      expect(request.monthlyDepreciation, 200);
    });
  });
}
