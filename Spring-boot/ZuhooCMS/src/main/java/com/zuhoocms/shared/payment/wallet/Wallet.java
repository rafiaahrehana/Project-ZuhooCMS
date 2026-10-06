package com.zuhoocms.shared.payment.wallet;

import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;

// No tenant @Filter on purpose: Wallet has no company_id column, so scoping goes through contextType/contextId (see WalletServiceImpl).
@Entity
@Table(name = "wallets")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Wallet extends BaseEntity {

    @Builder.Default
    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal balance = BigDecimal.ZERO;

    // Promotional / trial credit balance — separate from real cash balance.
    @Builder.Default
    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal creditBalance = BigDecimal.ZERO;

    @Builder.Default
    private String currency = "BDT";

    @Column(name = "context_type", nullable = false)
    private String contextType; // PLATFORM, COMPANY, CLIENT

    @Column(name = "context_id", nullable = false)
    private Long contextId;

    // Total spendable amount = cash balance + credit balance.
    public BigDecimal getTotalAvailable() {
        BigDecimal b = balance      != null ? balance      : BigDecimal.ZERO;
        BigDecimal c = creditBalance != null ? creditBalance : BigDecimal.ZERO;
        return b.add(c);
    }
}
