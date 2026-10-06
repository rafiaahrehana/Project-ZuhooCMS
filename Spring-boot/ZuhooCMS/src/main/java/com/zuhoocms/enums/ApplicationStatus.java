package com.zuhoocms.enums;

public enum ApplicationStatus {
    APPLIED,
    SCREENING,
    SHORTLISTED,
    INTERVIEW_SCHEDULED,
    INTERVIEWED,
    SELECTED,
    // Offer sub-pipeline: these change only through JobOfferController's actions, never the generic status endpoint, so offer state and application state cannot drift apart.
    OFFER_PENDING,
    OFFER_SENT,
    OFFER_ACCEPTED,
    OFFER_REJECTED,
    HIRED,
    REJECTED,
    WITHDRAWN
}
