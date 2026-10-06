package com.zuhoocms.modules.finance.generalledger;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface FinanceDocumentSequenceRepository extends JpaRepository<FinanceDocumentSequence, Long> {

    /**
     * Increments the counter and hands back the value just consumed, in one statement on the caller's own connection.
     *
     * <p>The row lock the UPDATE takes is what serialises concurrent issuers; it is held until the caller's transaction ends,
     * which is the point - no second connection is borrowed, so a document create needs one pooled connection, not two.
     * <p>Returns {@code null} when no counter row exists yet for this key; the caller then takes the create path.
     * <p>The company match has two branches because the column is nullable: {@code company_id = NULL} is never true in SQL,
     * so plain equality never finds the platform-level counter.
     */
    @Query(value = "UPDATE finance_document_sequences "
            + "SET next_value = next_value + 1 "
            + "WHERE doc_type = :docType AND year = :year "
            + "AND ((CAST(:companyId AS bigint) IS NULL AND company_id IS NULL) OR company_id = :companyId) "
            + "RETURNING next_value - 1", nativeQuery = true)
    Long bumpAndReturnIssued(@Param("companyId") Long companyId,
                             @Param("docType") String docType,
                             @Param("year") int year);

    /** Creates the counter for a key that has none yet, already advanced past the value this caller is about to use. Only ever reached under {@link #acquireSequenceLock}. */
    @Modifying
    @Query(value = "INSERT INTO finance_document_sequences (company_id, doc_type, year, next_value) "
            + "VALUES (CAST(:companyId AS bigint), :docType, :year, :nextValue)", nativeQuery = true)
    void insertCounter(@Param("companyId") Long companyId,
                       @Param("docType") String docType,
                       @Param("year") int year,
                       @Param("nextValue") long nextValue);

    /** Makes find-or-create atomic for one (company, type, year): the UPDATE above can only lock a row that exists, so the first document of a year lets two callers both find nothing and insert. Transaction-scoped, so no unlock and no leak on rollback. */
    @Query(value = "SELECT 1 FROM (SELECT pg_advisory_xact_lock(:key)) AS locked", nativeQuery = true)
    Integer acquireSequenceLock(@Param("key") long key);

}
