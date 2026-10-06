package com.zuhoocms.modules.finance.reports.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import java.math.BigDecimal;
import java.time.LocalDate;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class BalanceSheetReport {
    private LocalDate asOfDate;
    private BigDecimal totalAssets;
    private BigDecimal totalLiabilities;
    private BigDecimal totalEquity;
    // Assets should equal Liabilities + Equity; otherwise an unbalanced entry was posted or a fiscal year is unclosed (net income not yet in Retained Earnings) - see AccountingPeriodService.closeFiscalYear.
    private boolean balanced;
    private BigDecimal outOfBalanceAmount;
    private LocalDate generatedDate;
}
