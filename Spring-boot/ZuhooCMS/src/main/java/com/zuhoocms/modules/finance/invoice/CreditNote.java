package com.zuhoocms.modules.finance.invoice;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/** A partial write-down against an invoice: no cash leaves the company, so unlike Refund it is issued directly with no approve/reject workflow and simply reduces what the client owes. */
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "credit_notes", uniqueConstraints = @UniqueConstraint(columnNames = {"company_id", "credit_note_number"}))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CreditNote extends BaseEntity {

    private Long companyId;

    @Column(name = "credit_note_number", nullable = false)
    private String creditNoteNumber; // CN-2026-000001

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "client_invoice_id", nullable = false)
    private ClientInvoice clientInvoice;

    @Column(nullable = false)
    private BigDecimal amount;

    private String reason;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "issued_by_user_id")
    private User issuedBy;

    private LocalDateTime issuedAt;
}
