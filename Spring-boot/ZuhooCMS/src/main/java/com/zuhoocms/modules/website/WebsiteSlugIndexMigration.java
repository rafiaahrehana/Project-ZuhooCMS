package com.zuhoocms.modules.website;

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

import java.util.List;

/**
 * Schema-only migration: website slugs become unique per company, since a global UNIQUE (slug) made the second company's "about" page a constraint violation.
 * Dropping {@code unique} from the entity is not enough because {@code ddl-auto=update} never drops a constraint, so this drops the old UNIQUE (slug) and creates partial unique indexes on (company_id, slug).
 * Idempotent and touches no row data: the indexes use IF NOT EXISTS.
 */
@Slf4j
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class WebsiteSlugIndexMigration implements ApplicationRunner {

    private static final List<String> TABLES = List.of("website_content", "website_services");

    @PersistenceContext
    private EntityManager entityManager;

    private final TransactionTemplate tx;

    public WebsiteSlugIndexMigration(PlatformTransactionManager transactionManager) {
        this.tx = new TransactionTemplate(transactionManager);
    }

    @Override
    public void run(ApplicationArguments args) {
        for (String table : TABLES) {
            try {
                tx.executeWithoutResult(status -> migrate(table));
            } catch (RuntimeException ex) {
                log.warn("Slug index migration for {} failed: {}", table, ex.getMessage());
            }
        }
    }

    private void migrate(String table) {
        @SuppressWarnings("unchecked")
        List<String> globalSlugConstraints = entityManager.createNativeQuery("""
                SELECT con.conname FROM pg_constraint con
                JOIN pg_class rel ON rel.oid = con.conrelid
                JOIN pg_namespace ns ON ns.oid = rel.relnamespace
                WHERE ns.nspname = current_schema() AND rel.relname = :table AND con.contype = 'u'
                  AND array_length(con.conkey, 1) = 1
                  AND con.conkey[1] = (SELECT a.attnum FROM pg_attribute a
                                       WHERE a.attrelid = rel.oid AND a.attname = 'slug')
                """).setParameter("table", table).getResultList();
        for (String name : globalSlugConstraints) {
            String ddl = "ALTER TABLE " + table + " DROP CONSTRAINT IF EXISTS \"" + name.replace("\"", "") + "\"";
            entityManager.createNativeQuery(ddl).executeUpdate();
            log.info("Website slug migration: {}", ddl);
        }
        String index = "ux_" + table + "_company_slug";
        String ddl = "CREATE UNIQUE INDEX IF NOT EXISTS " + index + " ON " + table
                + " (company_id, slug) WHERE deleted = false";
        entityManager.createNativeQuery(ddl).executeUpdate();
        if (!globalSlugConstraints.isEmpty()) {
            log.info("Website slug migration: {}", ddl);
        }
    }
}
