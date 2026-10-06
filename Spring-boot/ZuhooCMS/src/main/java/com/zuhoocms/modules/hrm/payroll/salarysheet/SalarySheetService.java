package com.zuhoocms.modules.hrm.payroll.salarysheet;

import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.hrm.payroll.PayrollCalculator;
import com.zuhoocms.modules.hrm.payroll.PayrollPeriods;
import com.zuhoocms.modules.hrm.payroll.settings.PayrollSettings;
import com.zuhoocms.modules.hrm.payroll.settings.PayrollSettingsService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.List;

/**
 * Builds the company's salary sheet for a month, live rather than stored: absent days and overtime are read from attendance each time, so a corrected check-in shows immediately.
 * Payroll generation is what freezes the numbers; projected rows are priced by PayrollCalculator so preview and real payroll cannot disagree.
 */
@Service
@RequiredArgsConstructor
public class SalarySheetService {

    private final EmployeeRepository employeeRepository;
    private final PayrollSettingsService payrollSettingsService;
    private final SecurityUtil securityUtil;
    private final com.zuhoocms.modules.hrm.payroll.PayrollRepository payrollRepository;
    private final PayrollCalculator calculator;

    @Transactional(readOnly = true)
    public SalarySheetResponse build(int payMonth, int payYear) {
        PayrollPeriods.validate(payMonth, payYear);
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context for the current user");
        }

        PayrollSettings settings = payrollSettingsService.getOrCreate(companyId);
        int divisor = payrollSettingsService.perDayDivisor(settings, payMonth, payYear);

        List<SalarySheetRow> rows = new ArrayList<>();
        for (Employee employee : employeeRepository.findByCompanyIdAndActiveTrue(companyId)) {
            rows.add(buildRow(employee, companyId, payMonth, payYear));
        }
        rows.sort((a, b) -> a.getEmployeeName().compareToIgnoreCase(b.getEmployeeName()));

        return totalled(rows, payMonth, payYear, settings, divisor);
    }

    private SalarySheetRow buildRow(Employee employee, Long companyId, int payMonth, int payYear) {

        SalarySheetRow.SalarySheetRowBuilder row = SalarySheetRow.builder()
                .employeeId(employee.getId())
                .employeeNumber(employee.getEmployeeNumber())
                .employeeName(displayName(employee))
                .position(position(employee))
                .department(employee.getDepartment() != null ? employee.getDepartment().getName() : null);

        // Once payroll exists for the period the sheet restates the frozen register, not a fresh estimate; before that it is a live projection from the structure.
        var payrollOpt = payrollRepository.findByEmployeeIdAndPayMonthAndPayYear(
                employee.getId(), payMonth, payYear);
        if (payrollOpt.isPresent()) {
            var p = payrollOpt.get();
            BigDecimal earnExtras = orZero(p.getOtherEarnings()).add(orZero(p.getBillablePay()));
            BigDecimal dedExtras = orZero(p.getOtherDeductions()).add(orZero(p.getDeductions()))
                    .add(orZero(p.getInsuranceDeduction()));
            BigDecimal gross = orZero(p.getBasicSalary()).add(orZero(p.getHouseRent()))
                    .add(orZero(p.getMedicalAllowance())).add(orZero(p.getTransportAllowance()))
                    .add(orZero(p.getFoodAllowance())).add(orZero(p.getSpecialAllowance()))
                    .add(orZero(p.getBonus())).add(orZero(p.getOvertimePay())).add(earnExtras);
            BigDecimal totalDed = orZero(p.getAttendanceDeduction()).add(orZero(p.getTaxDeduction()))
                    .add(orZero(p.getProvidentFundDeduction())).add(orZero(p.getLoanDeductionAmount())).add(dedExtras);
            return row
                    .source("PAYROLL")
                    .payrollId(p.getId())
                    .paymentStatus(p.getStatus() != null ? p.getStatus().name() : null)
                    .paymentMethod(p.getPaymentMethod() != null ? p.getPaymentMethod().name() : null)
                    .basic(orZero(p.getBasicSalary())).houseRent(orZero(p.getHouseRent()))
                    .medical(orZero(p.getMedicalAllowance())).transport(orZero(p.getTransportAllowance()))
                    .food(orZero(p.getFoodAllowance())).special(orZero(p.getSpecialAllowance()))
                    .bonus(orZero(p.getBonus()))
                    .overtimeHours(orZero(p.getOvertimeHours())).overtimePayment(orZero(p.getOvertimePay()))
                    .otherEarnings(earnExtras).otherDeductions(dedExtras)
                    .grossEarnings(gross)
                    .absentDays(p.getAbsentDays() != null ? p.getAbsentDays() : 0)
                    .absentDeduction(orZero(p.getAttendanceDeduction()))
                    .tax(orZero(p.getTaxDeduction())).providentFund(orZero(p.getProvidentFundDeduction()))
                    .totalDeductions(totalDed)
                    .netPayable(orZero(p.getNetSalary()))
                    .build();
        }
        row.source("PROJECTED").bonus(BigDecimal.ZERO);

        if (calculator.activeStructure(employee.getId(), payMonth, payYear).isEmpty()) {
            // Listed with zeroes and a note rather than omitted - a missing employee is a problem you want to see.
            return row
                    .basic(BigDecimal.ZERO).houseRent(BigDecimal.ZERO).medical(BigDecimal.ZERO)
                    .transport(BigDecimal.ZERO).food(BigDecimal.ZERO).special(BigDecimal.ZERO)
                    .overtimeHours(BigDecimal.ZERO).overtimePayment(BigDecimal.ZERO)
                    .otherEarnings(BigDecimal.ZERO).otherDeductions(BigDecimal.ZERO)
                    .grossEarnings(BigDecimal.ZERO)
                    .absentDays(calculator.absentDays(employee.getId(), companyId, payMonth, payYear))
                    .absentDeduction(BigDecimal.ZERO)
                    .tax(BigDecimal.ZERO).providentFund(BigDecimal.ZERO)
                    .totalDeductions(BigDecimal.ZERO).netPayable(BigDecimal.ZERO)
                    .note("No salary structure effective for this month")
                    .build();
        }

        // Non-strict: a projection shows a negative net instead of failing the whole sheet.
        PayrollCalculator.Result r = calculator.calculate(employee, companyId, payMonth, payYear,
                PayrollCalculator.ManualInputs.none(), null, false);

        // Same column mapping as the PAYROLL branch: billable pay rides in other earnings, manual deductions/insurance in other deductions.
        BigDecimal earnExtras = r.otherEarnings().add(r.billablePay());
        BigDecimal dedExtras = r.otherDeductions().add(r.deductions()).add(r.insurance());
        BigDecimal totalDeductions = r.attendanceDeduction().add(r.tax()).add(r.providentFund())
                .add(r.loanDeduction()).add(dedExtras);

        return row
                .basic(r.basic()).houseRent(r.rent()).medical(r.medical())
                .transport(r.transport()).food(r.food()).special(r.special())
                .bonus(r.bonus())
                .overtimeHours(r.overtimeHours()).overtimePayment(r.overtimePay())
                .otherEarnings(earnExtras).otherDeductions(dedExtras)
                .grossEarnings(r.gross())
                .absentDays(r.absentDays()).absentDeduction(r.attendanceDeduction())
                .tax(r.tax()).providentFund(r.providentFund())
                .totalDeductions(totalDeductions)
                .netPayable(r.net().setScale(2, RoundingMode.HALF_UP))
                .build();
    }

    private SalarySheetResponse totalled(List<SalarySheetRow> rows, int payMonth, int payYear,
                                         PayrollSettings settings, int divisor) {
        BigDecimal basic = BigDecimal.ZERO, rent = BigDecimal.ZERO, medical = BigDecimal.ZERO;
        BigDecimal transport = BigDecimal.ZERO, food = BigDecimal.ZERO, special = BigDecimal.ZERO;
        BigDecimal otHours = BigDecimal.ZERO, otPay = BigDecimal.ZERO, gross = BigDecimal.ZERO;
        BigDecimal absentAmt = BigDecimal.ZERO, tax = BigDecimal.ZERO, pf = BigDecimal.ZERO;
        BigDecimal deductions = BigDecimal.ZERO, net = BigDecimal.ZERO;
        BigDecimal bonus = BigDecimal.ZERO, otherEarn = BigDecimal.ZERO, otherDed = BigDecimal.ZERO;
        int absentDays = 0;

        for (SalarySheetRow r : rows) {
            bonus = bonus.add(orZero(r.getBonus()));
            otherEarn = otherEarn.add(orZero(r.getOtherEarnings()));
            otherDed = otherDed.add(orZero(r.getOtherDeductions()));
            basic = basic.add(r.getBasic());
            rent = rent.add(r.getHouseRent());
            medical = medical.add(r.getMedical());
            transport = transport.add(r.getTransport());
            food = food.add(r.getFood());
            special = special.add(r.getSpecial());
            otHours = otHours.add(r.getOvertimeHours());
            otPay = otPay.add(r.getOvertimePayment());
            gross = gross.add(r.getGrossEarnings());
            absentDays += r.getAbsentDays();
            absentAmt = absentAmt.add(r.getAbsentDeduction());
            tax = tax.add(r.getTax());
            pf = pf.add(r.getProvidentFund());
            deductions = deductions.add(r.getTotalDeductions());
            net = net.add(r.getNetPayable());
        }

        return SalarySheetResponse.builder()
                .payMonth(payMonth).payYear(payYear)
                .perDayBasis(settings.getPerDayBasis().name())
                .perDayDivisor(divisor)
                .overtimeEnabled(settings.isOvertimeEnabled())
                .overtimeMultiplier(settings.getOvertimeMultiplier())
                .rows(rows)
                .totalBasic(basic).totalHouseRent(rent).totalMedical(medical)
                .totalTransport(transport).totalFood(food).totalSpecial(special)
                .totalOvertimeHours(otHours).totalOvertimePayment(otPay)
                .totalBonus(bonus).totalOtherEarnings(otherEarn).totalOtherDeductions(otherDed)
                .totalGrossEarnings(gross)
                .totalAbsentDays(absentDays).totalAbsentDeduction(absentAmt)
                .totalTax(tax).totalProvidentFund(pf)
                .totalDeductions(deductions).totalNetPayable(net)
                .build();
    }

    private String displayName(Employee e) {
        if (e.getUser() != null) {
            String name = ((e.getUser().getFirstName() == null ? "" : e.getUser().getFirstName()) + " "
                    + (e.getUser().getLastName() == null ? "" : e.getUser().getLastName())).trim();
            if (!name.isEmpty()) return name;
        }
        return e.getEmployeeNumber() != null ? e.getEmployeeNumber() : ("Employee #" + e.getId());
    }

    private String position(Employee e) {
        if (e.getDesignation() != null && e.getDesignation().getName() != null) {
            return e.getDesignation().getName();
        }
        return e.getJobTitle();
    }

    private BigDecimal orZero(BigDecimal v) {
        return v == null ? BigDecimal.ZERO : v;
    }
}
