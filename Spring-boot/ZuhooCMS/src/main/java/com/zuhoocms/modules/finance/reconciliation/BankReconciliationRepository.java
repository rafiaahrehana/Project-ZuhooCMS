package com.zuhoocms.modules.finance.reconciliation;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

@Repository
public interface BankReconciliationRepository extends JpaRepository<BankReconciliation, Long> {

    Optional<BankReconciliation> findByIdAndCompanyId(Long id, Long companyId);

    Page<BankReconciliation> findByCompanyId(Long companyId, Pageable pageable);

    List<BankReconciliation> findByCompanyIdAndReconciledFalse(Long companyId);

    /**
     * Matches on the exact day a pending reconciliation crosses the overdue threshold, so it is flagged once rather than every day.
     *
     * @deprecated an exact-day match loses the reminder whenever a run is skipped (app down, weekend, cron changed). Use
     * {@link #findByCompanyIdAndReconciledFalseAndOverdueNotifiedAtIsNullAndReconciliationDateLessThanEqual},
     * which catches the whole backlog and de-duplicates on overdueNotifiedAt.
     */
    @Deprecated
    List<BankReconciliation> findByCompanyIdAndReconciledFalseAndReconciliationDate(Long companyId, LocalDate reconciliationDate);

    /** Every still-open reconciliation past the overdue threshold with no reminder sent: catches the whole backlog while overdueNotifiedAt keeps it to one reminder each. */
    List<BankReconciliation> findByCompanyIdAndReconciledFalseAndOverdueNotifiedAtIsNullAndReconciliationDateLessThanEqual(
            Long companyId, LocalDate threshold);

    /** Guards "one open reconciliation per bank account": two sessions on the same account each clear a different subset of the same GL lines and neither reaches a zero difference. */
    Optional<BankReconciliation> findFirstByCompanyIdAndBankAccountIdAndReconciledFalse(Long companyId, Long bankAccountId);
}
