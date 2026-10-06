package com.zuhoocms.modules.hrm.attendance.attendance;

import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
// Lombok's isLate()/isOvertime()/isVerified() also emit the stripped "late"/"overtime"/"verified" keys alongside the
// pinned ones below. A grep of all three clients (Angular, Flutter, Android) found nothing reading the stripped
// spellings for attendance, so they are suppressed here and only the "is" keys are on the wire - the same treatment
// SupportMessageResponse already gives "internal"/"resolution".
@com.fasterxml.jackson.annotation.JsonIgnoreProperties({"late", "overtime", "verified"})
public class AttendanceResponse {

    private Long id;
    private Long companyId;

    private Long employeeId;
    private String employeeName;
    private String employeeNumber;

    private LocalDate attendanceDate;

    private LocalTime checkInTime;
    private LocalDateTime checkInDateTime;
    private AttendanceMethod checkInMethod;
    private String checkInLocation;
    private String checkInLatitude;
    private String checkInLongitude;
    private String checkInReason;

    private LocalTime checkOutTime;
    private LocalDateTime checkOutDateTime;
    private AttendanceMethod checkOutMethod;
    private String checkOutLocation;

    /** The selfies taken at each punch, as this app's own file URLs; the Android check-in screen reads checkInSelfieUrl. */
    private String checkInSelfieUrl;
    private String checkOutSelfieUrl;

    /**
     * Set when a punch that day fell outside the company's office radius (or a GPS punch arrived with no usable
     * coordinates). The reason is the first offence of the day - a later in-range punch does not clear it.
     */
    private boolean locationFlagged;
    private String locationFlagReason;
    private Double distanceFromOfficeMeters;

    private AttendanceStatus status;
    private ShiftType shiftType;

    /** Pinned to "isLate": Jackson derives "late" from isLate(), and the frontend reads isLate, so the Late column rendered empty for every record. */
    @com.fasterxml.jackson.annotation.JsonProperty("isLate")
    private boolean isLate;
    private long lateMinutes;
    private String lateReason;

    /** Pinned like isLate above: Jackson would otherwise emit "overtime", which the frontend never reads. */
    @com.fasterxml.jackson.annotation.JsonProperty("isOvertime")
    private boolean isOvertime;
    private BigDecimal overtimeHours;

    private boolean leftEarly;
    private long earlyMinutes;
    private String earlyDepartureReason;

    private BigDecimal totalWorkingHours;

    /** Pinned like isLate above: Jackson would otherwise emit "verified", which the frontend never reads. */
    @com.fasterxml.jackson.annotation.JsonProperty("isVerified")
    private boolean isVerified;
    private double verificationScore;

    private boolean approved;
    private String approvedBy;
    private LocalDateTime approvedDateTime;

    private String notes;

    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
