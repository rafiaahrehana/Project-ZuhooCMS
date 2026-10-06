package com.zuhoocms.modules.finance.period;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDate;
import java.time.LocalDateTime;

/** A rollup of a year's 12 AccountingPeriods: CLOSED once the year-end entry has posted, ACTIVE while the year contains today or has any closed period, DRAFT for an untouched generated year. */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FiscalYearSummary {
    private int fiscalYear;
    private String name; // "FY 2026"
    private LocalDate startDate;
    private LocalDate endDate;
    private int totalPeriods;
    private int openPeriods;
    private int closedPeriods;
    private String status; // DRAFT | ACTIVE | CLOSED
    private boolean yearEndPosted;
    private boolean current;
    private LocalDateTime createdAt;
}
