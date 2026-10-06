package com.zuhoocms.modules.servicedesk.proposal;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.company.Company;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

// Sales material (mockups, diagrams), kept separate from the Document/checklist mechanism, which is for compliance uploads.
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "proposal_attachments")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class ProposalAttachment extends BaseEntity {

    @Column(nullable = false)
    private String fileName;

    @Column(nullable = false)
    private String fileUrl;

    private String label;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "proposal_id", nullable = false)
    private ServiceProposal proposal;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;
}
