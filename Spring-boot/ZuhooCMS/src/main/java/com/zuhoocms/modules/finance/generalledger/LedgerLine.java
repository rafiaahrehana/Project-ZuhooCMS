package com.zuhoocms.modules.finance.generalledger;

import java.math.BigDecimal;

/** One line of a balanced multi-line posting (see GeneralLedgerService.recordBalancedTransaction): at most one of debitAmount/creditAmount is nonzero - zero/zero is skipped, both nonzero is rejected. */
public record LedgerLine(Long accountId, BigDecimal debitAmount, BigDecimal creditAmount) {

    public static LedgerLine debit(Long accountId, BigDecimal amount) {
        return new LedgerLine(accountId, amount, BigDecimal.ZERO);
    }

    public static LedgerLine credit(Long accountId, BigDecimal amount) {
        return new LedgerLine(accountId, BigDecimal.ZERO, amount);
    }
}
