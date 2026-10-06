package com.zuhoocms.modules.finance.vendor;

import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

/** A supplier the company buys from: the master record Accounts Payable needs, replacing the free-text vendor string on Expense under which two spellings were unrelated. */
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "vendors", uniqueConstraints = @UniqueConstraint(columnNames = {"company_id", "name"}))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Vendor extends BaseEntity {

    private Long companyId;

    @Column(nullable = false)
    private String name;

    private String contactPerson;
    private String email;
    private String phone;
    private String taxId;
    private String address;

    // Free text like "NET_30" / "Due on receipt" - informational for now
    private String paymentTerms;

    @Column(columnDefinition = "TEXT")
    private String notes;

    @Builder.Default
    private boolean active = true;
}
