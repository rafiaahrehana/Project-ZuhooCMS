package com.zuhoocms.core.scheduler;

import com.zuhoocms.modules.dashboard.DashboardService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class PlatformMetricsScheduler implements CommandLineRunner {

    private final DashboardService dashboardService;

    /** Seeds today's snapshot on boot, so the dashboard's sparklines are not empty until the first midnight run. */
    @Override
    public void run(String... args) {
        record();
    }

    // After SubscriptionScheduler.suspendExpiredCompanies (00:05), so the snapshot reflects that job's status changes.
    @Scheduled(cron = "0 10 0 * * *")
    public void recordDailySnapshot() {
        record();
    }

    /** Two instances starting together both insert and the unique snapshot_date index rejects the second; that snapshot is redundant, so ignore it rather than fail startup. */
    private void record() {
        try {
            dashboardService.recordTodaysPlatformSnapshot();
        } catch (DataIntegrityViolationException ex) {
            log.info("Today's platform metrics snapshot was written concurrently by another instance - skipped");
        }
    }
}
