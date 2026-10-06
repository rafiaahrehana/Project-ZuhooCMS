package com.zuhoocms.modules.hrm.attendance.attendance;

import com.zuhoocms.modules.hrm.attendance.biometric.device.BiometricDevice;
import com.zuhoocms.modules.hrm.attendance.biometric.device.BiometricDeviceRepository;
import com.zuhoocms.modules.hrm.attendance.settings.AttendanceLocationSettings;
import com.zuhoocms.modules.hrm.attendance.settings.AttendanceLocationSettingsService;
import com.zuhoocms.modules.hrm.attendance.shift.EmployeeShiftAssignment;
import com.zuhoocms.modules.hrm.attendance.shift.EmployeeShiftAssignmentRepository;
import com.zuhoocms.modules.hrm.attendance.shift.WeeklyOffDays;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.hrm.leave.holiday.HolidayRepository;
import com.zuhoocms.modules.hrm.leave.leaverequest.LeaveRequest;
import com.zuhoocms.modules.hrm.leave.leaverequest.LeaveRequestRepository;
import com.zuhoocms.enums.LeaveRequestStatus;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.geo.GeoUtils;
import com.zuhoocms.shared.storage.FileReferencePolicy;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.math.BigDecimal;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.TemporalAdjusters;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class AttendanceServiceImpl implements AttendanceService {

    private final AttendanceRepository attendanceRepository;
    private final EmployeeRepository employeeRepository;
    private final BiometricDeviceRepository deviceRepository;
    private final EmployeeShiftAssignmentRepository shiftAssignmentRepository;
    private final HolidayRepository holidayRepository;
    private final LeaveRequestRepository leaveRequestRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final AttendanceLocationSettingsService attendanceLocationSettingsService;

    private void requireViewOrOwn(Long employeeId) {
        if (authorizationService.hasPermission(PermissionCode.ATTENDANCE_VIEW)) {
            return;
        }
        if (!isSelf(employeeId)) {
            throw new ForbiddenException("Access denied: you can only access your own attendance records");
        }
    }

    /** Write guard; deliberately not {@link #requireViewOrOwn}, which passes on ATTENDANCE_VIEW and let anyone who could read the roster clock a colleague in. Others' records need ATTENDANCE_UPDATE. */
    private void requireUpdateOrOwn(Long employeeId) {
        if (authorizationService.hasPermission(PermissionCode.ATTENDANCE_UPDATE)) {
            return;
        }
        if (!isSelf(employeeId)) {
            throw new ForbiddenException(
                    "Access denied: you can only record attendance for yourself");
        }
    }

    private boolean isSelf(Long employeeId) {
        User currentUser = securityUtil.getCurrentUser();
        Employee currentEmployee = currentUser != null
                ? employeeRepository.findByUserId(currentUser.getId()).orElse(null)
                : null;
        return currentEmployee != null && employeeId != null && currentEmployee.getId().equals(employeeId);
    }

    @Override
    @Transactional(readOnly = true)
    public AttendanceResponse getMyTodayAttendance() {
        User currentUser = securityUtil.getCurrentUser();
        if (currentUser == null) {
            return null;
        }
        // Scoped to the active company: findByEmployeeIdAndAttendanceDate below carries no company predicate, so
        // resolving another tenant's employee record read that tenant's attendance.
        Long myCompanyId = securityUtil.getCurrentCompanyId();
        Employee employee = myCompanyId != null
                ? employeeRepository.findByUserIdAndCompanyId(currentUser.getId(), myCompanyId).orElse(null)
                : null;
        if (employee == null) {
            return null;
        }
        LocalDate today = LocalDate.now();
        List<Attendance> attendances = attendanceRepository
                .findByEmployeeIdAndAttendanceDate(employee.getId(), today);
        if (!attendances.isEmpty()) {
            return AttendanceMapper.toResponse(attendances.get(attendances.size() - 1));
        }

        // A night shift started yesterday and not checked out is still current, so it can be checked out after midnight.
        LocalDate yesterday = today.minusDays(1);
        List<Attendance> previous = attendanceRepository
                .findByEmployeeIdAndAttendanceDate(employee.getId(), yesterday);
        if (!previous.isEmpty()) {
            Attendance last = previous.get(previous.size() - 1);
            // The employee is now known to be in myCompanyId, so use that directly rather than deriving the
            // company from the employee row (which is what let this method run in another tenant).
            Long companyId = myCompanyId;
            if (last.getCheckInTime() != null && last.getCheckOutTime() == null
                    && isNightShiftOn(companyId, employee.getId(), yesterday)) {
                return AttendanceMapper.toResponse(last);
            }
        }
        return null;
    }

    @Override
    @Transactional(readOnly = true)
    public Page<AttendanceResponse> getMyRecords(Pageable pageable) {
        User currentUser = securityUtil.getCurrentUser();
        Employee employee = currentUser != null
            ? employeeRepository.findByUserId(currentUser.getId()).orElse(null)
            : null;
        if (employee == null) {
            return Page.empty(pageable);
        }
        Long companyId = securityUtil.getCurrentCompanyId();
        return attendanceRepository.findByCompanyIdAndEmployeeId(companyId, employee.getId(), pageable)
            .map(AttendanceMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public MyAttendanceMonthlySummaryResponse getMyMonthlySummary(int year, int month) {
        MyAttendanceMonthlySummaryResponse summary = new MyAttendanceMonthlySummaryResponse();
        summary.setYear(year);
        summary.setMonth(month);

        User currentUser = securityUtil.getCurrentUser();
        Long companyId = securityUtil.getCurrentCompanyId();
        // Scoped to the active company, and companyId is passed on to findByEmployeeAndDateRange and
        // findApprovedOverlapping below, so another tenant's employee record cannot mix that tenant's attendance and
        // leave into this company's holidays and shifts.
        Employee employee = currentUser != null && companyId != null
            ? employeeRepository.findByUserIdAndCompanyId(currentUser.getId(), companyId).orElse(null)
            : null;
        if (employee == null) {
            summary.setWorkedHours(BigDecimal.ZERO);
            return summary;
        }

        LocalDate monthStart = LocalDate.of(year, month, 1);
        LocalDate monthEnd = monthStart.with(TemporalAdjusters.lastDayOfMonth());
        LocalDate today = LocalDate.now();
        LocalDate elapsedEnd = monthEnd.isAfter(today) ? today : monthEnd;

        List<Attendance> records = attendanceRepository.findByEmployeeAndDateRange(companyId, employee.getId(), monthStart, monthEnd);
        BigDecimal workedHours = BigDecimal.ZERO;
        int present = 0, absent = 0, halfDay = 0;
        for (Attendance a : records) {
            if (a.getStatus() == AttendanceStatus.PRESENT || a.getStatus() == AttendanceStatus.LATE
                    || a.getStatus() == AttendanceStatus.WORK_FROM_HOME) {
                present++;
            } else if (a.getStatus() == AttendanceStatus.ABSENT) {
                absent++;
            } else if (a.getStatus() == AttendanceStatus.HALF_DAY) {
                halfDay++;
            }
            if (a.getTotalWorkingHours() != null) {
                workedHours = workedHours.add(a.getTotalWorkingHours());
            }
        }
        summary.setPresentDays(present);
        summary.setAbsentDays(absent);
        summary.setHalfDays(halfDay);
        summary.setWorkedHours(workedHours);

        summary.setHolidayDays(holidayRepository.findByCompanyAndDateRange(companyId, monthStart, monthEnd).size());

        List<LeaveRequest> approvedLeave = leaveRequestRepository.findApprovedOverlapping(
            companyId, employee.getId(), LeaveRequestStatus.APPROVED, monthStart, monthEnd);
        int onLeaveDays = 0;
        for (LeaveRequest lr : approvedLeave) {
            LocalDate start = lr.getStartDate().isBefore(monthStart) ? monthStart : lr.getStartDate();
            LocalDate end = lr.getEndDate().isAfter(monthEnd) ? monthEnd : lr.getEndDate();
            if (!end.isBefore(start)) {
                onLeaveDays += (int) (java.time.temporal.ChronoUnit.DAYS.between(start, end) + 1);
            }
        }
        summary.setOnLeaveDays(onLeaveDays);

        // Resolve the shift per day - it may have changed during the month.
        Map<Long, Set<DayOfWeek>> offDaysByAssignment = new HashMap<>();
        int weekOffDays = 0;
        for (LocalDate d = monthStart; !d.isAfter(elapsedEnd); d = d.plusDays(1)) {
            EmployeeShiftAssignment assignment = shiftAssignmentRepository
                .findEffectiveOn(companyId, employee.getId(), d)
                .orElse(null);
            Set<DayOfWeek> offDays = assignment == null
                ? WeeklyOffDays.parse(null)
                : offDaysByAssignment.computeIfAbsent(assignment.getId(),
                    k -> WeeklyOffDays.parse(assignment.getShift().getWeeklyOffDays()));
            if (offDays.contains(d.getDayOfWeek())) {
                weekOffDays++;
            }
        }
        summary.setWeekOffDays(weekOffDays);

        return summary;
    }

    @Override
    @Transactional
    public AttendanceResponse checkIn(AttendanceCheckInRequest request) {
        Long companyId = securityUtil.getCurrentCompanyId();

        Long empId = request.getEmployeeId();
        if (empId == null) {
            User currentUser = securityUtil.getCurrentUser();
            if (currentUser != null) {
                Employee emp = employeeRepository.findByUserId(currentUser.getId()).orElse(null);
                if (emp != null) {
                    empId = emp.getId();
                }
            }
        }
        if (empId == null) {
            throw new ResourceNotFoundException("Employee not found");
        }

        // employeeId comes from the request body, so without this any employee could clock a colleague in by passing their id.
        requireUpdateOrOwn(empId);

        // Only HR recording for someone else may supply times; self-service clocks use server time so they cannot be backdated.
        boolean trustClient = !isSelf(empId)
                && authorizationService.hasPermission(PermissionCode.ATTENDANCE_UPDATE);

        // requireUpdateOrOwn never checks the target is in the caller's tenant, so an unscoped findById would let ATTENDANCE_UPDATE clock another company's employee by id.
        // companyId is null only for the platform-admin case with no tenant context, where scoping is meaningless.
        Employee employee = companyId != null
                ? employeeRepository.findByIdAndCompanyId(empId, companyId)
                        .orElseThrow(() -> new ResourceNotFoundException("Employee not found"))
                : employeeRepository.findById(empId)
                        .orElseThrow(() -> new ResourceNotFoundException("Employee not found"));

        if (companyId == null && employee.getCompany() != null) {
            companyId = employee.getCompany().getId();
        }

        BiometricDevice device = null;
        if (request.getDeviceId() != null) {
            device = deviceRepository.findByIdAndCompanyId(request.getDeviceId(), companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Device not found"));
        }

        LocalDate today = LocalDate.now();
        List<Attendance> existingList = attendanceRepository
                .findByEmployeeIdAndAttendanceDate(empId, today);

        Attendance attendance;
        if (!existingList.isEmpty()) {
            attendance = existingList.get(0);

            if (attendance.getCheckInTime() != null) {
                throw new BadRequestException("You have already checked in today.");
            }
            // Overrides the nightly absentee job's ABSENT row, which would otherwise keep saying ABSENT with a check-in time on it; applyLateDetection may narrow this to LATE.
            attendance.setStatus(AttendanceStatus.PRESENT);
        } else {
            attendance = Attendance.builder()
                    .companyId(companyId)
                    .employee(employee)
                    .attendanceDate(today)
                    .shiftType(shiftTypeOn(companyId, empId, today))
                    .status(AttendanceStatus.PRESENT)
                    .build();
        }

        java.time.LocalTime checkInTime = trustClient && request.getCheckInTime() != null
                ? request.getCheckInTime() : java.time.LocalTime.now();
        AttendanceMethod method = resolveMethod(request.getMethod(), trustClient);

        attendance.checkIn(checkInTime, method, device);
        attendance.setVerificationScore(trustClient ? request.getVerificationScore() : 0);

        applyLateDetection(attendance, companyId, empId, checkInTime);

        // Persisted, not just read. The entity has carried these three columns and this reason all along and nothing
        // ever wrote them, so every record reported a blank location - and once a punch can be flagged for being too
        // far away, storing the distance without the coordinates that produced it leaves the flag unauditable.
        attendance.setCheckInLatitude(request.getLatitude());
        attendance.setCheckInLongitude(request.getLongitude());
        attendance.setCheckInLocation(request.getLocation());
        attendance.setCheckInReason(request.getReason());

        AttendanceLocationSettings locationSettings = attendanceLocationSettingsService.getOrCreate(companyId);
        applyLocationCheck(attendance, locationSettings, request.getLatitude(), request.getLongitude(), method);

        // Only a URL of a file actually uploaded to this app, by this company, is accepted - the same guard every
        // other file-URL column on this backend uses. Validated before the save, so a bogus URL leaves no row.
        String selfieUrl = FileReferencePolicy.requireOwn(request.getSelfieUrl(), attendance.getCheckInSelfieUrl());
        // Only a GPS punch is asked for a selfie. A fingerprint or RFID terminal has no camera and no coordinates,
        // so requiring one locked those companies out of checking in entirely the moment they turned enforcement on -
        // and the geofence beside this already exempts them for exactly the same reason.
        if (locationSettings.isGpsEnforcementEnabled() && method == AttendanceMethod.GPS
                && (selfieUrl == null || selfieUrl.isBlank())) {
            throw new BadRequestException("A selfie is required to check in.");
        }
        attendance.setCheckInSelfieUrl(selfieUrl);

        // A flagged location overrides whatever the client claimed; otherwise the client's own verified flag
        // (a biometric match result posted by HR or a terminal) still applies under the usual trustClient rule.
        attendance.setVerified(!attendance.isLocationFlagged() && trustClient && request.isVerified());

        // The (employee, date) unique constraint catches a concurrent double check-in.
        try {
            attendance = attendanceRepository.saveAndFlush(attendance);
        } catch (DataIntegrityViolationException ex) {
            throw new BadRequestException("You have already checked in today.");
        }
        return AttendanceMapper.toResponse(attendance);
    }

    /**
     * Flags the attendance row when the punch is outside the company's configured office radius.
     *
     * <p>Out of range is <b>recorded and flagged, never refused</b> - a wrong GPS fix must not be able to stop
     * somebody working, so this only ever writes data the reviewer reads. A no-op unless the company turned
     * enforcement on and gave office coordinates, and a kiosk punch (RFID, fingerprint) that has no coordinates to
     * give is not held against the employee - only a GPS punch arriving without them is.
     */
    private void applyLocationCheck(Attendance attendance, AttendanceLocationSettings settings,
                                     String latitude, String longitude, AttendanceMethod method) {
        if (!settings.isGpsEnforcementEnabled()
                || settings.getOfficeLatitude() == null || settings.getOfficeLongitude() == null) {
            return;
        }

        boolean hasCoords = latitude != null && !latitude.isBlank()
                && longitude != null && !longitude.isBlank();
        if (!hasCoords) {
            if (method == AttendanceMethod.GPS) {
                raiseLocationFlag(attendance, "Location was not provided.");
            }
            return;
        }

        try {
            double lat = Double.parseDouble(latitude);
            double lng = Double.parseDouble(longitude);
            double distance = GeoUtils.distanceMeters(lat, lng,
                    settings.getOfficeLatitude(), settings.getOfficeLongitude());
            attendance.setDistanceFromOfficeMeters(distance);

            if (distance > settings.getRadiusMeters()) {
                raiseLocationFlag(attendance, String.format(
                        "%.0fm from the office (allowed radius %dm).", distance, settings.getRadiusMeters()));
            }
            // An in-range punch deliberately does NOT clear the flag. This runs on check-out as well as check-in,
            // so clearing it let somebody punch in 11km away, punch out at the desk and end the day unflagged -
            // which defeats the only thing the flag is for. The row records that a punch that day was out of place;
            // only someone deliberately amending the record should be able to take that back.
        } catch (NumberFormatException e) {
            raiseLocationFlag(attendance, "Location could not be read.");
        }
    }

    /**
     * Flags the row, keeping any reason already on it. The first offence of the day is the interesting one and there
     * is a single reason column, so a later flag does not overwrite what the earlier one said.
     */
    private void raiseLocationFlag(Attendance attendance, String reason) {
        if (attendance.isLocationFlagged() && attendance.getLocationFlagReason() != null) {
            return;
        }
        attendance.setLocationFlagged(true);
        attendance.setLocationFlagReason(reason);
    }

    /**
     * The recorded method label, held to the same standard as {@code verified} and {@code verificationScore} above.
     *
     * <p>{@code method} arrives in the request body, and nothing on this path consults a matcher or a terminal, so a
     * self-service client could stamp its own row {@code FINGERPRINT} and produce a record claiming a biometric
     * check-in that never happened. Any {@linkplain AttendanceMethod#isDeviceBacked() device-backed} method is
     * therefore <b>downgraded to MANUAL</b> unless the caller is the same trusted actor that is already allowed to
     * supply times and verification results - HR recording for someone else with {@code ATTENDANCE_UPDATE}, which is
     * how the biometric terminals post. Downgrading rather than rejecting keeps existing mobile clients that send a
     * hopeful {@code FINGERPRINT} working: the punch is still recorded, just labelled for what the server can vouch
     * for.
     */
    static AttendanceMethod resolveMethod(AttendanceMethod requested, boolean trustClient) {
        if (requested == null) {
            return AttendanceMethod.MANUAL;
        }
        return !trustClient && requested.isDeviceBacked() ? AttendanceMethod.MANUAL : requested;
    }

    private ShiftType shiftTypeOn(Long companyId, Long employeeId, LocalDate date) {
        return shiftAssignmentRepository.findEffectiveOn(companyId, employeeId, date)
                .map(a -> a.getShift().getShiftType())
                .orElse(null);
    }

    private boolean isNightShiftOn(Long companyId, Long employeeId, LocalDate date) {
        if (employeeId == null || date == null) return false;
        return shiftAssignmentRepository.findEffectiveOn(companyId, employeeId, date)
                .map(a -> a.getShift().isNightShift())
                .orElse(false);
    }

    /** Marks LATE when check-in exceeds shift start + grace; a no-op without an active shift assignment, so a manual HR override survives. */
    private void applyLateDetection(Attendance attendance, Long companyId, Long employeeId,
                                     java.time.LocalTime checkInTime) {
        if (checkInTime == null) return;

        LocalDate onDate = attendance.getAttendanceDate() != null ? attendance.getAttendanceDate() : LocalDate.now();
        EmployeeShiftAssignment shiftAssignment = shiftAssignmentRepository
                .findEffectiveOn(companyId, employeeId, onDate)
                .orElse(null);
        if (shiftAssignment == null) return;

        long lateMinutes = java.time.temporal.ChronoUnit.MINUTES
                .between(shiftAssignment.getShift().getStartTime(), checkInTime);
        // Normalise across midnight: a 23:50 check-in for a 00:00 shift is 10 minutes early, not 1430 late.
        if (lateMinutes > 720) {
            lateMinutes -= 1440;
        } else if (lateMinutes <= -720) {
            lateMinutes += 1440;
        }

        if (lateMinutes > shiftAssignment.getShift().getGracePeriodMinutes()) {
            attendance.setLate(true);
            attendance.setLateMinutes(lateMinutes);
            attendance.setStatus(AttendanceStatus.LATE);
        } else {
            attendance.setLate(false);
            attendance.setLateMinutes(0);
        }
    }

    @Override
    @Transactional
    public AttendanceResponse checkOut(Long attendanceId, AttendanceCheckOutRequest request) {
        Attendance attendance = attendanceRepository.findByIdAndCompanyId(attendanceId, securityUtil.getCurrentCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Attendance not found"));

        // The id comes straight from the caller, so without this an employee could check out somebody else's record by guessing an id.
        Long ownerId = attendance.getEmployee() != null ? attendance.getEmployee().getId() : null;
        requireUpdateOrOwn(ownerId);
        boolean trustClient = !isSelf(ownerId)
                && authorizationService.hasPermission(PermissionCode.ATTENDANCE_UPDATE);

        // A check-out with no check-in is what the "ABSENT with an out time" rows are: an OUT time, no IN time, zero hours. Refuse rather than persist it.
        if (attendance.getCheckInTime() == null) {
            throw new BadRequestException("You have not checked in today, so there is nothing to check out from.");
        }
        if (attendance.getCheckOutTime() != null) {
            throw new BadRequestException("You have already checked out today.");
        }

        BiometricDevice device = null;
        if (request.getDeviceId() != null) {
            device = deviceRepository.findByIdAndCompanyId(request.getDeviceId(), securityUtil.getCurrentCompanyId())
                    .orElseThrow(() -> new ResourceNotFoundException("Device not found"));
        }

        java.time.LocalTime checkOutTime = trustClient && request.getCheckOutTime() != null
                ? request.getCheckOutTime() : java.time.LocalTime.now();
        AttendanceMethod method = resolveMethod(request.getMethod(), trustClient);

        // A night shift legitimately checks out after midnight, i.e. "before" check-in.
        if (checkOutTime.isBefore(attendance.getCheckInTime())
                && !isNightShiftOn(securityUtil.getCurrentCompanyId(), ownerId, attendance.getAttendanceDate())) {
            throw new BadRequestException("Check-out time cannot be earlier than the check-in time.");
        }

        attendance.checkOut(checkOutTime, method, device);

        // Same as check-in: these were declared, sent by the app on every punch and never written. The early-departure
        // reason is the starkest of them - the identically named field on the HR manual-entry DTO IS read, which is
        // probably why nobody noticed that an employee's own explanation was being dropped.
        attendance.setCheckOutLatitude(request.getLatitude());
        attendance.setCheckOutLongitude(request.getLongitude());
        attendance.setCheckOutLocation(request.getLocation());
        if (request.getEarlyDepartureReason() != null && !request.getEarlyDepartureReason().isBlank()) {
            attendance.setEarlyDepartureReason(request.getEarlyDepartureReason());
        }

        AttendanceLocationSettings locationSettings =
                attendanceLocationSettingsService.getOrCreate(attendance.getCompanyId());
        applyLocationCheck(attendance, locationSettings, request.getLatitude(), request.getLongitude(), method);
        // No selfie requirement here even with enforcement on: somebody already inside for the day must not be
        // locked out because a camera failed. Still validated when one is sent.
        attendance.setCheckOutSelfieUrl(
                FileReferencePolicy.requireOwn(request.getSelfieUrl(), attendance.getCheckOutSelfieUrl()));

        if (attendance.getCheckInTime() != null && attendance.getCheckOutTime() != null) {
            BigDecimal totalHours = attendance.calculateTotalHours();
            attendance.setTotalWorkingHours(totalHours);
        }

        attendance = attendanceRepository.save(attendance);
        return AttendanceMapper.toResponse(attendance);
    }

    @Override
    @Transactional(readOnly = true)
    public AttendanceResponse getById(Long id) {
        Attendance attendance = attendanceRepository.findByIdAndCompanyId(id, securityUtil.getCurrentCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Attendance not found"));
        requireViewOrOwn(attendance.getEmployee() != null ? attendance.getEmployee().getId() : null);
        return AttendanceMapper.toResponse(attendance);
    }

    @Override
    @Transactional(readOnly = true)
    public AttendanceResponse getByEmployeeAndDate(Long employeeId, LocalDate date) {
        requireViewOrOwn(employeeId);
        List<Attendance> attendances = attendanceRepository.findByEmployeeIdAndAttendanceDate(employeeId, date);
        if (attendances.isEmpty()) {
            throw new ResourceNotFoundException("Attendance not found");
        }
        return AttendanceMapper.toResponse(attendances.get(0));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<AttendanceResponse> getByEmployee(Long employeeId, Pageable pageable) {
        requireViewOrOwn(employeeId);
        Long companyId = securityUtil.getCurrentCompanyId();
        return attendanceRepository.findByCompanyIdAndEmployeeId(companyId, employeeId, pageable)
                .map(AttendanceMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<AttendanceResponse> getByCompanyAndDateRange(LocalDate start, LocalDate end, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.ATTENDANCE_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return attendanceRepository.findByCompanyIdAndAttendanceDateBetween(companyId, start, end, pageable)
                .map(AttendanceMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<AttendanceResponse> getByStatus(AttendanceStatus status, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.ATTENDANCE_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return attendanceRepository.findByCompanyIdAndStatus(companyId, status, pageable)
                .map(AttendanceMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<AttendanceResponse> listAll(AttendanceStatus status, LocalDate date, LocalDate startDate, LocalDate endDate, String search, Pageable pageable) {
        Long companyId = securityUtil.getCurrentCompanyId();
        boolean isHrOrAdmin = authorizationService.hasPermission(PermissionCode.ATTENDANCE_VIEW);

        if (!isHrOrAdmin) {
            User currentUser = securityUtil.getCurrentUser();
            Employee currentEmployee = currentUser != null
                    ? employeeRepository.findByUserId(currentUser.getId()).orElse(null)
                    : null;
            if (currentEmployee == null) {
                return Page.empty(pageable);
            }
            return attendanceRepository.findByCompanyIdAndEmployeeId(companyId, currentEmployee.getId(), pageable)
                    .map(AttendanceMapper::toResponse);
        }

        boolean hasSearch = search != null && !search.trim().isEmpty();
        boolean hasStatus = status != null;
        boolean hasDate = date != null;
        boolean hasStart = startDate != null;
        boolean hasEnd = endDate != null;

        LocalDate start = hasDate ? date : (hasStart ? startDate : null);
        LocalDate end = hasDate ? date : (hasEnd ? endDate : null);

        if (!hasSearch) {
            if (!hasStatus && start == null && end == null) {
                return attendanceRepository.findByCompanyId(companyId, pageable)
                        .map(AttendanceMapper::toResponse);
            }
            if (hasStatus && start == null && end == null) {
                return attendanceRepository.findByCompanyIdAndStatus(companyId, status, pageable)
                        .map(AttendanceMapper::toResponse);
            }
            if (!hasStatus && (start != null || end != null)) {
                LocalDate s = start != null ? start : LocalDate.of(1970, 1, 1);
                LocalDate e = end != null ? end : LocalDate.of(2099, 12, 31);
                return attendanceRepository.findByCompanyIdAndAttendanceDateBetween(companyId, s, e, pageable)
                        .map(AttendanceMapper::toResponse);
            }
            if (hasStatus && (start != null || end != null)) {
                LocalDate s = start != null ? start : LocalDate.of(1970, 1, 1);
                LocalDate e = end != null ? end : LocalDate.of(2099, 12, 31);
                return attendanceRepository.searchByStatusAndDateRange(companyId, status, s, e, pageable)
                        .map(AttendanceMapper::toResponse);
            }
        }

        String searchKeyword = search.trim();
        LocalDate s = start != null ? start : LocalDate.of(1970, 1, 1);
        LocalDate e = end != null ? end : LocalDate.of(2099, 12, 31);
        if (hasStatus) {
            return attendanceRepository.searchAttendanceRecordsWithStatusAndDate(companyId, status, s, e, searchKeyword, pageable)
                    .map(AttendanceMapper::toResponse);
        } else {
            return attendanceRepository.searchAttendanceRecordsWithoutStatusAndDate(companyId, s, e, searchKeyword, pageable)
                    .map(AttendanceMapper::toResponse);
        }
    }

    @Override
    @Transactional(readOnly = true)
    public List<AttendanceResponse> getLateAttendances(LocalDate date) {
        authorizationService.checkPermission(PermissionCode.ATTENDANCE_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return attendanceRepository.findLateAttendances(companyId, date)
                .stream()
                .map(AttendanceMapper::toResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public List<AttendanceResponse> getAbsentees(LocalDate date) {
        authorizationService.checkPermission(PermissionCode.ATTENDANCE_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return attendanceRepository.findByCompanyIdAndStatusAndAttendanceDateBetween(
                companyId, AttendanceStatus.ABSENT, date, date)
                .stream()
                .map(AttendanceMapper::toResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public long countPresent(Long companyId, LocalDate date) {
        return attendanceRepository.countByCompanyIdAndStatusAndDate(companyId, AttendanceStatus.PRESENT, date);
    }

    @Override
    @Transactional(readOnly = true)
    public long countLate(Long companyId, LocalDate date) {
        return attendanceRepository.countByCompanyIdAndStatusAndDate(companyId, AttendanceStatus.LATE, date);
    }

    @Override
    @Transactional(readOnly = true)
    public long countAbsent(Long companyId, LocalDate date) {
        return attendanceRepository.countByCompanyIdAndStatusAndDate(companyId, AttendanceStatus.ABSENT, date);
    }

    @Override
    @Transactional
    public void updateStatus(Long id, AttendanceStatus status) {
        authorizationService.checkPermission(PermissionCode.ATTENDANCE_APPROVE);
        Attendance attendance = attendanceRepository.findByIdAndCompanyId(id, securityUtil.getCurrentCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Attendance not found"));
        attendance.setStatus(status);
        attendanceRepository.save(attendance);
    }

    @Override
    @Transactional
    public void approveAttendance(Long id, String approverName) {
        authorizationService.checkPermission(PermissionCode.ATTENDANCE_APPROVE);
        Attendance attendance = attendanceRepository.findByIdAndCompanyId(id, securityUtil.getCurrentCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Attendance not found"));
        attendance.setApproved(true);
        attendance.setApprovedBy(approverName);
        attendance.setApprovedDateTime(LocalDateTime.now());
        attendanceRepository.save(attendance);
    }

    @Override
    @Transactional
    public AttendanceResponse delete(Long id) {
        authorizationService.checkPermission(PermissionCode.ATTENDANCE_APPROVE);
        Attendance attendance = attendanceRepository.findByIdAndCompanyId(id, securityUtil.getCurrentCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Attendance not found"));
        attendance.softDelete();
        attendanceRepository.save(attendance);
        return AttendanceMapper.toResponse(attendance);
    }

    @Override
    @Transactional
    public AttendanceResponse createManual(AttendanceRequest request) {
        authorizationService.checkPermission(PermissionCode.ATTENDANCE_MARK);
        Long companyId = securityUtil.getCurrentCompanyId();
        // Same cross-tenant IDOR as checkIn(): an unscoped findById on the caller-supplied employeeId would let ATTENDANCE_MARK write another company's attendance.
        Employee employee = employeeRepository.findByIdAndCompanyId(request.getEmployeeId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Employee not found"));

        List<Attendance> existingList = attendanceRepository
                .findByEmployeeIdAndAttendanceDate(request.getEmployeeId(), request.getAttendanceDate());

        Attendance attendance;
        if (!existingList.isEmpty()) {
            attendance = existingList.get(0);
            if (request.getStatus() != null) attendance.setStatus(request.getStatus());
            if (request.getCheckInTime() != null) attendance.setCheckInTime(request.getCheckInTime());
            if (request.getCheckOutTime() != null) attendance.setCheckOutTime(request.getCheckOutTime());
            if (request.getCheckInMethod() != null) attendance.setCheckInMethod(request.getCheckInMethod());
            if (request.getCheckOutMethod() != null) attendance.setCheckOutMethod(request.getCheckOutMethod());
            if (request.getShiftType() != null) attendance.setShiftType(request.getShiftType());
            if (request.getOvertimeHours() != null) {
                attendance.setOvertimeHours(request.getOvertimeHours());
                attendance.setOvertime(request.getOvertimeHours().signum() > 0);
            }
            if (request.getLateReason() != null) attendance.setLateReason(request.getLateReason());
            if (request.isLeftEarly()) {
                attendance.setLeftEarly(true);
                attendance.setEarlyMinutes(request.getEarlyMinutes());
                attendance.setEarlyDepartureReason(request.getEarlyDepartureReason());
            }
            if (request.getAdminNotes() != null) attendance.setAdminNotes(request.getAdminNotes());
        } else {
            attendance = Attendance.builder()
                    .companyId(companyId)
                    .employee(employee)
                    .attendanceDate(request.getAttendanceDate())
                    .status(request.getStatus() != null ? request.getStatus() : AttendanceStatus.PRESENT)
                    .checkInTime(request.getCheckInTime())
                    .checkOutTime(request.getCheckOutTime())
                    .checkInMethod(request.getCheckInMethod())
                    .checkOutMethod(request.getCheckOutMethod())
                    .shiftType(request.getShiftType() != null ? request.getShiftType()
                            : shiftTypeOn(companyId, request.getEmployeeId(), request.getAttendanceDate()))
                    .overtimeHours(request.getOvertimeHours())
                    .isOvertime(request.getOvertimeHours() != null && request.getOvertimeHours().signum() > 0)
                    .isLate(request.isLate())
                    .lateMinutes(request.getLateMinutes())
                    .lateReason(request.getLateReason())
                    .leftEarly(request.isLeftEarly())
                    .earlyMinutes(request.getEarlyMinutes())
                    .earlyDepartureReason(request.getEarlyDepartureReason())
                    .adminNotes(request.getAdminNotes())
                    .isVerified(true)
                    .build();
        }

        applyLateDetection(attendance, companyId, request.getEmployeeId(), attendance.getCheckInTime());
        if (attendance.isLate() && attendance.getStatus() != AttendanceStatus.LATE) {
            attendance.setStatus(AttendanceStatus.LATE);
        }

        if (attendance.getCheckInTime() != null && attendance.getCheckOutTime() != null) {
            BigDecimal totalHours = attendance.calculateTotalHours();
            attendance.setTotalWorkingHours(totalHours);
        }

        attendance = attendanceRepository.save(attendance);
        return AttendanceMapper.toResponse(attendance);
    }
}