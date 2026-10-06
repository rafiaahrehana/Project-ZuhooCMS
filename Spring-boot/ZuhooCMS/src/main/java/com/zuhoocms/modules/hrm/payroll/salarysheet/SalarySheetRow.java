package com.zuhoocms.modules.hrm.payroll.salarysheet;

import lombok.Builder;
import lombok.Data;

import java.math.BigDecimal;

/** One employee's line on the salary sheet for a pay month. */
@Data
@Builder
public class SalarySheetRow {

    private Long employeeId;
    private String employeeNumber;
    private String employeeName;
    /** Designation, falling back to the free-text job title. */
    private String position;

    private BigDecimal basic;
    private BigDecimal houseRent;
    private BigDecimal medical;
    private BigDecimal transport;
    private BigDecimal food;
    private BigDecimal special;

    private BigDecimal overtimeHours;
    private BigDecimal overtimePayment;

    /** Fixed components plus overtime — what the employee earned before deductions. */
    private BigDecimal grossEarnings;

    private int absentDays;
    private BigDecimal absentDeduction;
    private BigDecimal tax;
    private BigDecimal providentFund;
    private BigDecimal totalDeductions;

    private BigDecimal netPayable;

    /** Set when no salary structure covers this month (every figure above is then zero); the row stays so nobody disappears from the sheet. */
    private String note;

    // Payment state, from the period.s Payroll row when one exists.
    private Long payrollId;
    private String paymentStatus;
    private String paymentMethod;
    private String department;

    // Structure extra components (loan EMI, internet, ...), frozen the same way payroll freezes them.
    private java.math.BigDecimal otherEarnings;
    private java.math.BigDecimal otherDeductions;

    /** Month bonus - only ever non-zero on PAYROLL-sourced rows. */
    private java.math.BigDecimal bonus;

    /** PAYROLL when the row restates the period's actual payroll record, PROJECTED when it is a live estimate from structure and attendance. */
    private String source;
}
