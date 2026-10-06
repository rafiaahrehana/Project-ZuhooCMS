package com.zuhoocms.modules.company;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.enums.CompanyStatus;
import com.zuhoocms.shared.address.Address;
import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "companies")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Company extends BaseEntity {

    @Column(nullable = false)
    private String companyName;

    @Column(unique = true)
    private String companyEmail;

    @Column(unique = true)
    private String companyPhone;

    private String website;

    @Column(nullable = false, unique = true)
    private String subdomain;

    @OneToOne(cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @JoinColumn(name = "address_detail_id")
    private Address locationDetail;

    @Column(columnDefinition = "TEXT")
    private String portalAbout;

    // Shown on invoice PDFs so clients receive a legally usable invoice.
    private String taxRegistrationNumber; // VAT/BIN/TIN etc.
    private String bankName;
    private String bankAccountName;
    private String bankAccountNumber;
    private String bankBranch;

    // Calendar month the fiscal year starts in (1=January); drives how AccountingPeriod months are numbered and dated.
    @Builder.Default
    private Integer fiscalYearStartMonth = 1;

    // The single currency the General Ledger books in; foreign-currency invoices post converted amounts - see ClientInvoiceServiceImpl#toBase.
    @Builder.Default
    @Column(length = 10)
    private String baseCurrency = "BDT";

    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "owner_id", nullable = false)
    private User owner;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    @Builder.Default
    private CompanyStatus status = CompanyStatus.PENDING_VERIFICATION;

    // References SubscriptionPlanDefinition.code as a plain String, not a FK/enum, so Super Admin can add plan codes at runtime.
    // Legacy rows hold "FREE"/"STARTER"/"PRO"/"ENTERPRISE", seeded as catalog rows by SubscriptionPlanCatalogSeeder.
    @Column(nullable = false)
    @Builder.Default
    private String subscriptionPlan = "FREE";

    @Builder.Default
    private boolean active = false;
    @Builder.Default
    private boolean emailVerified = false;
    @Builder.Default
    private boolean trialReminderSent = false;

    private LocalDate subscriptionStart;
    private LocalDate subscriptionEnd;

    private LocalDateTime trialReminderSentAt;

    @Builder.Default
    private boolean isPlatformTenant = false;

    public boolean isTrialExpired() {
        if (this.isPlatformTenant) return false;
        // A TRIAL with no end date never verified its email (verifyEmail() starts the window), so it is expired, not endless; the demo is exempted by its callers.
        if (status == CompanyStatus.TRIAL && subscriptionEnd == null) return true;
        return subscriptionEnd != null && subscriptionEnd.isBefore(LocalDate.now());
    }
}
