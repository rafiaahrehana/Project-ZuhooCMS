package com.zuhoocms.modules.finance.invoice;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.enums.RefundStatus;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "refunds")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Refund extends BaseEntity {

    private Long companyId;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "client_invoice_id", nullable = false)
    private ClientInvoice clientInvoice;

    @Column(nullable = false)
    private BigDecimal requestedAmount;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private RefundStatus status = RefundStatus.REQUESTED;

    private String reason;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "processed_by_user_id")
    private User processedBy;

    private LocalDateTime processedAt;

    private String rejectionReason;

    /** true = credited to the company wallet as REFUND_CREDIT, false/null = paid out externally and only recorded; nullable so ddl-auto can add it to existing rows, which all predate wallet refunds. */
    @org.hibernate.annotations.ColumnDefault("false")
    @Column(name = "refund_to_wallet")
    private Boolean refundToWallet;
}
