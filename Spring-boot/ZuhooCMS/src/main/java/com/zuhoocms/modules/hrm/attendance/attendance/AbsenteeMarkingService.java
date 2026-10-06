package com.zuhoocms.modules.hrm.attendance.attendance;

import com.zuhoocms.enums.LeaveRequestStatus;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.hrm.attendance.shift.EmployeeShiftAssignment;
import com.zuhoocms.modules.hrm.attendance.shift.EmployeeShiftAssignmentRepository;
import com.zuhoocms.modules.hrm.attendance.shift.WeeklyOffDays;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.hrm.leave.holiday.HolidayRepository;
import com.zuhoocms.modules.hrm.leave.leaverequest.LeaveRequestRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;

/**
 * Settles attendance for a completed day; absence means no record at all, or a check-in with no check-out (an unfinished day is not attendance).
 * Shared by {@code DailyAbsenteeScheduler} and the manual admin backfill endpoint.
 * Idempotent: rows already ABSENT or fully clocked are untouched, and holidays, weekly-off days, approved leave, future dates and pre-hire dates are skipped.
 */
@Service
@RequiredArgsConstructor
public class AbsenteeMarkingService {

    private final CompanyRepository companyRepository;
    private final EmployeeRepository employeeRepository;
    private final AttendanceRepository attendanceRepository;
    private final HolidayRepository holidayRepository;
    private final LeaveRequestRepository leaveRequestRepository;
    private final EmployeeShiftAssignmentRepository shiftAssignmentRepository;

    /**
     * Marks absentees for one date across every company; public so the scheduler calls it per date through the Spring proxy, giving each date its own transaction.
     * @return number of ABSENT records created
     */
    @Transactional
    public int markAllCompaniesForDate(LocalDate targetDate) {
        int created = 0;
        for (Company company : companyRepository.findAll()) {
            if (company.isPlatformTenant()) continue;
            created += markCompanyForDate(company, targetDate);
        }
        return created;
    }

    /**
     * Backfills absentees for one company across an inclusive date range, for the tenant-scoped manual admin trigger.
     * @return number of ABSENT records created
     */
    @Transactional
    public int backfillForCompany(Long companyId, LocalDate start, LocalDate end) {
        Company company = companyRepository.findById(companyId).orElse(null);
        if (company == null || company.isPlatformTenant()) return 0;

        int created = 0;
        for (LocalDate d = start; !d.isAfter(end); d = d.plusDays(1)) {
            created += markCompanyForDate(company, d);
        }
        return created;
    }

    private int markCompanyForDate(Company company, LocalDate targetDate) {
        // Never mark absence for a day that hasn't happened yet.
        if (targetDate.isAfter(LocalDate.now())) return 0;
        if (holidayRepository.existsByCompanyIdAndDate(company.getId(), targetDate)) return 0;

        int created = 0;

        for (Employee employee : employeeRepository.findByCompanyIdAndActiveTrue(company.getId())) {
            // Don't invent absences for days before the employee joined.
            if (employee.getHireDate() != null && targetDate.isBefore(employee.getHireDate())) continue;

            List<Attendance> existing =
                    attendanceRepository.findByEmployeeIdAndAttendanceDate(employee.getId(), targetDate);
            if (!existing.isEmpty()) {
                // Yesterday's night shift is still running (it ends this morning).
                if (targetDate.equals(LocalDate.now().minusDays(1))
                        && isNightShift(company.getId(), employee.getId(), targetDate)) continue;
                created += settleIncompleteDays(existing, targetDate);
                continue;
            }

            if (isWeeklyOff(company.getId(), employee.getId(), targetDate)) continue;

            // Approved leave writes an ON_LEAVE row rather than skipping the employee; skipping meant ON_LEAVE was never written and "% on leave" always read near-zero.
            if (leaveRequestRepository.existsApprovedForEmployeeAndDate(
                    employee.getId(), targetDate, LeaveRequestStatus.APPROVED)) {
                attendanceRepository.save(Attendance.builder()
                        .companyId(company.getId())
                        .employee(employee)
                        .attendanceDate(targetDate)
                        .status(AttendanceStatus.ON_LEAVE)
                        .build());
                continue;
            }

            // The nightly run happens before a night shift starts, so not having checked in yet is not an absence.
            if (targetDate.equals(LocalDate.now())
                    && isNightShift(company.getId(), employee.getId(), targetDate)) continue;

            attendanceRepository.save(Attendance.builder()
                    .companyId(company.getId())
                    .employee(employee)
                    .attendanceDate(targetDate)
                    .status(AttendanceStatus.ABSENT)
                    .build());
            created++;
        }
        return created;
    }

    /**
     * A day clocked into but never clocked out of is settled as ABSENT once the day is over.
     * Past dates only - flipping someone mid-shift would be wrong. The check-in time stays as evidence, so HR can correct the day.
     * @return number of records flipped to ABSENT
     */
    private int settleIncompleteDays(List<Attendance> existing, LocalDate targetDate) {
        if (!targetDate.isBefore(LocalDate.now())) return 0;

        int settled = 0;
        for (Attendance attendance : existing) {
            if (attendance.getCheckInTime() != null
                    && attendance.getCheckOutTime() == null
                    && attendance.getStatus() != AttendanceStatus.ABSENT) {
                attendance.setStatus(AttendanceStatus.ABSENT);
                // Clearing lateness on an ABSENT day: the day is already unpaid, so a late flag double-counts it and inflates every "late days" figure. The check-in time stays as evidence.
                attendance.setLate(false);
                attendance.setLateMinutes(0);
                attendanceRepository.save(attendance);
                settled++;
            }
        }
        return settled;
    }

    private boolean isWeeklyOff(Long companyId, Long employeeId, LocalDate date) {
        EmployeeShiftAssignment assignment = shiftAssignmentRepository
                .findEffectiveOn(companyId, employeeId, date)
                .orElse(null);
        return WeeklyOffDays.parse(assignment != null ? assignment.getShift().getWeeklyOffDays() : null)
                .contains(date.getDayOfWeek());
    }

    private boolean isNightShift(Long companyId, Long employeeId, LocalDate date) {
        return shiftAssignmentRepository.findEffectiveOn(companyId, employeeId, date)
                .map(a -> a.getShift().isNightShift())
                .orElse(false);
    }
}
