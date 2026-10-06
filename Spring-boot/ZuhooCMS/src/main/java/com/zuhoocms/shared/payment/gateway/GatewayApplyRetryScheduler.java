package com.zuhoocms.shared.payment.gateway;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Retries confirmed charges left unapplied by the callback (SUCCESS, applied = false) - the money has been taken, so the fact is never dropped.
 * After {@link #MAX_ATTEMPTS} a row stops being retried and keeps its last error for staff to resolve by hand.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class GatewayApplyRetryScheduler {

    static final int MAX_ATTEMPTS = 10;
    private static final int BATCH = 50;

    private final PaymentGatewayTransactionRepository transactionRepository;
    private final SslCommerzService sslCommerzService;

    /** Every 10 minutes, first run 5 minutes after startup. */
    @Scheduled(fixedDelay = 600_000L, initialDelay = 300_000L)
    public void retryUnappliedCharges() {
        List<String> tranIds = transactionRepository.findUnappliedTranIds(MAX_ATTEMPTS, PageRequest.of(0, BATCH));
        for (String tranId : tranIds) {
            try {
                if (sslCommerzService.applyConfirmedTransaction(tranId)) {
                    log.info("Gateway retry: applied previously unapplied charge {}", tranId);
                }
            } catch (Exception e) {
                // applyConfirmedTransaction records its own failures; never let one row stop the batch.
                log.warn("Gateway retry: {} failed again: {}", tranId, e.getMessage());
            }
        }
    }
}
