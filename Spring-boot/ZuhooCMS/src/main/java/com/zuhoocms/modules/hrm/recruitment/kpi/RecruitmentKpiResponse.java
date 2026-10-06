package com.zuhoocms.modules.hrm.recruitment.kpi;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * Everything the Recruitment Reports &amp; KPIs page renders, in one round trip; as in HrDashboardResponse, counts are primitives and genuinely unknown rates are boxed and null so the UI shows a dash, not 0%.
 * Computed live from JobApplication's CURRENT status: there is no stage-transition history table, so "reached interview" is inferred from pipeline order, not an audit trail. See RecruitmentKpiServiceImpl.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class RecruitmentKpiResponse {

    private long openPositions;
    private long totalCandidates;
    private long totalApplications;
    private long hiresThisMonth;
    private long hiresTotal;

    /** Mean days from application to offer acceptance, over HIRED applications. Null with no hires yet. */
    private Double avgTimeToHireDays;
    /** Mean days from a posting opening to the day a hire against it accepted, per hire. Null with no hires yet. */
    private Double avgTimeToFillDays;
    /** % of all applications that reached at least the interview stage. */
    private Double applicationToInterviewRate;
    /** % of applications that reached interview and went on to be hired. */
    private Double interviewToHireRate;
    /** ACCEPTED / (ACCEPTED + DECLINED) offers - DRAFT/WITHDRAWN never reached a candidate decision. */
    private Double offerAcceptanceRate;
    /** Mean CvScoringService.atsScore over applications with atsParseStatus=SUCCESS. Null when nothing has been scored yet. */
    private Double avgAtsMatchScore;

    /** Applications by current stage: Applied -> Screening -> Interview -> Offer -> Hired. */
    private List<FunnelStage> funnel;
    private List<SourceSlice> sourceBreakdown;
    private List<JobKpi> jobKpis;
    private List<RecruiterKpi> recruiterKpis;
    /** Top-scored applications (evaluate() sets this) - candidates ranked, not by KPI. */
    private List<TopCandidate> topCandidates;

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class FunnelStage {
        private String stage;
        private long count;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class SourceSlice {
        private String source;
        private long count;
        private double percent;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class JobKpi {
        private Long jobPostingId;
        private String jobTitle;
        private String status;
        private long applications;
        private long shortlisted;
        private long interviews;
        private long offers;
        private long hired;
        private Double timeToFillDays;
        private Double offerAcceptanceRate;
        /** Mean automated ATS match score over this posting's applications that were actually scored - null if none have been. */
        private Double avgAtsMatchScore;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class RecruiterKpi {
        private Long recruiterId;
        private String recruiterName;
        private long jobsManaged;
        private long applications;
        private long shortlisted;
        private long interviews;
        private long offers;
        private long hires;
        private Double avgTimeToHireDays;
        private Double offerAcceptanceRate;
        /** Mean automated ATS match score over this recruiter's applications that were actually scored - null if none have been. */
        private Double avgAtsMatchScore;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class TopCandidate {
        private Long applicationId;
        private String candidateName;
        private String jobTitle;
        private Double overallScore;
    }
}
