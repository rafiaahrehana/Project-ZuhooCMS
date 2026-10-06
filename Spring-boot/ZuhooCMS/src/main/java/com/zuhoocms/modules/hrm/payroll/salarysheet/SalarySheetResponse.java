package com.zuhoocms.modules.hrm.payroll.salarysheet;

import lombok.Builder;
import lombok.Data;

import java.math.BigDecimal;
import java.util.List;

/** The company's salary sheet for one month, computed live from structures, attendance and settings; nothing is stored until running payroll freezes it into Payroll rows. */
@Data
@Builder
public class SalarySheetResponse {

    private int payMonth;
    private int payYear;

    /** Echoed so the sheet can explain how a day rate was reached. */
    private String perDayBasis;
    private int perDayDivisor;
    private boolean overtimeEnabled;
    private BigDecimal overtimeMultiplier;

    private List<SalarySheetRow> rows;

    private BigDecimal totalBasic;
    private BigDecimal totalHouseRent;
    private BigDecimal totalMedical;
    private BigDecimal totalTransport;
    private BigDecimal totalFood;
    private BigDecimal totalSpecial;
    private BigDecimal totalOvertimeHours;
    private BigDecimal totalOvertimePayment;
    private BigDecimal totalBonus;
    private BigDecimal totalOtherEarnings;
    private BigDecimal totalOtherDeductions;
    private BigDecimal totalGrossEarnings;
    private int totalAbsentDays;
    private BigDecimal totalAbsentDeduction;
    private BigDecimal totalTax;
    private BigDecimal totalProvidentFund;
    private BigDecimal totalDeductions;
    private BigDecimal totalNetPayable;
}
