package com.zuhoocms.modules.hrm.recruitment.kpi;

import java.time.LocalDate;

public interface RecruitmentKpiService {

    /** Date bounds are optional and inclusive, filtering on JobApplication's applied date (null/null means all-time); minScore only narrows the Top Evaluated Candidates list. */
    RecruitmentKpiResponse getSummary(LocalDate from, LocalDate to, Double minScore);
}
