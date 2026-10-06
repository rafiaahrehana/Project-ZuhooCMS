package com.zuhoocms.modules.finance.period;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.LocalDate;

/** Closed-period check for GeneralLedgerServiceImpl, depending only on the repository: AccountingPeriodServiceImpl calls GeneralLedgerService for year-end entries, so routing through the full service would be a circular bean dependency. */
@Component
@RequiredArgsConstructor
public class PeriodLockChecker {

    private final AccountingPeriodRepository periodRepository;

    public boolean isDateInClosedPeriod(Long companyId, LocalDate date) {
        if (companyId == null || date == null) return false;
        return periodRepository.findByCompanyIdAndStartDateLessThanEqualAndEndDateGreaterThanEqual(companyId, date, date)
                .map(p -> p.getStatus() == PeriodStatus.CLOSED)
                .orElse(false);
    }
}
