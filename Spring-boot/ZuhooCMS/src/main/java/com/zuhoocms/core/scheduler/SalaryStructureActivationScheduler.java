package com.zuhoocms.core.scheduler;

import com.zuhoocms.modules.hrm.salary.SalaryStructureService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Copies a future-dated salary structure onto the employee profile once its effectiveFrom arrives, rather than at creation time.
 * Cross-tenant: a @Scheduled method has no authenticated user, so the tenant filter is not active.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class SalaryStructureActivationScheduler {

    private final SalaryStructureService salaryStructureService;

    @Scheduled(cron = "0 5 0 * * *")
    public void applyDueStructures() {
        try {
            salaryStructureService.applyDueStructures();
        } catch (Exception ex) {
            log.error("Salary structure activation sweep failed", ex);
        }
    }
}
