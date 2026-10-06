package com.zuhoocms.modules.hrm.attendance.shift;

import com.zuhoocms.modules.company.Company;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.security.SecurityUtil;
import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor

public class ShiftServiceImpl implements ShiftService {

    private final ShiftRepository shiftRepository;
    private final com.zuhoocms.modules.hrm.employee.EmployeeRepository employeeRepository;
    private final SecurityUtil    securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    @Transactional
    public ShiftResponse create(ShiftRequest request) {
        authorizationService.checkPermission(PermissionCode.SHIFT_CREATE);
        Long companyId = requireCompanyId();
        if (shiftRepository.existsByCompanyIdAndName(companyId, request.getName())) {
            throw new BadRequestException("Shift '" + request.getName() + "' already exists");
        }
        validateTimes(request);
        Shift s = Shift.builder()
            .name(request.getName())
            .shiftType(request.getShiftType())
            .startTime(request.getStartTime())
            .endTime(request.getEndTime())
            .gracePeriodMinutes(request.getGracePeriodMinutes() != null ? request.getGracePeriodMinutes() : 10)
            // Must match Shift.weeklyOffDays' own default; this was "SAT,SUN", a dormant but confusing mismatch.
            .weeklyOffDays(request.getWeeklyOffDays() != null ? request.getWeeklyOffDays() : "FRI,SAT")
            .flexible(request.isFlexible())
            .nightShift(request.isNightShift())
            .workingMinutes(workingMinutes(request))
            .description(request.getDescription())
            .notes(request.getNotes())
            .company(companyRef(companyId))
            .build();
        shiftRepository.save(s);
        return ShiftMapper.toShiftResponse(s);
    }

    @Override
    @Transactional(readOnly = true)
    public ShiftResponse getById(Long id) {
        authorizationService.checkPermission(PermissionCode.SHIFT_VIEW);
        return ShiftMapper.toShiftResponse(findInTenant(id));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ShiftResponse> listAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.SHIFT_VIEW);
        return shiftRepository.findByCompanyId(requireCompanyId(), pageable)
            .map(ShiftMapper::toShiftResponse);
    }

    // Deliberately NOT gated by SHIFT_VIEW: the shift picker is needed by users with EMPLOYEE_UPDATE/SHIFT_ASSIGNMENT_VIEW only.
    @Override
    @Transactional(readOnly = true)
    public List<ShiftResponse> listActive() {
        return shiftRepository.findByCompanyIdAndActiveTrue(requireCompanyId())
            .stream().map(ShiftMapper::toShiftResponse).toList();
    }

    @Override
    @Transactional
    public ShiftResponse update(Long id, ShiftRequest request) {
        authorizationService.checkPermission(PermissionCode.SHIFT_UPDATE);
        Shift s = findInTenant(id);
        validateTimes(request);
        s.setName(request.getName());
        s.setShiftType(request.getShiftType());
        s.setStartTime(request.getStartTime());
        s.setEndTime(request.getEndTime());
        if (request.getGracePeriodMinutes() != null) s.setGracePeriodMinutes(request.getGracePeriodMinutes());
        if (request.getWeeklyOffDays() != null) s.setWeeklyOffDays(request.getWeeklyOffDays());
        s.setFlexible(request.isFlexible());
        s.setNightShift(request.isNightShift());
        s.setWorkingMinutes(workingMinutes(request));
        s.setDescription(request.getDescription());
        s.setNotes(request.getNotes());
        return ShiftMapper.toShiftResponse(s);
    }

    @Override
    @Transactional
    public ShiftResponse toggleActive(Long id) {
        authorizationService.checkPermission(PermissionCode.SHIFT_UPDATE);
        Shift s = findInTenant(id);
        s.setActive(!s.isActive());
        return ShiftMapper.toShiftResponse(s);
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.SHIFT_DELETE);
        Shift shift = findInTenant(id);
        long assignedEmployees = employeeRepository.countByShiftId(id);
        if (assignedEmployees > 0) {
            throw new BadRequestException(
                "Cannot delete this shift: it is currently assigned to " + assignedEmployees
                    + " employee(s). Reassign them first.");
        }
        shift.softDelete();
    }

    private void validateTimes(ShiftRequest request) {
        if (!request.isNightShift() && request.getStartTime() != null && request.getEndTime() != null
                && !request.getEndTime().isAfter(request.getStartTime())) {
            throw new BadRequestException("End time must be after start time unless this is a night shift");
        }
    }

    private long workingMinutes(ShiftRequest request) {
        if (request.getStartTime() == null || request.getEndTime() == null) return 0;
        long minutes = java.time.temporal.ChronoUnit.MINUTES.between(request.getStartTime(), request.getEndTime());
        // Night shifts end the next day.
        return minutes <= 0 ? minutes + 1440 : minutes;
    }

    private Shift findInTenant(Long id) {
        return shiftRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Shift not found: " + id));
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    private Company companyRef(Long companyId) {
        Company c = new Company(); c.setId(companyId); return c;
    }
}
