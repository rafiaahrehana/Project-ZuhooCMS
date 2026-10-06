package com.zuhoocms.modules.hrm.payroll.settings;

import com.zuhoocms.enums.PerDayBasis;
import com.zuhoocms.enums.SalaryBase;
import com.zuhoocms.modules.hrm.leave.holiday.HolidayRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;

/** Reads and applies one company's payroll policy; payroll calls {@link #perDayRate} rather than dividing itself, so "what is a day worth" is decided in one place. */
@Service
@RequiredArgsConstructor
public class PayrollSettingsService {

    private final PayrollSettingsRepository repository;
    private final HolidayRepository holidayRepository;
    private final SecurityUtil securityUtil;

    /**
     * The company's settings, so callers never deal with an empty Optional.
     * Missing rows return an unsaved defaults instance: read-only callers (the salary sheet) hit "cannot execute INSERT in a read-only transaction" and 500ed on a company's first view.
     * The row is written the first time a read-write caller (settings PUT, a payroll run) comes through.
     */
    @Transactional
    public PayrollSettings getOrCreate(Long companyId) {
        return repository.findByCompanyId(companyId)
                .orElseGet(() -> {
                    PayrollSettings defaults = PayrollSettings.builder().companyId(companyId).build();
                    if (TransactionSynchronizationManager.isCurrentTransactionReadOnly()) {
                        return defaults;
                    }
                    return repository.save(defaults);
                });
    }

    @Transactional
    public PayrollSettings getOrCreateForCurrentCompany() {
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context for the current user");
        }
        return getOrCreate(companyId);
    }

    @Transactional
    public PayrollSettings update(PayrollSettingsRequest request) {
        PayrollSettings settings = getOrCreateForCurrentCompany();

        if (request.getPerDayBasis() != null) settings.setPerDayBasis(request.getPerDayBasis());
        if (request.getAbsenceDeductionBase() != null) settings.setAbsenceDeductionBase(request.getAbsenceDeductionBase());
        if (request.getOvertimeEnabled() != null) settings.setOvertimeEnabled(request.getOvertimeEnabled());
        if (request.getOvertimeBase() != null) settings.setOvertimeBase(request.getOvertimeBase());

        if (request.getOvertimeMultiplier() != null) {
            settings.setOvertimeMultiplier(requireRange(request.getOvertimeMultiplier(),
                    BigDecimal.ONE, new BigDecimal("5"), "Overtime multiplier"));
        }
        if (request.getStandardHoursPerDay() != null) {
            settings.setStandardHoursPerDay(requireRange(request.getStandardHoursPerDay(),
                    BigDecimal.ONE, new BigDecimal("24"), "Standard hours per day"));
        }

        if (request.getHouseRentPercent() != null) settings.setHouseRentPercent(requirePercent(request.getHouseRentPercent(), "House rent"));
        if (request.getMedicalPercent() != null) settings.setMedicalPercent(requirePercent(request.getMedicalPercent(), "Medical"));
        if (request.getTransportPercent() != null) settings.setTransportPercent(requirePercent(request.getTransportPercent(), "Transport"));
        if (request.getFoodPercent() != null) settings.setFoodPercent(requirePercent(request.getFoodPercent(), "Food"));
        if (request.getProvidentFundPercent() != null) settings.setProvidentFundPercent(requirePercent(request.getProvidentFundPercent(), "Provident fund"));
        if (request.getTaxPercent() != null) settings.setTaxPercent(requirePercent(request.getTaxPercent(), "Tax"));

        return repository.save(settings);
    }

    /**
     * What one day of the given monthly amount is worth under this company's policy.
     * @param monthlyAmount basic or gross, per {@code absenceDeductionBase}
     */
    public BigDecimal perDayRate(PayrollSettings settings, BigDecimal monthlyAmount, int payMonth, int payYear) {
        int divisor = perDayDivisor(settings, payMonth, payYear);
        if (divisor <= 0 || monthlyAmount == null) return BigDecimal.ZERO;
        return monthlyAmount.divide(BigDecimal.valueOf(divisor), 4, RoundingMode.HALF_UP);
    }

    /** The divisor itself, exposed so payslips can show how a figure was reached. */
    public int perDayDivisor(PayrollSettings settings, int payMonth, int payYear) {
        LocalDate start = LocalDate.of(payYear, payMonth, 1);
        return switch (settings.getPerDayBasis()) {
            case CALENDAR_DAYS -> start.lengthOfMonth();
            case FIXED_30 -> 30;
            case FIXED_26 -> 26;
            case ACTUAL_WORKING_DAYS -> workingDaysIn(settings.getCompanyId(), start);
        };
    }

    /**
     * Working days in the month: every date that is not a company holiday and not a Friday or Saturday.
     * The weekend is company-wide rather than per-employee shift, or two people on the same salary would get different day rates.
     * Never returns zero, so a misconfigured holiday table cannot cause a divide-by-zero.
     */
    private int workingDaysIn(Long companyId, LocalDate monthStart) {
        int days = 0;
        LocalDate end = monthStart.withDayOfMonth(monthStart.lengthOfMonth());
        for (LocalDate d = monthStart; !d.isAfter(end); d = d.plusDays(1)) {
            switch (d.getDayOfWeek()) {
                case FRIDAY, SATURDAY -> { continue; }
                default -> { }
            }
            if (companyId != null && holidayRepository.existsByCompanyIdAndDate(companyId, d)) continue;
            days++;
        }
        return Math.max(days, 1);
    }

    private BigDecimal requirePercent(BigDecimal value, String label) {
        return requireRange(value, BigDecimal.ZERO, new BigDecimal("100"), label + " percentage");
    }

    private BigDecimal requireRange(BigDecimal value, BigDecimal min, BigDecimal max, String label) {
        if (value.compareTo(min) < 0 || value.compareTo(max) > 0) {
            throw new BadRequestException(label + " must be between " + min + " and " + max + ".");
        }
        return value;
    }
}
