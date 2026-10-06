package com.zuhoocms.modules.crm.support;

/** Email normalisation for lead/contact duplicate detection: trimmed and lowercased on write, so the stored value and the case-insensitive exists-queries agree and "Bob@X.com" is not a second lead. */
public final class EmailMatching {

    private EmailMatching() {
    }

    /** Trimmed + lowercased, or null when blank. */
    public static String normalise(String email) {
        if (email == null) return null;
        String trimmed = email.trim().toLowerCase();
        return trimmed.isEmpty() ? null : trimmed;
    }
}
