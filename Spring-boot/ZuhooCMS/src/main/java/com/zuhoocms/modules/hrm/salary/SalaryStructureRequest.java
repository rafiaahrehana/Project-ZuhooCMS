package com.zuhoocms.modules.hrm.salary;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import lombok.Data;

import java.math.BigDecimal;
import java.time.LocalDate;

@Data
public class SalaryStructureRequest {
    @NotNull(message = "Employee ID is required")
    private Long employeeId;
    @NotNull(message = "Effective from date is required")
    private LocalDate effectiveFrom;
    @NotNull(message = "Gross salary is required")
    @DecimalMin(value = "0.01", message = "Amount must be positive")
    private BigDecimal grossSalary;
    @NotNull(message = "Basic salary is required")
    @DecimalMin(value = "0.01", message = "Amount must be positive")
    private BigDecimal basicSalary;
    @PositiveOrZero(message = "Amounts cannot be negative")
    private BigDecimal houseRent;
    @PositiveOrZero(message = "Amounts cannot be negative")
    private BigDecimal medicalAllowance;
    @PositiveOrZero(message = "Amounts cannot be negative")
    private BigDecimal transportAllowance;
    @PositiveOrZero(message = "Amounts cannot be negative")
    private BigDecimal foodAllowance;
    @PositiveOrZero(message = "Amounts cannot be negative")
    private BigDecimal specialAllowance;
    @PositiveOrZero(message = "Amounts cannot be negative")
    private BigDecimal providentFund;
    @PositiveOrZero(message = "Amounts cannot be negative")
    private BigDecimal taxDeduction;
    private String notes;
}
