package com.zuhoocms.core.interceptor;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.hibernate.Session;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.function.Supplier;

/**
 * Read-only work with Hibernate's {@code tenantFilter} off, for public endpoints that address a tenant explicitly: a user of company A browsing company B's website otherwise got B's rows filtered down to A's.
 * The work passed here must constrain company_id itself, and REQUIRES_NEW keeps the disabled filter out of a caller's transaction.
 */
@Component
public class UnfilteredReads {

    private final TransactionTemplate tx;

    @PersistenceContext
    private EntityManager entityManager;

    public UnfilteredReads(PlatformTransactionManager transactionManager) {
        this.tx = new TransactionTemplate(transactionManager);
        this.tx.setReadOnly(true);
        this.tx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    public <T> T run(Supplier<T> work) {
        return tx.execute(status -> {
            Session session = entityManager.unwrap(Session.class);
            if (session.getEnabledFilter(TenantFilterInterceptor.FILTER_NAME) != null) {
                session.disableFilter(TenantFilterInterceptor.FILTER_NAME);
            }
            return work.get();
        });
    }
}
