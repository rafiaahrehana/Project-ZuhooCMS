package com.zuhoocms.modules.finance.chartofaccounts;

import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;

/** Finds or auto-creates the standard Chart of Accounts entries GL posting needs: companies are not seeded with a chart, so these appear on first use under fixed codes. */
@Component
@RequiredArgsConstructor
public class DefaultAccountResolver {

    private static final String CASH_CODE = "1000";
    private static final String CASH_NAME = "Cash and Bank";

    private static final String ACCOUNTS_RECEIVABLE_CODE = "1200";
    private static final String ACCOUNTS_RECEIVABLE_NAME = "Accounts Receivable";

    private static final String SALES_REVENUE_CODE = "4000";
    private static final String SALES_REVENUE_NAME = "Sales Revenue";

    private static final String TAX_PAYABLE_CODE = "2100";
    private static final String TAX_PAYABLE_NAME = "Tax Payable";

    private static final String OPERATING_EXPENSES_CODE = "5000";
    private static final String OPERATING_EXPENSES_NAME = "Operating Expenses";

    private static final String SALARY_EXPENSE_CODE = "5100";
    private static final String SALARY_EXPENSE_NAME = "Salaries and Wages";

    private static final String PAYROLL_PAYABLE_CODE = "2200";
    private static final String PAYROLL_PAYABLE_NAME = "Payroll Payable";

    private static final String RETAINED_EARNINGS_CODE = "3900";
    private static final String RETAINED_EARNINGS_NAME = "Retained Earnings";

    private static final String ACCOUNTS_PAYABLE_CODE = "2000";
    private static final String ACCOUNTS_PAYABLE_NAME = "Accounts Payable";

    private static final String FIXED_ASSETS_CODE = "1400";
    private static final String FIXED_ASSETS_NAME = "Fixed Assets";

    private static final String ACCUMULATED_DEPRECIATION_CODE = "1500";
    private static final String ACCUMULATED_DEPRECIATION_NAME = "Accumulated Depreciation";

    private static final String DEPRECIATION_EXPENSE_CODE = "5200";
    private static final String DEPRECIATION_EXPENSE_NAME = "Depreciation Expense";

    private static final String OPENING_BALANCE_EQUITY_CODE = "3800";
    private static final String OPENING_BALANCE_EQUITY_NAME = "Opening Balance Equity";

    private final ChartOfAccountRepository coaRepository;

    public ChartOfAccount cash(Long companyId) {
        ChartOfAccount account = resolve(companyId, CASH_CODE, CASH_NAME, AccountType.ASSET);
        // Keep the system cash account flagged reconcilable even if it predates isBankAccount.
        if (!account.isBankAccount()) {
            account.setBankAccount(true);
            account = coaRepository.save(account);
        }
        return account;
    }

    public ChartOfAccount accountsReceivable(Long companyId) {
        return resolve(companyId, ACCOUNTS_RECEIVABLE_CODE, ACCOUNTS_RECEIVABLE_NAME, AccountType.ASSET);
    }

    public ChartOfAccount salesRevenue(Long companyId) {
        return resolve(companyId, SALES_REVENUE_CODE, SALES_REVENUE_NAME, AccountType.REVENUE);
    }

    public ChartOfAccount taxPayable(Long companyId) {
        return resolve(companyId, TAX_PAYABLE_CODE, TAX_PAYABLE_NAME, AccountType.LIABILITY);
    }

    public ChartOfAccount operatingExpenses(Long companyId) {
        return resolve(companyId, OPERATING_EXPENSES_CODE, OPERATING_EXPENSES_NAME, AccountType.EXPENSE);
    }

    public ChartOfAccount salaryExpense(Long companyId) {
        return resolve(companyId, SALARY_EXPENSE_CODE, SALARY_EXPENSE_NAME, AccountType.EXPENSE);
    }

    /** Withheld tax + other payroll deductions the company still owes out (not yet remitted). */
    public ChartOfAccount payrollPayable(Long companyId) {
        return resolve(companyId, PAYROLL_PAYABLE_CODE, PAYROLL_PAYABLE_NAME, AccountType.LIABILITY);
    }

    /** Cumulative net income from all closed fiscal years - see AccountingPeriodServiceImpl.closeFiscalYear. */
    public ChartOfAccount retainedEarnings(Long companyId) {
        return resolve(companyId, RETAINED_EARNINGS_CODE, RETAINED_EARNINGS_NAME, AccountType.EQUITY);
    }

    /** What the company owes vendors on approved-but-unpaid bills - see VendorBillServiceImpl. */
    public ChartOfAccount accountsPayable(Long companyId) {
        return resolve(companyId, ACCOUNTS_PAYABLE_CODE, ACCOUNTS_PAYABLE_NAME, AccountType.LIABILITY);
    }

    public ChartOfAccount fixedAssets(Long companyId) {
        return resolve(companyId, FIXED_ASSETS_CODE, FIXED_ASSETS_NAME, AccountType.ASSET);
    }

    public ChartOfAccount accumulatedDepreciation(Long companyId) {
        return resolve(companyId, ACCUMULATED_DEPRECIATION_CODE, ACCUMULATED_DEPRECIATION_NAME, AccountType.CONTRA_ASSET);
    }

    public ChartOfAccount depreciationExpense(Long companyId) {
        return resolve(companyId, DEPRECIATION_EXPENSE_CODE, DEPRECIATION_EXPENSE_NAME, AccountType.EXPENSE);
    }

    /** Offset side of opening-balance entries when migrating from a previous system. */
    public ChartOfAccount openingBalanceEquity(Long companyId) {
        return resolve(companyId, OPENING_BALANCE_EQUITY_CODE, OPENING_BALANCE_EQUITY_NAME, AccountType.EQUITY);
    }

    /**
     * Reuses an existing account at this code, but only if its type matches: a mismatched type silently misclassifies every posting against it, so it fails loudly here.
     * <p>Race: two first-time posters both saw "no account at code 1000" and one hit the (company_id, account_code) unique constraint, rolling back its whole business transaction - creation goes through INSERT ... ON CONFLICT DO NOTHING plus a re-read.
     * <p>Soft-deleted code: the unique constraint covers soft-deleted rows, so a deleted "1000 Cash and Bank" made every later posting fail on a duplicate key; such a row is revived instead.
     */
    @Transactional
    public ChartOfAccount resolve(Long companyId, String code, String name, AccountType type) {
        ChartOfAccount existing = coaRepository.findByCompanyIdAndAccountCode(companyId, code).orElse(null);
        if (existing != null) {
            return requireMatchingType(existing, code, name, type);
        }

        // Nothing live at this code, but a soft-deleted row may still be holding it.
        ChartOfAccount deleted = coaRepository.findByCompanyIdAndAccountCodeIncludingDeleted(companyId, code)
                .orElse(null);
        if (deleted != null) {
            return reviveSoftDeleted(deleted, name, type);
        }

        // ON CONFLICT DO NOTHING: either we create it, or a concurrent caller already did.
        coaRepository.insertIfAbsent(companyId, code, name, type.name());
        ChartOfAccount created = coaRepository.findByCompanyIdAndAccountCode(companyId, code)
                .orElseThrow(() -> new BadRequestException(
                        "Could not resolve or create the default Chart of Accounts entry " + code + " (" + name + ")"));
        return requireMatchingType(created, code, name, type);
    }

    private ChartOfAccount requireMatchingType(ChartOfAccount account, String code, String name, AccountType type) {
        if (account.getType() != type) {
            throw new BadRequestException(
                    "Chart of Accounts code " + code + " already exists as \"" + account.getAccountName()
                            + "\" (" + account.getType() + "), but " + name + " requires " + type
                            + " - rename or recode the existing account before posting can continue.");
        }
        return account;
    }

    /** Revives a soft-deleted default account under its same id so historic GL rows still resolve; the balance is left alone because zeroing it would desync it from the ledger rows pointing here. */
    private ChartOfAccount reviveSoftDeleted(ChartOfAccount account, String name, AccountType type) {
        account.setDeleted(false);
        account.setDeletedAt(null);
        account.setAccountName(name);
        account.setType(type);
        account.setActive(true);
        account.setHeaderAccount(false);
        account.setAllowDirectPosting(true);
        if (account.getBalance() == null) {
            account.setBalance(BigDecimal.ZERO);
        }
        account.setDescription("Auto-created default account (restored)");
        return coaRepository.save(account);
    }
}
