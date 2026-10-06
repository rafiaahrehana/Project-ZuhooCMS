package com.zuhoocms.modules.ai.support;

import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.function.Supplier;

/**
 * Splits an AI-backed service method into transactions that end before the provider call: an AI request can block ~31s, and a transaction spanning it would hold its pooled JDBC connection and drain the pool.
 * Callers read inside {@link #load} (commits on return), call the provider with no transaction open, then write through {@link #persist}.
 * Own templates rather than the auto-configured TransactionTemplate bean, so readOnly can differ per phase and by-type injection in AssetImportServiceImpl stays unambiguous.
 * Entities returned by load are detached once it commits - build the DTO and read lazy associations inside the callback.
 */
@Component
public class AiTransactionBoundary {

    private final TransactionTemplate readOnly;
    private final TransactionTemplate readWrite;

    public AiTransactionBoundary(PlatformTransactionManager transactionManager) {
        this.readOnly = new TransactionTemplate(transactionManager);
        // Hibernate keeps FlushMode.MANUAL, so nothing accidentally dirtied while assembling a prompt gets written back.
        this.readOnly.setReadOnly(true);

        this.readWrite = new TransactionTemplate(transactionManager);
    }

    /** Reads entities and assembles a prompt; commits before returning. */
    public <T> T load(Supplier<T> work) {
        return readOnly.execute(status -> work.get());
    }

    /** Persists the outcome of an AI call in a fresh read-write transaction. */
    public <T> T persist(Supplier<T> work) {
        return readWrite.execute(status -> work.get());
    }
}
