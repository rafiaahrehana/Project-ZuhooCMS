package com.zuhoocms.shared.payment.gateway;

import jakarta.persistence.EntityManager;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Creates the partial unique index on val_id so one SSLCommerz validation settles exactly one transaction; ddl-auto=update cannot express a "WHERE val_id IS NOT NULL" index.
 * Index-only and idempotent (IF NOT EXISTS); on existing duplicate val_ids the index is skipped with an error logged, and SslCommerzServiceImpl still refuses a reused val_id in code.
 */
@Slf4j
@Component
@Order(2)
@RequiredArgsConstructor
public class GatewaySchemaMigrationRunner implements ApplicationRunner {

    private final EntityManager entityManager;
    private final TransactionTemplate transactionTemplate;

    @Override
    public void run(ApplicationArguments args) {
        try {
            transactionTemplate.executeWithoutResult(status -> createPartialValIdUniqueIndex());
        } catch (RuntimeException ex) {
            log.error("Gateway schema migration: could not create uq_pgt_val_id - resolve duplicated "
                    + "val_id values in payment_gateway_transactions, then restart. Cause: {}", ex.getMessage());
        }
    }

    private void createPartialValIdUniqueIndex() {
        Number duplicates = (Number) entityManager.createNativeQuery(
                "SELECT COUNT(*) FROM (SELECT val_id FROM payment_gateway_transactions "
                        + "WHERE val_id IS NOT NULL GROUP BY val_id HAVING COUNT(*) > 1) d")
                .getSingleResult();
        if (duplicates != null && duplicates.longValue() > 0) {
            log.error("Gateway schema migration: {} val_id value(s) are shared by several transactions; "
                    + "uq_pgt_val_id not created", duplicates);
            return;
        }
        entityManager.createNativeQuery(
                "CREATE UNIQUE INDEX IF NOT EXISTS uq_pgt_val_id "
                        + "ON payment_gateway_transactions (val_id) WHERE val_id IS NOT NULL")
                .executeUpdate();
    }
}
