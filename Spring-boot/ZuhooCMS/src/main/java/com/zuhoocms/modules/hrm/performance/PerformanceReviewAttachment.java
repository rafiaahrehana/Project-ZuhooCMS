package com.zuhoocms.modules.hrm.performance;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.company.Company;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

/** A supporting document attached to a performance review; like servicedesk's Document, the file goes through POST /api/upload and only its URL and metadata are stored here. */
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "performance_review_attachments")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class PerformanceReviewAttachment extends BaseEntity {

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "review_id", nullable = false)
    private PerformanceReview review;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id")
    private Company company;

    @Column(nullable = false)
    private String fileName;

    private String fileUrl;
    private String fileType;
    private Long fileSizeBytes;

    /** Optional human label, e.g. "Client Appreciation". */
    private String label;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "uploaded_by_id")
    private User uploadedBy;
}
