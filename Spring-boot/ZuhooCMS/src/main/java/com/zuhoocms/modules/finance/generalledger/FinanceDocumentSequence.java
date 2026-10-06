package com.zuhoocms.modules.finance.generalledger;

import jakarta.persistence.*;
import lombok.*;

/**
 * One monotonically increasing counter per (company, document type, year).
 *
 * <p>Replaces {@code MAX(number) + 1} read inside the inserting transaction, under which two simultaneous creators built the same number and either collided or produced two documents sharing one number.
 * The counter is locked, read and incremented in a short dedicated transaction (see {@link DocumentNumberService}).
 * <p>Deliberately not a {@code BaseEntity}: BaseEntity's {@code @SQLRestriction("deleted = false")} would filter the counter row out of the {@code SELECT ... FOR UPDATE} that must find it.
 */
@Entity
@Table(name = "finance_document_sequences", uniqueConstraints = {
        @UniqueConstraint(name = "uk_finance_doc_seq", columnNames = {"company_id", "doc_type", "year"})
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class FinanceDocumentSequence {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Owning tenant, nullable on purpose: platform-level documents get their own counter under a NULL company, as the documents themselves do. */
    @Column(name = "company_id")
    private Long companyId;

    /** Document family this counter serves - see the constants on {@link DocumentNumberService}. */
    @Column(name = "doc_type", nullable = false, length = 50)
    private String docType;

    /** Calendar year from the document's own date rather than today, so a back-dated document draws from the year it is dated in. */
    @Column(name = "year", nullable = false)
    private int year;

    /** The next number to hand out; incremented every time one is issued. */
    @Column(name = "next_value", nullable = false)
    private long nextValue;
}
