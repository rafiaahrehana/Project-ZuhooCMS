package com.zuhoocms.core.scheduler;

import com.zuhoocms.modules.hrm.announcement.AnnouncementService;
import lombok.RequiredArgsConstructor;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Publishes on Announcement.scheduledAt, which nothing acted on before; every 15 minutes, since a 9am announcement landing at 9:45 defeats the point. */
@Component
@RequiredArgsConstructor
public class AnnouncementScheduledPublishScheduler {

    private final AnnouncementService announcementService;

    @Scheduled(cron = "0 */15 * * * *")
    public void publishDue() {
        announcementService.publishDueScheduled();
    }
}
