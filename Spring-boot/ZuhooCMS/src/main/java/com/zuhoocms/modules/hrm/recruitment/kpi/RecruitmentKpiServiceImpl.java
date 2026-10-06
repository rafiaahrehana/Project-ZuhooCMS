package com.zuhoocms.modules.hrm.recruitment.kpi;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.core.base.SoftDeletedProxies;
import com.zuhoocms.enums.ApplicationSource;
import com.zuhoocms.enums.ApplicationStatus;
import com.zuhoocms.enums.AtsParseStatus;
import com.zuhoocms.enums.JobPostingStatus;
import com.zuhoocms.modules.hrm.employee.EmployeeUserResolver;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplication;
import com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationRepository;
import com.zuhoocms.modules.hrm.recruitment.jobpost.JobPosting;
import com.zuhoocms.modules.hrm.recruitment.jobpost.JobPostingRepository;
import com.zuhoocms.modules.hrm.recruitment.offer.JobOffer;
import com.zuhoocms.modules.hrm.recruitment.offer.JobOfferRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.OptionalDouble;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Aggregates entirely in Java over one fetch each of applications/postings/offers, as HrDashboardServiceImpl does: simpler and cheaper than N per-breakdown queries at this app's scale.
 *
 * "Reached stage X" is inferred from the CURRENT status via PIPELINE_ORDER, since no stage-history audit trail exists; REJECTED/WITHDRAWN are excluded from "reached" counts rather than guessed at.
 *
 * Date filtering (from/to, optional) defines an "applied in this period" window on JobApplication.createdAt, and every derived figure is recomputed from that filtered set so the report stays internally consistent.
 * openPositions and hiresThisMonth are deliberately NOT filtered - they are "right now" pulse figures, not period activity.
 *
 * minScore only narrows the Top Evaluated Candidates list: most applications are never scored, so excluding unset scores elsewhere would drop most of the pipeline out of the other figures.
 */
@Service
@RequiredArgsConstructor
public class RecruitmentKpiServiceImpl implements RecruitmentKpiService {

    private final JobApplicationRepository applicationRepository;
    private final JobPostingRepository jobPostingRepository;
    private final JobOfferRepository jobOfferRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    private static final Map<ApplicationStatus, Integer> PIPELINE_ORDER = Map.ofEntries(
        Map.entry(ApplicationStatus.APPLIED, 0),
        Map.entry(ApplicationStatus.SCREENING, 1),
        Map.entry(ApplicationStatus.SHORTLISTED, 2),
        Map.entry(ApplicationStatus.INTERVIEW_SCHEDULED, 3),
        Map.entry(ApplicationStatus.INTERVIEWED, 4),
        Map.entry(ApplicationStatus.SELECTED, 5),
        Map.entry(ApplicationStatus.OFFER_PENDING, 6),
        Map.entry(ApplicationStatus.OFFER_SENT, 6),
        Map.entry(ApplicationStatus.OFFER_REJECTED, 6),
        Map.entry(ApplicationStatus.OFFER_ACCEPTED, 7),
        Map.entry(ApplicationStatus.HIRED, 8)
    );
    private static final int INTERVIEW_ORDER = PIPELINE_ORDER.get(ApplicationStatus.INTERVIEW_SCHEDULED);

    @Override
    @Transactional(readOnly = true)
    public RecruitmentKpiResponse getSummary(LocalDate from, LocalDate to, Double minScore) {
        authorizationService.checkPermission(PermissionCode.RECRUITMENT_REPORT_VIEW);
        Long companyId = requireCompanyId();

        // Fetch-joined: the associations the report reads would each cost one query per row as plain lazy loads.
        List<JobApplication> allApplications = applicationRepository.findAllForKpis(companyId);
        List<JobPosting> postings = jobPostingRepository.findAllForKpis(companyId);
        List<JobOffer> allOffers = jobOfferRepository.findAllForKpis(companyId);
        Set<Long> interviewedIds = new java.util.HashSet<>(applicationRepository.findInterviewedApplicationIds(companyId));
        // Candidate FKs off the column, NOT off the fetched association: findAllForKpis left-join-fetches the
        // candidate and @SQLRestriction("deleted = false") nulls it for a soft-deleted candidate, which made the
        // distinct-candidate count blind to the very applications it was counting.
        Map<Long, Long> candidateIdByApplication = candidateIdsByApplication(companyId);

        List<JobApplication> applications = filterByAppliedDate(allApplications, from, to);
        Set<Long> inRangeApplicationIds = applications.stream().map(JobApplication::getId).collect(Collectors.toSet());
        List<JobOffer> offers = allOffers.stream()
            .filter(o -> SoftDeletedProxies.id(o.getJobApplication()) != null
                && inRangeApplicationIds.contains(SoftDeletedProxies.id(o.getJobApplication())))
            .toList();

        List<JobApplication> hired = applications.stream()
            .filter(a -> a.getStatus() == ApplicationStatus.HIRED && a.getConvertedAt() != null)
            .toList();
        // "This month" hires are a live pulse figure, so this uses allApplications rather than the from/to-filtered set on purpose.
        List<JobApplication> allHired = allApplications.stream()
            .filter(a -> a.getStatus() == ApplicationStatus.HIRED && a.getConvertedAt() != null)
            .toList();
        // "Interviewed" = at/after the interview stage OR has a completed interview on record; the status-only rule dropped everyone rejected after interview, overstating the interview-to-hire rate.
        long reachedInterview = applications.stream()
            .filter(a -> reachedInterview(a) || interviewedIds.contains(a.getId()))
            .count();
        YearMonth thisMonth = YearMonth.now();

        return RecruitmentKpiResponse.builder()
            .openPositions(postings.stream().filter(p -> p.getStatus() == JobPostingStatus.OPEN).count())
            // Distinct people behind the applications in range, deleted candidate records included: their applications
            // still happened and must still be counted. Applications with no candidate row at all (careers-page
            // submissions predating the Candidate backfill) have no person to count and are skipped, as before.
            .totalCandidates(applications.stream()
                .map(a -> candidateIdByApplication.get(a.getId()))
                .filter(java.util.Objects::nonNull).distinct().count())
            .totalApplications(applications.size())
            .hiresThisMonth(allHired.stream().filter(a -> YearMonth.from(a.getConvertedAt()).equals(thisMonth)).count())
            .hiresTotal(hired.size())
            .avgTimeToHireDays(avgDays(hired, a -> a.getCreatedAt(), JobApplication::getConvertedAt))
            .avgTimeToFillDays(avgTimeToFillDays(hired))
            .applicationToInterviewRate(rate(reachedInterview, applications.size()))
            .interviewToHireRate(rate(hired.size(), reachedInterview))
            .offerAcceptanceRate(offerAcceptanceRate(offers))
            .avgAtsMatchScore(avgAtsMatchScore(applications))
            .funnel(funnel(applications))
            .sourceBreakdown(sourceBreakdown(applications))
            .jobKpis(jobKpis(postings, applications, offers))
            .recruiterKpis(recruiterKpis(postings, applications, offers))
            .topCandidates(topCandidates(applications, minScore))
            .build();
    }

    private Map<Long, Long> candidateIdsByApplication(Long companyId) {
        Map<Long, Long> byApplication = new java.util.HashMap<>();
        for (Object[] row : applicationRepository.findCandidateIdsByApplication(companyId)) {
            if (row[1] != null) byApplication.put((Long) row[0], (Long) row[1]);
        }
        return byApplication;
    }

    private List<JobApplication> filterByAppliedDate(List<JobApplication> apps, LocalDate from, LocalDate to) {
        if (from == null && to == null) return apps;
        return apps.stream().filter(a -> {
            if (a.getCreatedAt() == null) return false;
            LocalDate appliedOn = a.getCreatedAt().toLocalDate();
            if (from != null && appliedOn.isBefore(from)) return false;
            if (to != null && appliedOn.isAfter(to)) return false;
            return true;
        }).toList();
    }

    private boolean reachedInterview(JobApplication a) {
        Integer order = PIPELINE_ORDER.get(a.getStatus());
        return order != null && order >= INTERVIEW_ORDER;
    }

    private long count(List<JobApplication> apps, ApplicationStatus status) {
        return apps.stream().filter(a -> a.getStatus() == status).count();
    }

    private long inOfferSubPipeline(List<JobApplication> apps) {
        return inStage(apps, RecruitmentPipelineStages.OFFER);
    }

    private long inStage(List<JobApplication> apps, String stage) {
        return apps.stream().filter(a -> stage.equals(RecruitmentPipelineStages.stageOf(a.getStatus()))).count();
    }

    private Double rate(long numerator, long denominator) {
        return denominator == 0 ? null : Math.round(numerator * 1000.0 / denominator) / 10.0;
    }

    private Double avgDays(List<JobApplication> apps,
                            java.util.function.Function<JobApplication, LocalDateTime> from,
                            java.util.function.Function<JobApplication, LocalDateTime> to) {
        if (apps.isEmpty()) return null;
        OptionalDouble avg = apps.stream()
            .filter(a -> from.apply(a) != null && to.apply(a) != null)
            .mapToLong(a -> ChronoUnit.DAYS.between(from.apply(a).toLocalDate(), to.apply(a).toLocalDate()))
            .average();
        return avg.isPresent() ? Math.round(avg.getAsDouble() * 10) / 10.0 : null;
    }

    private Double avgTimeToFillDays(List<JobApplication> hired) {
        List<Long> days = new ArrayList<>();
        for (JobApplication a : hired) {
            JobPosting posting = SoftDeletedProxies.loadable(a.getJobPosting());
            if (posting == null || posting.getCreatedAt() == null || a.getConvertedAt() == null) continue;
            days.add(ChronoUnit.DAYS.between(posting.getCreatedAt().toLocalDate(), a.getConvertedAt().toLocalDate()));
        }
        if (days.isEmpty()) return null;
        return Math.round(days.stream().mapToLong(Long::longValue).average().orElse(0) * 10) / 10.0;
    }

    private Double offerAcceptanceRate(List<JobOffer> offers) {
        long accepted = offers.stream().filter(o -> o.getStatus() == JobOffer.Status.ACCEPTED).count();
        long declined = offers.stream().filter(o -> o.getStatus() == JobOffer.Status.DECLINED).count();
        return rate(accepted, accepted + declined);
    }

    /** Mean CvScoringService.atsScore over applications that were actually scored - unscored/failed/not-applicable ones don't drag the average down or inflate it. */
    private Double avgAtsMatchScore(List<JobApplication> applications) {
        OptionalDouble avg = applications.stream()
            .filter(a -> a.getAtsParseStatus() == AtsParseStatus.SUCCESS && a.getAtsScore() != null)
            .mapToInt(JobApplication::getAtsScore)
            .average();
        return avg.isPresent() ? Math.round(avg.getAsDouble() * 10) / 10.0 : null;
    }

    private List<RecruitmentKpiResponse.FunnelStage> funnel(List<JobApplication> applications) {
        // Same grouping as the HR dashboard pipeline - see RecruitmentPipelineStages.
        return RecruitmentPipelineStages.STAGES.stream()
            .map(name -> stage(name, inStage(applications, name)))
            .toList();
    }

    private RecruitmentKpiResponse.FunnelStage stage(String name, long count) {
        return RecruitmentKpiResponse.FunnelStage.builder().stage(name).count(count).build();
    }

    private List<RecruitmentKpiResponse.SourceSlice> sourceBreakdown(List<JobApplication> applications) {
        long total = applications.size();
        Map<String, Long> counts = new LinkedHashMap<>();
        for (JobApplication a : applications) {
            String key = a.getSource() != null ? a.getSource().name() : "UNKNOWN";
            counts.merge(key, 1L, Long::sum);
        }
        return counts.entrySet().stream()
            .map(e -> RecruitmentKpiResponse.SourceSlice.builder()
                .source(e.getKey())
                .count(e.getValue())
                .percent(total == 0 ? 0 : Math.round(e.getValue() * 1000.0 / total) / 10.0)
                .build())
            // Count descending, then source name: without the tiebreak equally-sized sources swap places
            // between reports and the chart legend reorders itself for no reason.
            .sorted(java.util.Comparator
                .comparingLong(RecruitmentKpiResponse.SourceSlice::getCount).reversed()
                .thenComparing(RecruitmentKpiResponse.SourceSlice::getSource,
                    java.util.Comparator.nullsLast(String::compareTo)))
            .toList();
    }

    private List<RecruitmentKpiResponse.JobKpi> jobKpis(List<JobPosting> postings, List<JobApplication> applications, List<JobOffer> offers) {
        // Grouped on the FK read off the proxy, never on getJobPosting().getId(): a proxy to a soft-deleted posting throws when touched.
        Map<Long, List<JobApplication>> appsByPosting = applications.stream()
            .filter(a -> SoftDeletedProxies.id(a.getJobPosting()) != null)
            .collect(Collectors.groupingBy(a -> SoftDeletedProxies.id(a.getJobPosting())));
        Map<Long, List<JobOffer>> offersByPosting = offers.stream()
            .filter(o -> offerPostingId(o) != null)
            .collect(Collectors.groupingBy(RecruitmentKpiServiceImpl::offerPostingId));

        List<RecruitmentKpiResponse.JobKpi> result = new ArrayList<>();
        for (JobPosting posting : postings) {
            List<JobApplication> apps = appsByPosting.getOrDefault(posting.getId(), List.of());
            List<JobOffer> postingOffers = offersByPosting.getOrDefault(posting.getId(), List.of());
            List<JobApplication> hired = apps.stream()
                .filter(a -> a.getStatus() == ApplicationStatus.HIRED && a.getConvertedAt() != null)
                .toList();
            result.add(RecruitmentKpiResponse.JobKpi.builder()
                .jobPostingId(posting.getId())
                .jobTitle(posting.getTitle())
                .status(posting.getStatus().name())
                .applications(apps.size())
                .shortlisted(count(apps, ApplicationStatus.SHORTLISTED))
                .interviews(inStage(apps, RecruitmentPipelineStages.INTERVIEW))
                .offers(inOfferSubPipeline(apps))
                .hired(hired.size())
                .timeToFillDays(avgTimeToFillDays(hired))
                .offerAcceptanceRate(offerAcceptanceRate(postingOffers))
                .avgAtsMatchScore(avgAtsMatchScore(apps))
                .build());
        }
        return result;
    }

    private List<RecruitmentKpiResponse.RecruiterKpi> recruiterKpis(List<JobPosting> postings, List<JobApplication> applications, List<JobOffer> offers) {
        Map<Long, List<JobPosting>> postingsByRecruiter = postings.stream()
            .filter(p -> SoftDeletedProxies.id(p.getAssignedRecruiter()) != null)
            .collect(Collectors.groupingBy(p -> SoftDeletedProxies.id(p.getAssignedRecruiter())));

        List<RecruitmentKpiResponse.RecruiterKpi> result = new ArrayList<>();
        for (Map.Entry<Long, List<JobPosting>> entry : postingsByRecruiter.entrySet()) {
            List<JobPosting> recruiterPostings = entry.getValue();
            java.util.Set<Long> postingIds = recruiterPostings.stream().map(JobPosting::getId).collect(Collectors.toSet());
            List<JobApplication> apps = applications.stream()
                .filter(a -> postingIds.contains(SoftDeletedProxies.id(a.getJobPosting())))
                .toList();
            List<JobOffer> recruiterOffers = offers.stream()
                .filter(o -> postingIds.contains(offerPostingId(o)))
                .toList();
            List<JobApplication> hired = apps.stream()
                .filter(a -> a.getStatus() == ApplicationStatus.HIRED && a.getConvertedAt() != null)
                .toList();
            // displayName(), not recruiter.getUser().getFullName(): both the employee and their login are soft-deleted on termination, and either proxy throws when touched.
            String recruiterName = EmployeeUserResolver.displayName(recruiterPostings.get(0).getAssignedRecruiter());

            result.add(RecruitmentKpiResponse.RecruiterKpi.builder()
                .recruiterId(entry.getKey())
                .recruiterName(recruiterName)
                .jobsManaged(recruiterPostings.size())
                .applications(apps.size())
                .shortlisted(count(apps, ApplicationStatus.SHORTLISTED))
                .interviews(inStage(apps, RecruitmentPipelineStages.INTERVIEW))
                .offers(inOfferSubPipeline(apps))
                .hires(hired.size())
                .avgTimeToHireDays(avgDays(hired, JobApplication::getCreatedAt, JobApplication::getConvertedAt))
                .offerAcceptanceRate(offerAcceptanceRate(recruiterOffers))
                .avgAtsMatchScore(avgAtsMatchScore(apps))
                .build());
        }
        // Hires descending, then recruiter name - the same tiebreak sourceBreakdown() got, and for the same reason:
        // without it recruiters on equal hire counts swapped places between two requests and the leaderboard flickered.
        result.sort(java.util.Comparator
            .comparingLong(RecruitmentKpiResponse.RecruiterKpi::getHires).reversed()
            .thenComparing(RecruitmentKpiResponse.RecruiterKpi::getRecruiterName,
                java.util.Comparator.nullsLast(String::compareTo))
            // Two recruiters can share a display name; the id makes the order total, so it cannot depend on the
            // HashMap iteration order the rows were built in.
            .thenComparing(RecruitmentKpiResponse.RecruiterKpi::getRecruiterId,
                java.util.Comparator.nullsLast(Long::compareTo)));
        return result;
    }

    private static final int TOP_CANDIDATES_LIMIT = 10;
    // A minScore threshold already bounds the result set: "who's above 90?" wants everyone above 90, not just the first 10.
    private static final int TOP_CANDIDATES_LIMIT_WITH_MIN_SCORE = 50;

    /*
     * Named from the candidate where it is readable, else from applicantName on the application row: findAllForKpis
     * left-join-fetches the candidate, and BaseEntity's @SQLRestriction("deleted = false") turns that into a null
     * association once the candidate is soft-deleted, which silently dropped the row out of this list.
     * Applications with no candidate at all and no recorded name are still skipped, as before.
     */
    private List<RecruitmentKpiResponse.TopCandidate> topCandidates(List<JobApplication> applications, Double minScore) {
        int limit = minScore != null ? TOP_CANDIDATES_LIMIT_WITH_MIN_SCORE : TOP_CANDIDATES_LIMIT;
        return applications.stream()
            .filter(a -> a.getOverallScore() != null && candidateName(a) != null)
            .filter(a -> minScore == null || a.getOverallScore() >= minScore)
            .sorted((a, b) -> Double.compare(b.getOverallScore(), a.getOverallScore()))
            .limit(limit)
            .map(a -> {
                JobPosting posting = SoftDeletedProxies.loadable(a.getJobPosting());
                return RecruitmentKpiResponse.TopCandidate.builder()
                    .applicationId(a.getId())
                    .candidateName(candidateName(a))
                    .jobTitle(posting != null ? posting.getTitle() : null)
                    .overallScore(a.getOverallScore())
                    .build();
            })
            .toList();
    }

    /** Posting id behind an offer, read off the FKs so neither a soft-deleted application nor a soft-deleted posting throws. */
    private static Long offerPostingId(JobOffer o) {
        JobApplication a = SoftDeletedProxies.loadable(o.getJobApplication());
        return a == null ? null : SoftDeletedProxies.id(a.getJobPosting());
    }

    private static String candidateName(JobApplication a) {
        var candidate = SoftDeletedProxies.loadable(a.getCandidate());
        return candidate != null && candidate.getName() != null ? candidate.getName() : a.getApplicantName();
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }
}
