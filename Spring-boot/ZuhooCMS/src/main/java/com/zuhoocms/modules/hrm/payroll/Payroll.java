package com.zuhoocms.modules.hrm.payroll;

import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.core.base.BaseEntity;

import com.zuhoocms.modules.company.Company;
import com.zuhoocms.enums.PayrollStatus;
import com.zuhoocms.enums.PaymentMethod;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.math.BigDecimal;
import java.time.LocalDate;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "payrolls",
    uniqueConstraints = @UniqueConstraint(columnNames = {"employee_id", "pay_month", "pay_year"}))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Payroll extends BaseEntity {

    // Optimistic lock: concurrent approve/pay/settle must fail fast, not overwrite; columnDefinition backfills existing rows under ddl-auto=update.
    @Version
    @Column(name = "version", nullable = false, columnDefinition = "bigint default 0")
    private Long version;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "employee_id", nullable = false)
    private Employee employee;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;

    @Column(name = "pay_month", nullable = false)
    private int payMonth;   // 1-12

    @Column(name = "pay_year", nullable = false)
    private int payYear;

    @Builder.Default

    @Column(precision = 12, scale = 2)
    private BigDecimal basicSalary = BigDecimal.ZERO;

    @Builder.Default


    @Column(precision = 12, scale = 2)
    private BigDecimal houseRent = BigDecimal.ZERO;

    @Builder.Default


    @Column(precision = 12, scale = 2)
    private BigDecimal medicalAllowance = BigDecimal.ZERO;

    @Builder.Default


    @Column(precision = 12, scale = 2)
    private BigDecimal transportAllowance = BigDecimal.ZERO;

    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal foodAllowance = BigDecimal.ZERO;

    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal specialAllowance = BigDecimal.ZERO;

    @Builder.Default


    @Column(precision = 12, scale = 2)
    private BigDecimal bonus = BigDecimal.ZERO;

    // Billable pay: approved timesheet billableHours * employee billableRate, added to gross/net on top of the fixed components.
    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal billableHours = BigDecimal.ZERO;

    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal billableRate = BigDecimal.ZERO;

    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal billablePay = BigDecimal.ZERO;

    // Overtime frozen at run time: the salary sheet recomputes it live, so a later multiplier change would restate an already-issued payslip.
    // Nullable on purpose - ddl-auto=update cannot add a NOT NULL column to a table that already has rows.
    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal overtimeHours = BigDecimal.ZERO;

    /** The per-hour figure used, already including the multiplier. */
    @Builder.Default
    @Column(precision = 12, scale = 4)
    private BigDecimal overtimeRate = BigDecimal.ZERO;

    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal overtimePay = BigDecimal.ZERO;

    // employee_salary_components earnings/deductions summed at run time and frozen here, like overtime. Nullable - ddl-auto=update.
    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal otherEarnings = BigDecimal.ZERO;

    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal otherDeductions = BigDecimal.ZERO;

    @Builder.Default

    @Column(precision = 12, scale = 2)
    private BigDecimal deductions = BigDecimal.ZERO;

    @Builder.Default


    @Column(precision = 12, scale = 2)
    private BigDecimal taxDeduction = BigDecimal.ZERO;

    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal insuranceDeduction = BigDecimal.ZERO;

    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal providentFundDeduction = BigDecimal.ZERO;

    /** (gross / calendar days in month) * unapproved absent days; separate from manual `deductions`. Approved leave never counts as absent - see AbsenteeMarkingService. */
    @Builder.Default
    @Column(precision = 12, scale = 2)
    private BigDecimal attendanceDeduction = BigDecimal.ZERO;

    @Builder.Default
    @Column(name = "absent_days")
    private Integer absentDays = 0;

    // Nullable: rows predating runs, and ad-hoc single payrolls, have no run.
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "payroll_run_id")
    private com.zuhoocms.modules.hrm.payroll.run.PayrollRun run;

    // Installment frozen at DRAFT creation; remainingBalance only moves at PAID (see PayrollServiceImpl.markPaid), so deleting a DRAFT needs no reversal. Nullable.
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "loan_advance_id")
    private com.zuhoocms.modules.hrm.payroll.loan.LoanAdvance loanAdvance;

    @Column(precision = 12, scale = 2)
    private BigDecimal loanDeductionAmount;

    private String glDebitAccount;
    private String glCreditAccount;

    @Enumerated(EnumType.STRING)
    @Column(length = 20)
    private PaymentMethod paymentMethod;

    @Builder.Default

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal netSalary = BigDecimal.ZERO;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private PayrollStatus status = PayrollStatus.DRAFT;

    @Column(columnDefinition = "TEXT")
    private String notes;

    private String paymentReference;
    private LocalDate paidAt;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "approved_by_id")
    private Employee approvedBy;
}
