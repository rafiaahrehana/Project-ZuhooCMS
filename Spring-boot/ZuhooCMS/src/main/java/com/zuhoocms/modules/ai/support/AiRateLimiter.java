package com.zuhoocms.modules.ai.support;

import com.zuhoocms.modules.ai.config.AiProperties;
import com.zuhoocms.modules.ai.exception.AiQuotaExceededException;
import com.zuhoocms.modules.ai.repository.AiRateCounterRepository;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;

/**
 * Atomic AI quotas: ai.daily-company-limit per company per day, ai.hourly-user-limit per user per hour.
 * {@link #reserve} takes a slot with a conditional UPDATE before the provider call, so parallel requests cannot overshoot as counting the usage log did; a failed call still counts.
 * Each reservation commits in its own REQUIRES_NEW transaction: visible to concurrent requests at once, and holding no connection across the provider call.
 */
@Component
public class AiRateLimiter {

    private final AiRateCounterRepository counterRepository;
    private final AiProperties aiProperties;
    private final TransactionTemplate tx;

    public AiRateLimiter(AiRateCounterRepository counterRepository, AiProperties aiProperties,
                         PlatformTransactionManager transactionManager) {
        this.counterRepository = counterRepository;
        this.aiProperties = aiProperties;
        this.tx = new TransactionTemplate(transactionManager);
        this.tx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    /** Takes one request slot for this company (today) and user (this hour), or throws 429. */
    public void reserve(Long companyId, Long userId) {
        LocalDateTime now = LocalDateTime.now();
        String companyScope = "company:" + (companyId != null ? companyId : "platform");
        LocalDateTime day = LocalDate.now().atStartOfDay();
        String userScope = "user:" + userId;
        LocalDateTime hour = now.truncatedTo(ChronoUnit.HOURS);

        int companyLimit = aiProperties.getDailyCompanyLimit();
        if (!take(companyScope, day, companyLimit)) {
            throw new AiQuotaExceededException(
                "Daily AI request limit reached for this company (" + companyLimit
                    + "/day). Try again tomorrow.");
        }

        int userLimit = aiProperties.getHourlyUserLimit();
        if (!take(userScope, hour, userLimit)) {
            // The company slot was taken for a call that will not happen - give it back.
            tx.executeWithoutResult(s -> counterRepository.decrement(companyScope, day));
            throw new AiQuotaExceededException(
                "Hourly AI request limit reached for your account (" + userLimit
                    + "/hour). Try again shortly.");
        }
    }

    private boolean take(String scope, LocalDateTime window, int limit) {
        Integer updated = tx.execute(s -> {
            counterRepository.ensureRow(scope, window);
            return counterRepository.tryIncrement(scope, window, limit);
        });
        return updated != null && updated == 1;
    }
}
