package com.zuhoocms.enums;

/** Divisor turning a monthly salary into a day's pay; there is no universally correct answer, so each tenant picks its own policy. */
public enum PerDayBasis {

    /** Divide by the calendar month's days (28-31), so the same absence costs more in February than in January. */
    CALENDAR_DAYS,

    /** Fixed 30-day month. Predictable and identical every month. */
    FIXED_30,

    /** Fixed 26-day month (30 less ~4 weekly holidays), an RMG/manufacturing convention; the smaller divisor makes deductions bite harder. */
    FIXED_26,

    /** Actual working days, excluding weekly-offs and company holidays: most defensible, but the divisor moves between 20 and 23 month to month. */
    ACTUAL_WORKING_DAYS
}
