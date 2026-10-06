package com.zuhoocms.modules.support.contextswitch;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.util.List;

/** Ends switches left active over 8 hours, or an agent who forgets to click "End" appears to view that company indefinitely; each ends in its own transaction so one failure never rolls back the rest. */
@Slf4j
@Component
@RequiredArgsConstructor
public class SupportContextSwitchExpiryScheduler {

    static final long MAX_ACTIVE_HOURS = 8;

    private final SupportContextSwitchService contextSwitchService;

    /** Lets a local verification run start the app without these jobs touching existing rows. */
    @Value("${app.support.schedulers.enabled:true}")
    private boolean enabled;

    @Scheduled(cron = "0 */15 * * * *")
    public void expireStaleSwitches() {
        if (!enabled) return;
        LocalDateTime cutoff = LocalDateTime.now().minusHours(MAX_ACTIVE_HOURS);
        List<Long> ids = contextSwitchService.findStaleActiveIds(cutoff);
        int expired = 0;
        for (Long id : ids) {
            try {
                if (contextSwitchService.expireIfStale(id, cutoff)) expired++;
            } catch (RuntimeException ex) {
                log.warn("Could not auto-expire context switch {}: {}", id, ex.getMessage());
            }
        }
        if (expired > 0) {
            log.info("Auto-expired {} support context switch(es) older than {}h", expired, MAX_ACTIVE_HOURS);
        }
    }
}
