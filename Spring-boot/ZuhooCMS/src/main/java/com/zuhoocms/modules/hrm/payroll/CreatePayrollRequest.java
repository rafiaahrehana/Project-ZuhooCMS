package com.zuhoocms.modules.hrm.payroll;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

import java.math.BigDecimal;

@Data
public class CreatePayrollRequest {
    @NotNull(message = "Employee ID is required")
    private Long employeeId;
    @NotNull(message = PayrollPeriods.MONTH_MESSAGE)
    @Min(value = 1, message = PayrollPeriods.MONTH_MESSAGE)
    @Max(value = 12, message = PayrollPeriods.MONTH_MESSAGE)
    private Integer payMonth;
    @NotNull(message = PayrollPeriods.YEAR_MESSAGE)
    @Min(value = 2000, message = PayrollPeriods.YEAR_MESSAGE)
    @Max(value = 2100, message = PayrollPeriods.YEAR_MESSAGE)
    private Integer payYear;

    // Optional: without basicSalary, PayrollCalculator takes the six fixed components from the structure active on day 1 of the period.
    // A manual basicSalary overrides only those six - tax, PF and extras still come from the structure, and manual bonus/deductions are added on top.
    @DecimalMin(value = "0", message = "Basic salary cannot be negative")
    private BigDecimal basicSalary;
    @DecimalMin(value = "0", message = "House rent cannot be negative")
    private BigDecimal houseRent;
    @DecimalMin(value = "0", message = "Medical allowance cannot be negative")
    private BigDecimal medicalAllowance;
    @DecimalMin(value = "0", message = "Transport allowance cannot be negative")
    private BigDecimal transportAllowance;
    @DecimalMin(value = "0", message = "Food allowance cannot be negative")
    private BigDecimal foodAllowance;
    @DecimalMin(value = "0", message = "Special allowance cannot be negative")
    private BigDecimal specialAllowance;
    @DecimalMin(value = "0", message = "Bonus cannot be negative")
    private BigDecimal bonus;
    @DecimalMin(value = "0", message = "Deductions cannot be negative")
    private BigDecimal deductions;
    @DecimalMin(value = "0", message = "Tax deduction cannot be negative")
    private BigDecimal taxDeduction;
    @DecimalMin(value = "0", message = "Insurance deduction cannot be negative")
    private BigDecimal insuranceDeduction;
    @DecimalMin(value = "0", message = "Provident fund deduction cannot be negative")
    private BigDecimal providentFundDeduction;
    private String notes;
}
