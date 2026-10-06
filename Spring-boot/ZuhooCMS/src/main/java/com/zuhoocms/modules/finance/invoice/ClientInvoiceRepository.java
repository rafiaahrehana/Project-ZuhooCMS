package com.zuhoocms.modules.finance.invoice;

import com.zuhoocms.enums.InvoiceStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

public interface ClientInvoiceRepository extends JpaRepository<ClientInvoice, Long> {

    Optional<ClientInvoice> findByInvoiceNumber(String invoiceNumber);

    Optional<ClientInvoice> findByCompanyIdAndInvoiceNumber(Long companyId, String invoiceNumber);

    Optional<ClientInvoice> findByIdAndCompanyId(Long id, Long companyId);

    @EntityGraph(attributePaths = {"client"})
    Page<ClientInvoice> findByCompanyId(Long companyId, Pageable pageable);

    /** Invoices for one company in a date window with the client joined in: the finance dashboard reads a client name per row, which otherwise triggers a select per row. */
    @EntityGraph(attributePaths = {"client"})
    List<ClientInvoice> findByCompanyIdAndInvoiceDateBetween(Long companyId, java.time.LocalDate start, java.time.LocalDate end);

    @EntityGraph(attributePaths = {"client"})
    Page<ClientInvoice> findByCompanyIdAndStatus(Long companyId, InvoiceStatus status, Pageable pageable);

    @EntityGraph(attributePaths = {"client"})
    Page<ClientInvoice> findByCompanyIdAndClientId(Long companyId, Long clientId, Pageable pageable);

    long countByCompanyId(Long companyId);

    long countByCompanyIdAndStatus(Long companyId, InvoiceStatus status);

    Page<ClientInvoice> findByCompanyIdAndInvoiceNumberContainingIgnoreCase(Long companyId, String keyword, Pageable pageable);

    /**
     * Seed for the INV- number counter (see DocumentNumberService): the highest running number under this company/prefix, <b>soft-deleted rows included</b>.
     * Native on purpose - JPQL MAX goes through BaseEntity's {@code @SQLRestriction("deleted = false")}, so a deleted highest draft vanished from MAX while the (company_id, invoice_number) unique constraint still counted it.
     * Parsed numerically so a number widening past six digits still sorts right.
     */
    @Query(value = """
        SELECT MAX(CASE WHEN SUBSTRING(invoice_number FROM :start) ~ '^[0-9]+$'
                        THEN CAST(SUBSTRING(invoice_number FROM :start) AS BIGINT) END)
        FROM client_invoices
        WHERE company_id = :companyId AND invoice_number LIKE CONCAT(:prefix, '%')
        """, nativeQuery = true)
    Long findMaxInvoiceSequenceIncludingDeleted(
        @Param("companyId") Long companyId,
        @Param("prefix") String prefix,
        @Param("start") int start
    );

    /** All overdue invoices for a company: due date passed, not yet paid/cancelled. */
    @Query("""
        SELECT i FROM ClientInvoice i
        WHERE i.companyId = :companyId
          AND i.dueDate < CURRENT_DATE
          AND i.status NOT IN :excludedStatuses
          AND i.deleted = false
        """)
    List<ClientInvoice> findOverdueInvoices(
        @Param("companyId") Long companyId,
        @Param("excludedStatuses") List<InvoiceStatus> excludedStatuses
    );

    @Query("SELECT SUM(i.balanceAmount) FROM ClientInvoice i WHERE i.companyId = :companyId AND i.status IN :statuses AND i.deleted = false")
    Optional<BigDecimal> sumOutstandingByCompanyId(
        @Param("companyId") Long companyId,
        @Param("statuses") List<InvoiceStatus> statuses
    );

    @Query("SELECT SUM(i.balanceAmount) FROM ClientInvoice i WHERE i.companyId = :companyId AND i.client.id = :clientId AND i.status IN :statuses AND i.deleted = false")
    Optional<BigDecimal> sumOutstandingByCompanyIdAndClientId(
        @Param("companyId") Long companyId,
        @Param("clientId") Long clientId,
        @Param("statuses") List<InvoiceStatus> statuses
    );

    long countByCompanyIdAndClientIdAndStatusIn(Long companyId, Long clientId, List<InvoiceStatus> statuses);

    // No bulk "UPDATE ... SET status = OVERDUE" here: it had no deleted filter, bypassed @Version and could overwrite a just-committed payment, and hit a different row set than findNewlyOverdue() read for notifications.

    /** Invoices past due and still in one of the given open statuses; InvoiceOverdueScheduler marks exactly these OVERDUE and notifies once each. */
    @Query("SELECT i FROM ClientInvoice i WHERE i.dueDate < :currentDate AND i.status IN :oldStatuses AND i.deleted = false")
    List<ClientInvoice> findNewlyOverdue(
        @Param("currentDate") java.time.LocalDate currentDate,
        @Param("oldStatuses") List<InvoiceStatus> oldStatuses
    );

    /** Used by the AR Aging report - anything still owed, regardless of how overdue. */
    @EntityGraph(attributePaths = {"client"})
    @Query("""
        SELECT i FROM ClientInvoice i
        WHERE i.companyId = :companyId
          AND i.status IN :outstandingStatuses
          AND i.balanceAmount > 0
          AND i.deleted = false
        """)
    List<ClientInvoice> findOutstandingByCompanyId(
        @Param("companyId") Long companyId,
        @Param("outstandingStatuses") List<InvoiceStatus> outstandingStatuses
    );
}
