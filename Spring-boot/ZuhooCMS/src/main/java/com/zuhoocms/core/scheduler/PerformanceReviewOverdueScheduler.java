package com.zuhoocms.core.scheduler;

import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.modules.hrm.performance.PerformanceReview;
import com.zuhoocms.modules.hrm.performance.PerformanceReviewRepository;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/** Flags a PerformanceReview.reviewPeriodEnd that passed with the review still not finalised; nothing else in the app tracks that. */
@Component
@RequiredArgsConstructor
public class PerformanceReviewOverdueScheduler {

    // Grace period so the manager has time to conduct the review before being flagged.
    private static final int GRACE_DAYS = 14;

    private final PerformanceReviewRepository reviewRepository;
    private final NotificationService notificationService;

    @Scheduled(cron = "0 0 8 * * *")
    @Transactional
    public void remindOverdueReviews() {
        LocalDate cutoff = LocalDate.now().minusDays(GRACE_DAYS);

        List<PerformanceReview> overdue = reviewRepository.findNewlyOverdue(cutoff);
        for (PerformanceReview review : overdue) {
            review.setOverdueReminderSentAt(LocalDateTime.now());

            if (review.getReviewedBy() == null || review.getReviewedBy().getUser() == null) continue;

            notificationService.send(CreateNotificationRequest.of(
                    NotificationType.PERFORMANCE_REVIEW_OVERDUE,
                    "Performance review overdue",
                    review.getEmployee().getFullName() + "'s review period ended "
                            + review.getReviewPeriodEnd() + " and it still isn't finalised.",
                    "/hrm/performance/" + review.getId(),
                    review.getReviewedBy().getUser().getId(),
                    review.getCompany().getId()));
        }
    }
}
