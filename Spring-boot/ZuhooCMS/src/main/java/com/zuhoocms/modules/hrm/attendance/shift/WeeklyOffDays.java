package com.zuhoocms.modules.hrm.attendance.shift;

import java.time.DayOfWeek;
import java.util.EnumSet;
import java.util.Set;

/** Single parser for Shift.weeklyOffDays; accepts "FRI,SAT" and the Angular form's "Saturday, Sunday" by matching the first three letters. */
public final class WeeklyOffDays {

    private WeeklyOffDays() {}

    public static Set<DayOfWeek> parse(String csv) {
        // null keeps the historical FRI/SAT default; blank means "no off days".
        if (csv == null) return EnumSet.of(DayOfWeek.FRIDAY, DayOfWeek.SATURDAY);
        Set<DayOfWeek> out = EnumSet.noneOf(DayOfWeek.class);
        if (csv.isBlank()) return out;
        for (String token : csv.split(",")) {
            String t = token.trim().toUpperCase();
            if (t.length() < 3) continue;
            switch (t.substring(0, 3)) {
                case "MON" -> out.add(DayOfWeek.MONDAY);
                case "TUE" -> out.add(DayOfWeek.TUESDAY);
                case "WED" -> out.add(DayOfWeek.WEDNESDAY);
                case "THU" -> out.add(DayOfWeek.THURSDAY);
                case "FRI" -> out.add(DayOfWeek.FRIDAY);
                case "SAT" -> out.add(DayOfWeek.SATURDAY);
                case "SUN" -> out.add(DayOfWeek.SUNDAY);
                default -> { /* unknown token - ignore */ }
            }
        }
        return out;
    }
}
