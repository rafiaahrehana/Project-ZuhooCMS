package com.zuhoocms.modules.finance.invoice;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface CreditNoteRepository extends JpaRepository<CreditNote, Long> {

    Page<CreditNote> findByCompanyId(Long companyId, Pageable pageable);

    Page<CreditNote> findByCompanyIdAndClientInvoiceId(Long companyId, Long clientInvoiceId, Pageable pageable);

    Optional<CreditNote> findByIdAndCompanyId(Long id, Long companyId);

    /** Seed for the CN- counter: the highest number under this company/prefix including soft-deleted rows - native, so @SQLRestriction cannot hide one the unique constraint still counts. */
    @Query(value = """
        SELECT MAX(CASE WHEN SUBSTRING(credit_note_number FROM :start) ~ '^[0-9]+$'
                        THEN CAST(SUBSTRING(credit_note_number FROM :start) AS BIGINT) END)
        FROM credit_notes
        WHERE company_id = :companyId AND credit_note_number LIKE CONCAT(:prefix, '%')
        """, nativeQuery = true)
    Long findMaxCreditNoteSequenceIncludingDeleted(
        @Param("companyId") Long companyId,
        @Param("prefix") String prefix,
        @Param("start") int start
    );
}
