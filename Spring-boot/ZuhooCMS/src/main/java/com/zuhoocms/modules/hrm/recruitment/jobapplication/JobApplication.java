package com.zuhoocms.modules.hrm.recruitment.jobapplication;

import com.zuhoocms.modules.hrm.recruitment.jobpost.JobPosting;
import com.zuhoocms.modules.hrm.recruitment.candidate.Candidate;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.enums.ApplicationSource;
import com.zuhoocms.enums.ApplicationStatus;
import com.zuhoocms.enums.AtsParseStatus;
import jakarta.persistence.*;
import lombok.*;
import java.time.Instant;
import java.time.LocalDateTime;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "job_applications")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class JobApplication extends BaseEntity {

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "job_posting_id", nullable = false) private JobPosting jobPosting;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", nullable = false) private Company company;

    // The person applying; name/email/phone/resume/links live on Candidate so one person can have several applications without duplicating contact details.
    // Not DB-NOT-NULL: ddl-auto=update adds columns via a plain ALTER, which Postgres rejects as NOT NULL against a table with existing rows.
    // Every code path that creates a JobApplication sets this - see RecruitmentServiceImpl.apply() and RecruitmentDataMigrationRunner, which backfills pre-existing rows on boot.
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "candidate_id") private Candidate candidate;

    private String coverLetter;

    // What the applicant submitted with THIS application: an anonymous careers-page submission must never overwrite the shared Candidate record, since anyone knowing the email could replace name, phone and resume.
    // Nullable - staff-logged and legacy rows use the Candidate's details. See RecruitmentMapper / CvScoringService.
    @Column(length = 150) private String applicantName;
    @Column(length = 30) private String applicantPhone;
    @Column(length = 500) private String resumeUrl;
    @Column(length = 500) private String linkedInUrl;
    @Column(length = 500) private String portfolioUrl;

    /** How this specific application arrived - can differ from Candidate.source (e.g. a second application via referral). */
    @Enumerated(EnumType.STRING)
    @Column(length = 20) private ApplicationSource source;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(nullable = false) private ApplicationStatus status = ApplicationStatus.APPLIED;

    private LocalDateTime interviewAt;
    private String interviewNotes;
    @Column(columnDefinition = "TEXT") private String rejectionReason;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "reviewed_by_id") private User reviewedBy;

    // Set once the application is hired, mirroring Lead.convertedClient/convertedAt in the CRM module.
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "converted_employee_id") private Employee convertedEmployee;

    private LocalDateTime convertedAt;

    // Candidate evaluation, 0-100 each and all optional; per-application rather than per-candidate, since the same person can fit two roles differently.
    // Weighted into overallScore by RecruitmentServiceImpl.evaluate() - see that method for the weights.
    private Integer scoreEducation;
    private Integer scoreExperience;
    private Integer scoreTechnicalSkills;
    private Integer scoreInterview;
    private Integer scoreCommunication;
    private Double overallScore;

    // Automated ATS match: a signal alongside the manual scores above, never a replacement, computed once at apply time from a resume we host against the posting's requirements.
    // See CvScoringService for the weighting, and AtsParseStatus for why an application may never get scored (no resume, unsupported format, no requirements set).
    private Integer atsScore;
    @Column(length = 500) private String atsMatchedRequiredSkills;
    @Column(length = 500) private String atsMissingRequiredSkills;
    @Column(length = 500) private String atsMatchedPreferredSkills;
    private Integer atsExtractedExperienceYears;
    private Boolean atsMeetsEducationRequirement;
    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 20) private AtsParseStatus atsParseStatus = AtsParseStatus.PENDING;
    private Instant atsParsedAt;
}
