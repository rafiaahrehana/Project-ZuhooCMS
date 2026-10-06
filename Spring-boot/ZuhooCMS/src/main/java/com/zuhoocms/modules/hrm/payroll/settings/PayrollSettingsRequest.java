package com.zuhoocms.modules.hrm.payroll.settings;

import com.zuhoocms.enums.PerDayBasis;
import com.zuhoocms.enums.SalaryBase;
import lombok.Data;

import java.math.BigDecimal;

/** Every field is nullable and applied only when present, so a partial update does not wipe fields the page did not render. */
@Data
public class PayrollSettingsRequest {

    private PerDayBasis perDayBasis;
    private SalaryBase absenceDeductionBase;

    private Boolean overtimeEnabled;
    private BigDecimal overtimeMultiplier;
    private SalaryBase overtimeBase;
    private BigDecimal standardHoursPerDay;

    private BigDecimal houseRentPercent;
    private BigDecimal medicalPercent;
    private BigDecimal transportPercent;
    private BigDecimal foodPercent;
    private BigDecimal providentFundPercent;
    private BigDecimal taxPercent;
}
