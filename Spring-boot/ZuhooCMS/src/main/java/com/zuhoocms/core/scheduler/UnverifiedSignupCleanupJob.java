package com.zuhoocms.core.scheduler;

import com.zuhoocms.auth.token.TokenRepository;
import com.zuhoocms.auth.token.TokenType;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.enums.CompanyStatus;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Disables self sign-ups unverified for {@code app.registration.cleanup.max-age-days} (default 7): owner deactivated, tokens revoked, company DEACTIVATED.
 * Subdomain and emails are released by renaming them {@code <value>#unverified-<id>}, a value no validated input can produce; nothing is deleted, so an admin can restore one.
 * {@code app.registration.cleanup.enabled} turns the job off; {@code app.registration.cleanup.run-on-startup} also runs it once at boot.
 */
@Slf4j
@Component
public class UnverifiedSignupCleanupJob {

    private final CompanyRepository companyRepository;
    private final TokenRepository tokenRepository;
    private final TransactionTemplate tx;

    @Value("${app.registration.cleanup.enabled:true}")
    private boolean enabled;

    @Value("${app.registration.cleanup.max-age-days:7}")
    private int maxAgeDays;

    @Value("${app.registration.cleanup.run-on-startup:false}")
    private boolean runOnStartup;

    public UnverifiedSignupCleanupJob(CompanyRepository companyRepository, TokenRepository tokenRepository,
                                      PlatformTransactionManager transactionManager) {
        this.companyRepository = companyRepository;
        this.tokenRepository = tokenRepository;
        this.tx = new TransactionTemplate(transactionManager);
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onStartup() {
        if (runOnStartup) {
            run();
        }
    }

    @Scheduled(cron = "0 20 0 * * *")
    public void scheduled() {
        run();
    }

    /** Returns how many sign-ups were disabled. */
    public int run() {
        if (!enabled) {
            log.info("Unverified sign-up cleanup is disabled (app.registration.cleanup.enabled=false)");
            return 0;
        }
        Integer count = tx.execute(status -> {
            List<Company> stale = companyRepository.findStaleUnverifiedSignups(
                    LocalDateTime.now().minusDays(maxAgeDays),
                    List.of(CompanyStatus.TRIAL, CompanyStatus.PENDING_VERIFICATION));
            for (Company company : stale) {
                User owner = company.getOwner();
                String suffix = "#unverified-";
                owner.setActive(false);
                owner.setEmail(owner.getEmail() + suffix + owner.getId());
                company.setStatus(CompanyStatus.DEACTIVATED);
                company.setActive(false);
                company.setSubdomain(company.getSubdomain() + suffix + company.getId());
                if (company.getCompanyEmail() != null) {
                    company.setCompanyEmail(company.getCompanyEmail() + suffix + company.getId());
                }
                tokenRepository.revokeAllByUserIdAndType(owner.getId(), TokenType.REFRESH);
                log.info("Disabled unverified sign-up: company {} ({}), owner user {}",
                        company.getId(), company.getCompanyName(), owner.getId());
            }
            return stale.size();
        });
        int n = count == null ? 0 : count;
        log.info("Unverified sign-up cleanup: {} sign-up(s) older than {} days disabled", n, maxAgeDays);
        return n;
    }
}
