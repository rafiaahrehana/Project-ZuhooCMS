package com.zuhoocms.modules.hrm.recruitment.kpi;

import com.zuhoocms.enums.ApplicationStatus;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * The single definition of the Applied -> Screening -> Interview -> Offer -> Hired funnel, shared by the HR dashboard and the KPI report, which grouped statuses independently and showed two different funnels.
 * REJECTED and WITHDRAWN belong to no stage: a current status does not record how far an application got before it closed.
 */
public final class RecruitmentPipelineStages {

    public static final String APPLIED = "Applied";
    public static final String SCREENING = "Screening";
    public static final String INTERVIEW = "Interview";
    public static final String OFFER = "Offer";
    public static final String HIRED = "Hired";

    public static final List<String> STAGES = List.of(APPLIED, SCREENING, INTERVIEW, OFFER, HIRED);

    private RecruitmentPipelineStages() {}

    /** The funnel stage a status is shown under, or null for closed statuses (REJECTED, WITHDRAWN). */
    public static String stageOf(ApplicationStatus status) {
        if (status == null) return null;
        return switch (status) {
            case APPLIED -> APPLIED;
            case SCREENING, SHORTLISTED -> SCREENING;
            case INTERVIEW_SCHEDULED, INTERVIEWED, SELECTED -> INTERVIEW;
            case OFFER_PENDING, OFFER_SENT, OFFER_ACCEPTED, OFFER_REJECTED -> OFFER;
            case HIRED -> HIRED;
            case REJECTED, WITHDRAWN -> null;
        };
    }

    /** Stage -> count, in funnel order, from per-status counts. Every stage is present (zero when empty). */
    public static Map<String, Long> countByStage(Map<ApplicationStatus, Long> perStatus) {
        Map<String, Long> result = new LinkedHashMap<>();
        STAGES.forEach(stage -> result.put(stage, 0L));
        perStatus.forEach((status, count) -> {
            String stage = stageOf(status);
            if (stage != null && count != null) result.merge(stage, count, Long::sum);
        });
        return result;
    }
}
