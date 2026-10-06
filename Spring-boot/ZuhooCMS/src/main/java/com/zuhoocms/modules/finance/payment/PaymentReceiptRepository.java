package com.zuhoocms.modules.finance.payment;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface PaymentReceiptRepository extends JpaRepository<PaymentReceipt, Long> {
    Optional<PaymentReceipt> findByIdAndCompanyId(Long id, Long companyId);
    Page<PaymentReceipt> findByCompanyId(Long companyId, Pageable pageable);
    Page<PaymentReceipt> findByCompanyIdAndClientId(Long companyId, Long clientId, Pageable pageable);

    /** Seed for the RCP- counter (see DocumentNumberService): the highest number under this company/prefix including soft-deleted receipts - native, so BaseEntity's @SQLRestriction cannot hide one the unique constraint still counts. */
    @Query(value = """
        SELECT MAX(CASE WHEN SUBSTRING(receipt_number FROM :start) ~ '^[0-9]+$'
                        THEN CAST(SUBSTRING(receipt_number FROM :start) AS BIGINT) END)
        FROM payment_receipts
        WHERE company_id = :companyId AND receipt_number LIKE CONCAT(:prefix, '%')
        """, nativeQuery = true)
    Long findMaxReceiptSequenceIncludingDeleted(@Param("companyId") Long companyId,
                                                @Param("prefix") String prefix,
                                                @Param("start") int start);
}
