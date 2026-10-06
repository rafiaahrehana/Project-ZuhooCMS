package com.zuhoocms.modules.crm.support;

/** Phone normalisation for lead/contact duplicate detection: raw equality makes "+966 50 123 4567" and "0501234567" two people, so matching uses the trailing {@link #MATCH_DIGITS} digits of the digits-only form. */
public final class PhoneMatching {

    /** Enough to identify a subscriber without matching two unrelated short numbers. */
    public static final int MATCH_DIGITS = 9;

    private PhoneMatching() {
    }

    /** Everything that isn't a digit removed; null/blank in, null out. */
    public static String digitsOnly(String phone) {
        if (phone == null) return null;
        String digits = phone.replaceAll("[^0-9]", "");
        return digits.isEmpty() ? null : digits;
    }

    /** The comparable tail: the last {@link #MATCH_DIGITS} digits, or the whole thing when shorter; null when there are no digits. */
    public static String matchKey(String phone) {
        String digits = digitsOnly(phone);
        if (digits == null) return null;
        return digits.length() <= MATCH_DIGITS ? digits : digits.substring(digits.length() - MATCH_DIGITS);
    }

    /** Storage form: trimmed, or null when blank. */
    public static String normaliseForStorage(String phone) {
        if (phone == null) return null;
        String trimmed = phone.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }
}
