package com.zuhoocms.modules.hrm.dashboard;

public interface HrDashboardService {

    /** Aggregated HR figures for the active company. */
    HrDashboardResponse getSummary();
}
