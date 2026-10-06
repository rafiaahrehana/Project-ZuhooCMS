package com.zuhoocms.modules.hrm.attendance.biometric.data;
import com.zuhoocms.modules.hrm.attendance.biometric.device.BiometricDevice;
import com.zuhoocms.modules.hrm.attendance.biometric.device.BiometricDeviceRepository;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.LocalDateTime;
import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class EmployeeBiometricServiceImpl implements EmployeeBiometricService {

    private final EmployeeBiometricDataRepository biometricDataRepository;
    private final EmployeeRepository employeeRepository;
    private final BiometricDeviceRepository deviceRepository;
    private final AuthorizationService authorizationService;
    private final SecurityUtil securityUtil;
    private final com.zuhoocms.modules.hrm.attendance.biometric.verification.BiometricMatcher matcher;

    private void requireViewOrOwn(Long employeeId) {
        // findById is scoped by the request-level Hibernate tenant filter; hasPermission() alone says nothing about which company the target employeeId is in.
        boolean sameTenantEmployee = employeeId != null && employeeRepository.findById(employeeId).isPresent();
        if (sameTenantEmployee && authorizationService.hasPermission(PermissionCode.BIOMETRIC_VIEW)) {
            return;
        }
        User currentUser = securityUtil.getCurrentUser();
        Employee currentEmployee = currentUser != null
                ? employeeRepository.findByUserId(currentUser.getId()).orElse(null)
                : null;
        if (currentEmployee == null || employeeId == null || !currentEmployee.getId().equals(employeeId)) {
            throw new ForbiddenException("Access denied: you can only access your own biometric enrollment");
        }
    }

    // EmployeeBiometricData has no company_id or tenant filter, so a lookup by its own id must verify ownership, or any user could read another company's biometric templates by id.
    private void requireSameTenant(EmployeeBiometricData data) {
        Long companyId = securityUtil.getCurrentCompanyId();
        Employee employee = data.getEmployee();
        if (companyId == null || employee == null || employee.getCompany() == null
                || !companyId.equals(employee.getCompany().getId())) {
            throw new ForbiddenException("Access denied: biometric enrollment belongs to a different company");
        }
    }

    @Override
    @Transactional
    public BiometricDataResponse enrollEmployee(BiometricEnrollmentRequest request) {
        authorizationService.checkPermission(PermissionCode.BIOMETRIC_MANAGE);
        // Both ids come from the request body - scope them to the caller's company so nobody can enroll another tenant's employee or device.
        Long companyId = securityUtil.getCurrentCompanyId();
        Employee employee = employeeRepository.findByIdAndCompanyId(request.getEmployeeId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Employee not found"));

        BiometricDevice device = deviceRepository.findByIdAndCompanyId(request.getDeviceId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Device not found"));

        if (device.isAtCapacity()) {
            throw new BadRequestException("Device is at maximum enrollment capacity");
        }

        EmployeeBiometricData biometricData;
        if (request.getBiometricType() != null && biometricDataRepository.reviveDeleted(
                employee.getId(), device.getId(), request.getBiometricType()) > 0) {
            // A soft-deleted enrollment still holds the unique key; reuse it as a fresh enrollment.
            biometricData = biometricDataRepository
                    .findByEmployeeIdAndDeviceIdAndBiometricType(employee.getId(), device.getId(), request.getBiometricType())
                    .orElseThrow(() -> new ResourceNotFoundException("Enrollment not found"));
            biometricData.setEmployee(employee);
            biometricData.setDevice(device);
            biometricData.setBiometricType(request.getBiometricType());
            biometricData.setBiometricTemplate(request.getBiometricTemplate());
            biometricData.setTemplateFormat(request.getTemplateFormat());
            biometricData.setEnrollmentDate(LocalDateTime.now());
            biometricData.setEnrolledBy(null);
            biometricData.setEnrollmentAttempts(0);
            biometricData.setEnrollmentQualityScore(request.getQualityScore());
            biometricData.setEnrolled(true);
            biometricData.setActive(true);
            biometricData.setLastVerifiedTime(null);
            biometricData.setSuccessfulMatches(0);
            biometricData.setFailedMatches(0);
            biometricData.setNotes(null);
            biometricData.setSecurityNotes(null);
        } else {
            biometricData = EmployeeBiometricData.builder()
                    .employee(employee)
                    .device(device)
                    .biometricType(request.getBiometricType())
                    .biometricTemplate(request.getBiometricTemplate())
                    .templateFormat(request.getTemplateFormat())
                    .enrollmentDate(LocalDateTime.now())
                    .enrollmentQualityScore(request.getQualityScore())
                    .enrolled(true)
                    .active(true)
                    .build();
        }

        biometricData = biometricDataRepository.save(biometricData);

        device.setTotalEnrollments(device.getTotalEnrollments() + 1);
        deviceRepository.save(device);

        return BiometricDataMapper.toResponse(biometricData);
    }

    @Override
    @Transactional(readOnly = true)
    public BiometricDataResponse getEnrollment(Long employeeId, Long deviceId) {
        EmployeeBiometricData data = biometricDataRepository
                .findByEmployeeIdAndDeviceIdAndBiometricType(employeeId, deviceId, "FINGERPRINT")
                .orElseThrow(() -> new ResourceNotFoundException("Enrollment not found"));
        requireSameTenant(data);
        requireViewOrOwn(employeeId);
        return BiometricDataMapper.toResponse(data);
    }

    @Override
    @Transactional(readOnly = true)
    public BiometricDataResponse getById(Long id) {
        EmployeeBiometricData data = biometricDataRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Enrollment not found"));
        requireSameTenant(data);
        requireViewOrOwn(data.getEmployee() != null ? data.getEmployee().getId() : null);
        return BiometricDataMapper.toResponse(data);
    }

    @Override
    @Transactional(readOnly = true)
    public List<BiometricDataResponse> getByEmployee(Long employeeId) {
        requireViewOrOwn(employeeId);
        return biometricDataRepository.findByEmployeeId(employeeId)
                .stream()
                .map(BiometricDataMapper::toResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public boolean verifyBiometric(Long employeeId, Long deviceId, String template, double threshold) {
        authorizationService.checkPermission(PermissionCode.BIOMETRIC_MANAGE);
        // Fails closed before any enrollment is read or any match counter is touched - see BiometricMatcher.
        matcher.requireAvailable();
        EmployeeBiometricData data = biometricDataRepository
                .findByEmployeeIdAndDeviceIdAndBiometricType(employeeId, deviceId, "FINGERPRINT")
                .orElseThrow(() -> new ResourceNotFoundException("Enrollment not found"));
        requireSameTenant(data);

        double matchScore = calculateMatch(data.getBiometricTemplate(), template);

        if (matchScore >= threshold) {
            updateLastVerified(data.getId());
            recordSuccessfulMatch(data.getId());
            return true;
        }
        recordFailedMatch(data.getId());
        return false;
    }

    @Override
    @Transactional
    public boolean verifyBiometric(Long id, String template, double threshold) {
        authorizationService.checkPermission(PermissionCode.BIOMETRIC_MANAGE);
        // Fails closed before any enrollment is read or any match counter is touched - see BiometricMatcher.
        matcher.requireAvailable();
        EmployeeBiometricData data = biometricDataRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Enrollment not found"));
        requireSameTenant(data);

        double matchScore = calculateMatch(data.getBiometricTemplate(), template);

        if (matchScore >= threshold) {
            updateLastVerified(id);
            recordSuccessfulMatch(id);
            return true;
        }
        recordFailedMatch(id);
        return false;
    }

    @Override
    @Transactional
    public void updateEnrollmentStatus(Long id, boolean enrolled) {
        authorizationService.checkPermission(PermissionCode.BIOMETRIC_MANAGE);
        EmployeeBiometricData data = biometricDataRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Enrollment not found"));
        requireSameTenant(data);
        data.setEnrolled(enrolled);
        biometricDataRepository.save(data);
    }

    @Override
    @Transactional
    public void updateLastVerified(Long id) {
        EmployeeBiometricData data = biometricDataRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Enrollment not found"));
        requireSameTenant(data);
        data.setLastVerifiedTime(LocalDateTime.now());
        biometricDataRepository.save(data);
    }

    @Override
    @Transactional
    public void recordSuccessfulMatch(Long id) {
        EmployeeBiometricData data = biometricDataRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Enrollment not found"));
        requireSameTenant(data);
        data.setSuccessfulMatches(data.getSuccessfulMatches() + 1);
        biometricDataRepository.save(data);
    }

    @Override
    @Transactional
    public void recordFailedMatch(Long id) {
        EmployeeBiometricData data = biometricDataRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Enrollment not found"));
        requireSameTenant(data);
        data.setFailedMatches(data.getFailedMatches() + 1);
        biometricDataRepository.save(data);
    }

    @Override
    @Transactional
    public BiometricDataResponse delete(Long id) {
        authorizationService.checkPermission(PermissionCode.BIOMETRIC_MANAGE);
        EmployeeBiometricData data = biometricDataRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Enrollment not found"));
        requireSameTenant(data);
        data.softDelete();
        biometricDataRepository.save(data);
        return BiometricDataMapper.toResponse(data);
    }

    /** Delegates to the one gate; there is no local copy of "matching" any more - see BiometricMatcher for why it is off by default. */
    private double calculateMatch(String template1, String template2) {
        return matcher.score(template1, template2);
    }
}

