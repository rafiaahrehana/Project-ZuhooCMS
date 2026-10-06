package com.zuhoocms.core.scheduler;

import com.zuhoocms.auth.token.TokenRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

/**
 * Removes expired tokens; without it the tokens table grows indefinitely, since every registration, login and password reset writes rows that expire but are never cleaned up.
 * The 7-day grace period keeps recent tokens available for debugging.
 */
@Component
@RequiredArgsConstructor
@Slf4j

public class TokenCleanupScheduler {

    private final TokenRepository tokenRepository;

    private static final int GRACE_PERIOD_DAYS = 7;

    @Scheduled(cron = "0 0 3 * * *")
    @Transactional
    public void cleanExpiredTokens() {
        LocalDateTime cutoff = LocalDateTime.now().minusDays(GRACE_PERIOD_DAYS);
        tokenRepository.deleteExpiredBefore(cutoff);
        log.debug("Token cleanup: deleted tokens that expired before {}", cutoff);
    }
}
