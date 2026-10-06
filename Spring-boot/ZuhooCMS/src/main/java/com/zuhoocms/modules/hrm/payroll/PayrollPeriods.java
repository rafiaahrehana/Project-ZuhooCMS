package com.zuhoocms.modules.hrm.payroll;

import com.zuhoocms.shared.exception.BadRequestException;

/** Single place for the pay-period bounds every payroll endpoint enforces. */
public final class PayrollPeriods {

    public static final String MONTH_MESSAGE = "Pay month must be between 1 and 12.";
    public static final String YEAR_MESSAGE = "Pay year must be between 2000 and 2100.";

    private PayrollPeriods() {}

    public static void validate(Integer month, Integer year) {
        validateMonth(month);
        validateYear(year);
    }

    public static void validateMonth(Integer month) {
        if (month == null || month < 1 || month > 12) throw new BadRequestException(MONTH_MESSAGE);
    }

    public static void validateYear(Integer year) {
        if (year == null || year < 2000 || year > 2100) throw new BadRequestException(YEAR_MESSAGE);
    }
}
