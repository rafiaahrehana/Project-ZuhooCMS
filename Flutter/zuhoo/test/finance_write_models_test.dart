import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/accounting/reconciliation_models.dart';
import 'package:zuhoo/features/finance/finance_models.dart';

void main() {
  group('UpdateExpenseRequest', () {
    final expense = Expense.fromJson(const {
      'id': 3,
      'expenseNumber': 'EXP-3',
      'description': 'Taxi to the airport',
      'amount': 88.4,
      'expenseDate': '2026-02-01',
      'status': 'PENDING',
      'createdAt': '2026-02-01T09:00:00',
      'title': 'Travel',
      'currency': 'SAR',
      'vendorName': 'Careem',
      'category': 'TRAVEL',
      'expenseAccountId': 41,
      'expenseAccountName': 'Travel expenses',
      'receiptUrl': 'https://files/receipt.png',
      'notes': 'Client meeting',
    });

    test('carries across the fields no form shows', () {
      final json = UpdateExpenseRequest.from(expense)
          .copyWith(amount: 90)
          .toJson();

      expect(json['amount'], 90);
      // The three that would be wiped if they were left out: the update
      // assigns the account, the receipt and the notes without a null check.
      expect(json['expenseAccountId'], 41);
      expect(json['receiptUrl'], 'https://files/receipt.png');
      expect(json['notes'], 'Client meeting');
      expect(json['currency'], 'SAR');
    });

    test('sends every key, nulls included', () {
      const request = UpdateExpenseRequest(
        description: 'A thing',
        amount: 10,
        expenseDate: '2026-01-01',
      );

      expect(request.toJson().keys.toSet(), {
        'description',
        'amount',
        'expenseDate',
        'title',
        'currency',
        'vendorName',
        'category',
        'expenseAccountId',
        'receiptUrl',
        'notes',
      });
      expect(request.toJson()['expenseAccountId'], isNull);
    });

    test('the expense model reads the account id, not only its name', () {
      // Without the id there would be nothing to send back, and every edit
      // would silently detach the expense from its account.
      expect(expense.expenseAccountId, 41);
    });
  });

  group('BankReconciliation', () {
    test('a difference of a rounding error still counts as squared', () {
      final squared = BankReconciliation.fromJson(const {
        'id': 1,
        'difference': 0.001,
      });
      expect(squared.balances, isTrue);

      final out = BankReconciliation.fromJson(const {
        'id': 1,
        'difference': -0.02,
      });
      expect(out.balances, isFalse);
    });

    test('a sparse response reads as zeroes', () {
      final reconciliation = BankReconciliation.fromJson(const {'id': 2});
      expect(reconciliation.glBalance, 0);
      expect(reconciliation.reconciled, isFalse);
      expect(reconciliation.balances, isTrue);
    });
  });

  group('StatementImportResult', () {
    test('unmatched lines and the updated reconciliation both come through',
        () {
      final result = StatementImportResult.fromJson(const {
        'totalLines': 12,
        'matched': 9,
        'unmatchedCount': 3,
        'unmatchedLines': [
          {
            'date': '2026-02-03',
            'description': 'CARD 4471',
            'amount': -20.0,
            'reason': 'No ledger entry within tolerance',
          },
        ],
        'reconciliation': {'id': 5, 'difference': 60.0},
      });

      expect(result.matched, 9);
      expect(result.unmatchedLines.single.reason, isNotNull);
      expect(result.reconciliation?.id, 5);
      expect(result.reconciliation?.balances, isFalse);
    });

    test('a response with no reconciliation attached is not a crash', () {
      final result = StatementImportResult.fromJson(const {'totalLines': 0});
      expect(result.reconciliation, isNull);
      expect(result.unmatchedLines, isEmpty);
    });
  });
}
