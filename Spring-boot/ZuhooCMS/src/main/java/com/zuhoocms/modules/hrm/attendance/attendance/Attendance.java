package com.zuhoocms.modules.hrm.attendance.attendance;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.hrm.attendance.biometric.device.BiometricDevice;
import com.zuhoocms.modules.hrm.employee.Employee;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.LocalDateTime;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "attendance",
        uniqueConstraints = @UniqueConstraint(columnNames = {"employee_id", "attendance_date"}),
        indexes = {
        @Index(name = "idx_attendance_employee", columnList = "employee_id"),
        @Index(name = "idx_attendance_date", columnList = "attendance_date"),
        @Index(name = "idx_attendance_status", columnList = "status"),
        @Index(name = "idx_attendance_company", columnList = "company_id")
})
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Attendance extends BaseEntity {

    private Long companyId;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "employee_id", nullable = false)
    private Employee employee;

    private LocalDate attendanceDate;

    private LocalTime checkInTime;
    private LocalDateTime checkInDateTime;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private AttendanceMethod checkInMethod = AttendanceMethod.MANUAL;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "checkin_device_id")
    private BiometricDevice checkInDevice;

    private String checkInLatitude;
    private String checkInLongitude;
    private String checkInLocation;

    private String checkInReason;

    @Builder.Default
    private boolean isVerified = false;

    @Builder.Default
    private double verificationScore = 0.0; // 0-100% match score for fingerprint

    private LocalTime checkOutTime;
    private LocalDateTime checkOutDateTime;

    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private AttendanceMethod checkOutMethod;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "checkout_device_id")
    private BiometricDevice checkOutDevice;

    private String checkOutLatitude;
    private String checkOutLongitude;
    private String checkOutLocation;

    // The selfie the employee took at the punch, as one of this app's own file URLs (/api/files/{id}).
    // 500 rather than the default 255: a signed serve URL is longer than a bare path.
    @Column(length = 500)
    private String checkInSelfieUrl;

    @Column(length = 500)
    private String checkOutSelfieUrl;

    // An out-of-range punch is recorded and flagged for review, never refused - a wrong GPS fix must not be able to
    // stop somebody working - so these are plain data columns that HR reads, not a gate on the write.
    // @ColumnDefault is required: ddl-auto=update adds this NOT NULL column to a table that already has rows.
    @Builder.Default
    @Column(nullable = false)
    @org.hibernate.annotations.ColumnDefault("false")
    private boolean locationFlagged = false;

    /** Why the row was flagged. One column on purpose: it holds the FIRST offence of the day, which is the interesting one. */
    private String locationFlagReason;

    /** Distance of the most recent punch from the office, in meters; null when the company does not enforce GPS. */
    private Double distanceFromOfficeMeters;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private AttendanceStatus status = AttendanceStatus.ABSENT;

    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private ShiftType shiftType;

    @Builder.Default
    private boolean isLate = false;

    private long lateMinutes;

    private String lateReason;

    @Builder.Default
    private boolean isOvertime = false;

    private BigDecimal overtimeHours;

    @Builder.Default
    private boolean leftEarly = false;

    private long earlyMinutes;

    private String earlyDepartureReason;

    private BigDecimal totalWorkingHours;

    private String adminNotes;
    private String approvalNotes;

    // Must default false: defaulting true made every self-service check-in arrive "approved" and left approveAttendance() with nothing to do. Payroll reads status, not this field.
    @Builder.Default
    private boolean approved = false;

    private String approvedBy;
    private LocalDateTime approvedDateTime;

    public long calculateTotalMinutes() {
        if (checkInTime != null && checkOutTime != null) {
            long minutes = java.time.temporal.ChronoUnit.MINUTES.between(checkInTime, checkOutTime);
            // Night shift: check-out after midnight wraps past the check-in time.
            return checkOutTime.isBefore(checkInTime) ? minutes + 1440 : minutes;
        }
        return 0;
    }

    public BigDecimal calculateTotalHours() {
        long minutes = calculateTotalMinutes();
        return BigDecimal.valueOf(minutes).divide(BigDecimal.valueOf(60), 2, java.math.RoundingMode.HALF_UP);
    }

    public void checkIn(LocalTime time, AttendanceMethod method, BiometricDevice device) {
        this.checkInTime = time;
        this.checkInDateTime = LocalDateTime.now();
        this.checkInMethod = method;
        this.checkInDevice = device;
    }

    public void checkOut(LocalTime time, AttendanceMethod method, BiometricDevice device) {
        this.checkOutTime = time;
        this.checkOutDateTime = LocalDateTime.now();
        this.checkOutMethod = method;
        this.checkOutDevice = device;
        this.totalWorkingHours = calculateTotalHours();
    }

    public boolean isCompleteDay() {
        return checkInTime != null && checkOutTime != null;
    }
}
