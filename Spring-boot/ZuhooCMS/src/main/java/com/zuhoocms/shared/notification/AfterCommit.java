package com.zuhoocms.shared.notification;

import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Defers side effects until commit: an @Async notification or email fired inside a @Transactional service could otherwise run before its data is visible, or be sent after a rollback.
 * Inside a transaction the action is an afterCommit callback, dropped on rollback; outside one it runs immediately.
 */
public final class AfterCommit {

    private AfterCommit() {
    }

    public static void run(Runnable action) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    action.run();
                }
            });
        } else {
            action.run();
        }
    }
}
