package com.zuhoocms.enums;

/** Picklist alongside the older free-text lostReason field, which stays as optional detail; the code is what makes win/loss analysis aggregatable. */
public enum LostReason {
    PRICE,
    COMPETITOR,
    NO_BUDGET,
    NO_RESPONSE,
    BAD_TIMING,
    REQUIREMENTS_MISMATCH,
    OTHER
}
