package com.zuhoocms.modules.servicedesk.requeststatus;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Schema-only migration: {@code request_status_history.changed_by_id} becomes nullable, because a status change the
 * platform makes itself has no signed-in user to attribute it to - the unpaid-request sweep's auto-cancellation is
 * the case that mattered, and every one of its history inserts failed on the NOT NULL until this ran.
 *
 * <p>Dropping {@code nullable = false} from the entity is not enough: {@code ddl-auto=update} never relaxes an
 * existing NOT NULL, so the live column keeps it. Also backfills {@code changed_by_name} for the rows written before
 * that column existed, so an older timeline entry still names its actor.
 *
 * <p>Idempotent: the DROP NOT NULL is skipped when the column already allows nulls, and the backfill only touches
 * rows whose name is still null.
 */
@Slf4j
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestStatusHistoryActorMigration implements ApplicationRunner {

    @PersistenceContext
    private EntityManager entityManager;

    private final TransactionTemplate tx;

    public RequestStatusHistoryActorMigration(PlatformTransactionManager transactionManager) {
        this.tx = new TransactionTemplate(transactionManager);
    }

    @Override
    public void run(ApplicationArguments args) {
        try {
            tx.executeWithoutResult(status -> migrate());
        } catch (RuntimeException ex) {
            // A failure here must not stop the application: every other status change still works, and the next
            // start retries.
            log.warn("request_status_history actor migration failed: {}", ex.getMessage());
        }
    }

    private void migrate() {
        Object notNull = entityManager.createNativeQuery("""
                SELECT a.attnotnull FROM pg_attribute a
                JOIN pg_class rel ON rel.oid = a.attrelid
                JOIN pg_namespace ns ON ns.oid = rel.relnamespace
                WHERE ns.nspname = current_schema() AND rel.relname = 'request_status_history'
                  AND a.attname = 'changed_by_id' AND a.attnum > 0 AND NOT a.attisdropped
                """).getResultStream().findFirst().orElse(null);
        // No row means the table has not been created yet; Hibernate will create the column nullable from the entity.
        if (Boolean.TRUE.equals(notNull)) {
            entityManager.createNativeQuery(
                "ALTER TABLE request_status_history ALTER COLUMN changed_by_id DROP NOT NULL").executeUpdate();
            log.info("request_status_history.changed_by_id is now nullable (system-originated status changes)");
        }

        if (notNull != null) {
            int backfilled = entityManager.createNativeQuery("""
                    UPDATE request_status_history h
                    SET changed_by_name = TRIM(CONCAT(u.first_name, ' ', u.last_name))
                    FROM users u
                    WHERE u.id = h.changed_by_id AND h.changed_by_name IS NULL
                    """).executeUpdate();
            if (backfilled > 0) {
                log.info("Backfilled changed_by_name on {} request_status_history row(s)", backfilled);
            }
        }
    }
}
