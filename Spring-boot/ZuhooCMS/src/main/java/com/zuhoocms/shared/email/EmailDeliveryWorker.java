package com.zuhoocms.shared.email;

import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.shared.exception.InternalServerException;
import com.zuhoocms.shared.notification.NotificationPreferenceRepository;
import jakarta.mail.internet.MimeMessage;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;

/** SMTP work for EmailServiceImpl with an email_logs row per message; a separate bean so the calls go through the @Async proxy. */
@Component
@Slf4j
public class EmailDeliveryWorker {

    static final int MAX_ATTEMPTS = 3;
    /** Wait before attempt 2 and attempt 3. */
    private static final long[] BACKOFF_MS = {2_000L, 10_000L};
    private static final int MAX_COLUMN = 255;

    private final JavaMailSender mailSender;
    private final EmailLogRepository emailLogRepository;
    private final UserRepository userRepository;
    private final NotificationPreferenceRepository preferenceRepository;
    private final String from;

    public EmailDeliveryWorker(JavaMailSender mailSender,
                               EmailLogRepository emailLogRepository,
                               UserRepository userRepository,
                               NotificationPreferenceRepository preferenceRepository,
                               @Value("${spring.mail.username}") String from) {
        this.mailSender = mailSender;
        this.emailLogRepository = emailLogRepository;
        this.userRepository = userRepository;
        this.preferenceRepository = preferenceRepository;
        this.from = from;
    }

    /** Fire-and-forget delivery with retries. Never throws. */
    @Async
    public void deliverAsync(String to, String subject, String html, String templateName,
                             Long companyId, EmailPreference preference) {
        try {
            if (to == null || to.isBlank()) {
                log.warn("Email '{}' skipped: no recipient address", templateName);
                return;
            }
            if (!allowedByPreferences(to, preference)) {
                log.debug("Email '{}' to {} suppressed by notification preferences", templateName, to);
                return;
            }
            deliver(to, subject, html, templateName, companyId, MAX_ATTEMPTS);
        } catch (Exception e) {
            log.error("Email '{}' to {} failed: {}", templateName, to, e.getMessage());
        }
    }

    /** Synchronous single attempt, no silent retries, for callers that must report the outcome; throws InternalServerException on failure. */
    public void deliverNow(String to, String subject, String html, String templateName, Long companyId) {
        if (to == null || to.isBlank()) {
            throw new InternalServerException("Email delivery failed");
        }
        if (!deliver(to, subject, html, templateName, companyId, 1)) {
            throw new InternalServerException("Email delivery failed");
        }
    }

    private boolean allowedByPreferences(String to, EmailPreference preference) {
        if (preference == null || preference == EmailPreference.ALWAYS) {
            return true;
        }
        try {
            return userRepository.findByEmail(to.trim())
                    .flatMap(user -> preferenceRepository.findByUserId(user.getId()))
                    .map(preference::allows)
                    .orElse(true); // unknown address or no preference row = defaults = send
        } catch (Exception e) {
            // Never lose an email because the preference lookup failed.
            log.debug("Preference lookup failed for {}: {}", to, e.getMessage());
            return true;
        }
    }

    private boolean deliver(String to, String subject, String html, String templateName,
                            Long companyId, int maxAttempts) {
        Company company = null;
        if (companyId != null) {
            company = new Company();
            company.setId(companyId);
        }

        EmailLog emailLog = emailLogRepository.save(EmailLog.builder()
                .recipient(truncate(to))
                .subject(truncate(subject == null ? "" : subject))
                .template(truncate(templateName == null ? "Custom" : templateName))
                .company(company)
                .sentTime(LocalDateTime.now())
                .status("PENDING")
                .build());

        Exception lastError = null;
        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
            try {
                MimeMessage message = mailSender.createMimeMessage();
                MimeMessageHelper helper = new MimeMessageHelper(message, true);
                helper.setFrom(from);
                helper.setTo(to);
                helper.setSubject(subject == null ? "" : subject);
                helper.setText(html == null ? "" : html, true);
                mailSender.send(message);

                emailLog.setStatus("SUCCESS");
                emailLog.setFailureReason(null);
                emailLogRepository.save(emailLog);
                return true;
            } catch (Exception e) {
                lastError = e;
                log.warn("Email '{}' to {} failed (attempt {}/{}): {}",
                        templateName, to, attempt, maxAttempts, e.getMessage());
                if (attempt < maxAttempts) {
                    emailLog.setRetryCount(emailLog.getRetryCount() + 1);
                    emailLog.setFailureReason(truncate(reasonOf(e)));
                    emailLog = emailLogRepository.save(emailLog);
                    if (!sleep(BACKOFF_MS[Math.min(attempt - 1, BACKOFF_MS.length - 1)])) {
                        break;
                    }
                }
            }
        }

        emailLog.setStatus("FAILED");
        emailLog.setFailureReason(truncate(reasonOf(lastError)));
        emailLogRepository.save(emailLog);
        return false;
    }

    private static boolean sleep(long millis) {
        try {
            Thread.sleep(millis);
            return true;
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
            return false;
        }
    }

    private static String reasonOf(Exception e) {
        if (e == null) {
            return "Unknown error";
        }
        String msg = e.getMessage();
        return (msg == null || msg.isBlank()) ? e.getClass().getSimpleName() : msg;
    }

    private static String truncate(String value) {
        if (value == null) {
            return null;
        }
        return value.length() <= MAX_COLUMN ? value : value.substring(0, MAX_COLUMN);
    }
}
