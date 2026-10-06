package com.zuhoocms.modules.hrm.payroll.run;

import com.zuhoocms.modules.hrm.payroll.Payroll;
import com.zuhoocms.modules.hrm.payroll.PayrollRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.util.List;

/** Recomputes a run's frozen totals from its non-deleted lines; a separate bean so PayrollServiceImpl and PayrollRunService can share it without a circular dependency. */
@Component
@RequiredArgsConstructor
public class PayrollRunTotals {

    private final PayrollRepository payrollRepository;
    private final PayrollRunRepository runRepository;

    public void refresh(PayrollRun run) {
        List<Payroll> lines = payrollRepository.findByRunId(run.getId());
        BigDecimal gross = BigDecimal.ZERO, net = BigDecimal.ZERO;
        for (Payroll p : lines) {
            BigDecimal lineGross = nz(p.getBasicSalary()).add(nz(p.getHouseRent())).add(nz(p.getMedicalAllowance()))
                    .add(nz(p.getTransportAllowance())).add(nz(p.getFoodAllowance())).add(nz(p.getSpecialAllowance()))
                    .add(nz(p.getBonus())).add(nz(p.getBillablePay())).add(nz(p.getOvertimePay())).add(nz(p.getOtherEarnings()));
            gross = gross.add(lineGross);
            net = net.add(nz(p.getNetSalary()));
        }
        run.setTotalEmployees(lines.size());
        run.setTotalGross(gross);
        run.setTotalNet(net);
        run.setTotalDeduction(gross.subtract(net));
    }

    public void refreshAndSave(PayrollRun run) {
        refresh(run);
        runRepository.save(run);
    }

    private static BigDecimal nz(BigDecimal v) { return v == null ? BigDecimal.ZERO : v; }
}
