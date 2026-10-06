package com.zuhoocms.modules.ai.enums;

public enum AiFeature {
    EMPLOYMENT_LETTER,
    LEAVE_POLICY,
    PERFORMANCE_REVIEW,
    CRM_LEAD_SUMMARY,
    CRM_ACTIVITY_SUMMARY,
    INVOICE_SUMMARY,
    SERVICE_REQUEST_SUMMARY,
    ANNOUNCEMENT_DRAFT,
    HOLIDAY_DRAFT,
    WORKFLOW_SUGGESTION,
    SEARCH_ANSWER,
    BUSINESS_INSIGHTS,
    GENERAL,
    // In-page "Compose" micro-assists: a quick draft from rough notes on a form, via the same generateRaw() path as the features above.
    TIMESHEET_ENTRY,
    EXPENSE_ENTRY,
    DAILY_BRIEFING,
    // Marks a tool-calling agent thread rather than a plain GENERAL one: cosmetic grouping only, the agent loop behaves identically.
    AGENT_TASK
}
