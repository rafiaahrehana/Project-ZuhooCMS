package com.zuhoocms.modules.hrm.payroll;

import com.zuhoocms.enums.LeaveType;
import com.zuhoocms.enums.SalaryBase;
import com.zuhoocms.modules.hrm.attendance.attendance.Attendance;
import com.zuhoocms.modules.hrm.attendance.attendance.AttendanceRepository;
import com.zuhoocms.modules.hrm.attendance.attendance.AttendanceStatus;
import com.zuhoocms.modules.hrm.attendance.timesheet.TimesheetRepository;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.leave.LeaveService;
import com.zuhoocms.modules.hrm.leave.leaverequest.LeaveRequest;
import com.zuhoocms.modules.hrm.leave.leaverequest.LeaveRequestRepository;
import com.zuhoocms.modules.hrm.payroll.components.SalaryComponent;
import com.zuhoocms.modules.hrm.payroll.components.SalaryComponentService;
import com.zuhoocms.modules.hrm.payroll.loan.LoanAdvance;
import com.zuhoocms.modules.hrm.payroll.loan.LoanAdvanceRepository;
import com.zuhoocms.modules.hrm.payroll.settings.PayrollSettings;
import com.zuhoocms.modules.hrm.payroll.settings.PayrollSettingsService;
import com.zuhoocms.modules.hrm.salary.SalaryStructure;
import com.zuhoocms.modules.hrm.salary.SalaryStructureRepository;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

/**
 * The ONE place payroll money is computed: create, bulk generate, run recalculation and projected sheet rows all use {@link #calculate}, so no two paths can price a month differently.
 * - Fixed components come from the structure active on day 1 of the period; a manual basicSalary overrides only those six.
 * - Tax, PF and extra components from that structure apply in every path; manual bonus/deductions/tax/insurance/PF are added on top.
 * - Absence deduction is capped at the fixed gross.
 * - An ABSENT attendance day inside approved UNPAID leave is counted once (as leave).
 * - Loan installment is due only once the loan is disbursed by period end, and never exceeds what other lines' reservations leave.
 * - If net would go negative the loan installment shrinks first; still negative fails in strict mode.
 */
@Component
@RequiredArgsConstructor
public class PayrollCalculator {

    private final SalaryStructureRepository salaryStructureRepository;
    private final AttendanceRepository attendanceRepository;
    private final TimesheetRepository timesheetRepository;
    private final PayrollSettingsService payrollSettingsService;
    private final SalaryComponentService salaryComponentService;
    private final LeaveService leaveService;
    private final LeaveRequestRepository leaveRequestRepository;
    private final LoanAdvanceRepository loanAdvanceRepository;
    private final PayrollRepository payrollRepository;

    /** Manually supplied amounts. Every field may be null. */
    public record ManualInputs(BigDecimal basic, BigDecimal rent, BigDecimal medical, BigDecimal transport,
                               BigDecimal food, BigDecimal special,
                               BigDecimal bonus, BigDecimal deductions, BigDecimal tax,
                               BigDecimal insurance, BigDecimal providentFund) {

        public static ManualInputs none() {
            return new ManualInputs(null, null, null, null, null, null, null, null, null, null, null);
        }

        public static ManualInputs from(CreatePayrollRequest r) {
            return new ManualInputs(r.getBasicSalary(), r.getHouseRent(), r.getMedicalAllowance(),
                    r.getTransportAllowance(), r.getFoodAllowance(), r.getSpecialAllowance(),
                    r.getBonus(), r.getDeductions(), r.getTaxDeduction(),
                    r.getInsuranceDeduction(), r.getProvidentFundDeduction());
        }
    }

    public record Result(
            SalaryStructure structure,
            BigDecimal basic, BigDecimal rent, BigDecimal medical, BigDecimal transport,
            BigDecimal food, BigDecimal special, BigDecimal fixedGross,
            BigDecimal bonus,
            BigDecimal billableHours, BigDecimal billableRate, BigDecimal billablePay,
            BigDecimal overtimeHours, BigDecimal overtimeRate, BigDecimal overtimePay,
            BigDecimal otherEarnings, BigDecimal otherDeductions,
            BigDecimal deductions, BigDecimal tax, BigDecimal insurance, BigDecimal providentFund,
            BigDecimal attendanceDeduction, int absentDays,
            LoanAdvance loan, BigDecimal loanDeduction,
            BigDecimal gross, BigDecimal net) {

        /** Everything subtracted from gross, loan included. */
        public BigDecimal totalDeductions() {
            return gross.subtract(net);
        }
    }

    public Optional<SalaryStructure> activeStructure(Long employeeId, int payMonth, int payYear) {
        return salaryStructureRepository.findActiveForEmployeeOnDate(employeeId, LocalDate.of(payYear, payMonth, 1));
    }

    /**
     * @param existingPayrollId the line being recomputed, so its own loan reservation is not counted against itself; null for a new line
     * @param strict            true for real payroll lines (throws when deductions exceed gross); false for the salary sheet projection
     */
    public Result calculate(Employee employee, Long companyId, int payMonth, int payYear,
                            ManualInputs manual, Long existingPayrollId, boolean strict) {
        ManualInputs m = manual != null ? manual : ManualInputs.none();
        SalaryStructure structure = activeStructure(employee.getId(), payMonth, payYear).orElse(null);

        BigDecimal basic, rent, medical, transport, food, special;
        if (m.basic() != null) {
            basic = m.basic();
            rent = nz(m.rent());
            medical = nz(m.medical());
            transport = nz(m.transport());
            food = nz(m.food());
            special = nz(m.special());
        } else if (structure != null) {
            basic = nz(structure.getBasicSalary());
            rent = nz(structure.getHouseRent());
            medical = nz(structure.getMedicalAllowance());
            transport = nz(structure.getTransportAllowance());
            food = nz(structure.getFoodAllowance());
            special = nz(structure.getSpecialAllowance());
        } else {
            throw new BadRequestException(
                    "No active salary structure for " + displayName(employee) + " for " + payMonth + "/" + payYear
                            + " - set one up under Salary Structures, or provide basicSalary manually");
        }
        BigDecimal fixedGross = basic.add(rent).add(medical).add(transport).add(food).add(special);

        BigDecimal bonus = nz(m.bonus());
        BigDecimal deductions = nz(m.deductions());
        BigDecimal insurance = nz(m.insurance());
        BigDecimal tax = nz(m.tax());
        BigDecimal providentFund = nz(m.providentFund());
        BigDecimal otherEarnings = BigDecimal.ZERO;
        BigDecimal otherDeductions = BigDecimal.ZERO;
        if (structure != null) {
            // The structure wins: its tax and provident fund REPLACE whatever the request carried, they are not
            // added to it. Adding them deducted both twice - a request of 1000 against a structure of 1000 took
            // 2000 - and the only symptom was a wrong net salary. It also made the two paths disagree, because
            // recalculate passes null here and so produced a different figure for the same line.
            //
            // Replacing is also what the rest of this method already does: when a basic salary is supplied the six
            // fixed earnings are taken FROM the request and the structure is ignored for them. Tax and PF adding
            // instead of overriding was the asymmetry, not the rule.
            tax = nz(structure.getTaxDeduction());
            providentFund = nz(structure.getProvidentFund());
            otherEarnings = salaryComponentService.sumExtras(structure.getId(), SalaryComponent.ComponentType.EARNING);
            otherDeductions = salaryComponentService.sumExtras(structure.getId(), SalaryComponent.ComponentType.DEDUCTION);
        }

        PayrollSettings settings = payrollSettingsService.getOrCreate(companyId);
        LocalDate start = LocalDate.of(payYear, payMonth, 1);
        LocalDate end = start.withDayOfMonth(start.lengthOfMonth());

        // Billable pay: approved timesheet hours x the employee's billable rate.
        BigDecimal billableRate = nz(employee.getBillableRate());
        BigDecimal billableHours = BigDecimal.valueOf(
                timesheetRepository.sumApprovedBillableHours(employee.getId(), start, end).orElse(0.0));
        BigDecimal billablePay = billableRate.signum() == 0
                ? BigDecimal.ZERO
                : billableRate.multiply(billableHours).setScale(2, RoundingMode.HALF_UP);

        BigDecimal overtimeHours = BigDecimal.ZERO, overtimeRate = BigDecimal.ZERO, overtimePay = BigDecimal.ZERO;
        if (settings.isOvertimeEnabled()) {
            BigDecimal hours = nz(attendanceRepository.sumOvertimeHours(employee.getId(), start, end));
            if (hours.signum() > 0) {
                overtimeHours = hours;
                BigDecimal base = settings.getOvertimeBase() == SalaryBase.GROSS ? fixedGross : basic;
                BigDecimal hoursPerDay = nz(settings.getStandardHoursPerDay());
                if (base.signum() > 0 && hoursPerDay.signum() > 0) {
                    BigDecimal perDay = payrollSettingsService.perDayRate(settings, base, payMonth, payYear);
                    BigDecimal hourly = perDay.divide(hoursPerDay, 4, RoundingMode.HALF_UP)
                            .multiply(nz(settings.getOvertimeMultiplier()));
                    overtimePay = hourly.multiply(hours).setScale(2, RoundingMode.HALF_UP);
                    overtimeRate = hourly.setScale(4, RoundingMode.HALF_UP);
                }
            }
        }

        // Absence (ABSENT days not already covered by unpaid leave + unpaid leave days).
        int absentDays = absentDays(employee.getId(), companyId, payMonth, payYear);
        BigDecimal attendanceDeduction = BigDecimal.ZERO;
        if (absentDays > 0) {
            BigDecimal base = settings.getAbsenceDeductionBase() == SalaryBase.BASIC ? basic : fixedGross;
            if (base.signum() > 0) {
                attendanceDeduction = payrollSettingsService.perDayRate(settings, base, payMonth, payYear)
                        .multiply(BigDecimal.valueOf(absentDays))
                        .setScale(2, RoundingMode.HALF_UP)
                        .min(fixedGross);
            }
        }

        LoanAdvance loan = null;
        BigDecimal loanDeduction = BigDecimal.ZERO;
        Optional<LoanAdvance> activeLoan = loanAdvanceRepository
                .findFirstByEmployeeIdAndStatus(employee.getId(), LoanAdvance.Status.ACTIVE);
        if (activeLoan.isPresent()) {
            LoanAdvance l = activeLoan.get();
            if (l.getDisbursedDate() == null || !l.getDisbursedDate().isAfter(end)) {
                BigDecimal reserved = nz(payrollRepository.sumReservedLoanDeduction(
                        l.getId(), existingPayrollId != null ? existingPayrollId : -1L));
                BigDecimal available = nz(l.getRemainingBalance()).subtract(reserved);
                BigDecimal due = nz(l.getMonthlyInstallment()).min(available).max(BigDecimal.ZERO);
                if (due.signum() > 0) {
                    loan = l;
                    loanDeduction = due;
                }
            }
        }

        BigDecimal gross = fixedGross.add(bonus).add(billablePay).add(overtimePay).add(otherEarnings);
        BigDecimal net = gross.subtract(deductions).subtract(tax).subtract(insurance).subtract(providentFund)
                .subtract(attendanceDeduction).subtract(otherDeductions).subtract(loanDeduction);

        if (net.signum() < 0 && loanDeduction.signum() > 0) {
            BigDecimal reduce = loanDeduction.min(net.negate());
            loanDeduction = loanDeduction.subtract(reduce);
            net = net.add(reduce);
            if (loanDeduction.signum() == 0) loan = null;
        }
        if (net.signum() < 0 && strict) {
            throw new BadRequestException("Deductions exceed gross pay for " + displayName(employee));
        }

        return new Result(structure, basic, rent, medical, transport, food, special, fixedGross, bonus,
                billableHours, billableRate, billablePay, overtimeHours, overtimeRate, overtimePay,
                otherEarnings, otherDeductions, deductions, tax, insurance, providentFund,
                attendanceDeduction, absentDays, loan, loanDeduction, gross, net);
    }

    /** Copies every computed figure onto the line. Does not touch status/run/payment fields. */
    public void apply(Result r, Payroll p) {
        p.setBasicSalary(r.basic());
        p.setHouseRent(r.rent());
        p.setMedicalAllowance(r.medical());
        p.setTransportAllowance(r.transport());
        p.setFoodAllowance(r.food());
        p.setSpecialAllowance(r.special());
        p.setBonus(r.bonus());
        p.setBillableHours(r.billableHours());
        p.setBillableRate(r.billableRate());
        p.setBillablePay(r.billablePay());
        p.setOvertimeHours(r.overtimeHours());
        p.setOvertimeRate(r.overtimeRate());
        p.setOvertimePay(r.overtimePay());
        p.setOtherEarnings(r.otherEarnings());
        p.setOtherDeductions(r.otherDeductions());
        p.setDeductions(r.deductions());
        p.setTaxDeduction(r.tax());
        p.setInsuranceDeduction(r.insurance());
        p.setProvidentFundDeduction(r.providentFund());
        p.setAttendanceDeduction(r.attendanceDeduction());
        p.setAbsentDays(r.absentDays());
        p.setLoanAdvance(r.loan());
        p.setLoanDeductionAmount(r.loanDeduction());
        p.setNetSalary(r.net());
    }

    /**
     * ABSENT rows in the period, minus those inside approved UNPAID leave (already charged as leave), plus chargeable
     * approved unpaid-leave days.
     *
     * <p>companyId is a parameter, not derived here: payroll runs on scheduler threads where Hibernate's tenantFilter is
     * not enabled, so the attendance and leave lookups below must carry the tenant themselves or an employee id from
     * another company would price this company's month.
     */
    public int absentDays(Long employeeId, Long companyId, int payMonth, int payYear) {
        LocalDate start = LocalDate.of(payYear, payMonth, 1);
        LocalDate end = start.withDayOfMonth(start.lengthOfMonth());

        List<LocalDate> absentDates = attendanceRepository.findByEmployeeAndDateRange(companyId, employeeId, start, end).stream()
                .filter(a -> a.getStatus() == AttendanceStatus.ABSENT)
                .map(Attendance::getAttendanceDate)
                .toList();

        int absent = absentDates.size();
        if (absent > 0) {
            List<LeaveRequest> unpaid = leaveRequestRepository.findApprovedOverlapping(
                    companyId, employeeId, LeaveType.UNPAID, start, end);
            if (!unpaid.isEmpty()) {
                long overlap = absentDates.stream()
                        .filter(d -> unpaid.stream().anyMatch(lr -> lr.getStartDate() != null && lr.getEndDate() != null
                                && !d.isBefore(lr.getStartDate()) && !d.isAfter(lr.getEndDate())))
                        .count();
                absent -= (int) overlap;
            }
        }
        return absent + leaveService.unpaidLeaveDays(employeeId, companyId, payMonth, payYear);
    }

    public static String displayName(Employee employee) {
        if (employee.getUser() != null && employee.getUser().getFullName() != null) {
            return employee.getUser().getFullName();
        }
        return employee.getEmployeeNumber() != null ? employee.getEmployeeNumber() : "Employee #" + employee.getId();
    }

    private static BigDecimal nz(BigDecimal v) {
        return v != null ? v : BigDecimal.ZERO;
    }
}
