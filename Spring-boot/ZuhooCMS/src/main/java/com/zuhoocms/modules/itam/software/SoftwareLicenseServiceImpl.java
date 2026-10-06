package com.zuhoocms.modules.itam.software;

import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.itam.shared.ItamEmployeeGuard;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class SoftwareLicenseServiceImpl implements SoftwareLicenseService {

    /** Statuses on which no new seat may be handed out. */
    private static final Set<LicenseStatus> NON_ASSIGNABLE =
            Set.of(LicenseStatus.EXPIRED, LicenseStatus.SUSPENDED, LicenseStatus.REVOKED);

    private static final int LICENSE_KEY_COLUMN_LENGTH = 255;

    private final SoftwareLicenseRepository licenseRepository;
    private final SoftwareLicenseSeatRepository seatRepository;
    private final EmployeeRepository employeeRepository;
    private final ItamEmployeeGuard employeeGuard;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    private SoftwareLicense findInTenant(Long id) {
        return licenseRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("License not found"));
    }

    private SoftwareLicense lockInTenant(Long id, Long companyId) {
        return licenseRepository.findByIdAndCompanyIdForUpdate(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("License not found"));
    }

    private Long requireCompanyId() {
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) throw new BadRequestException("No company context found in security token");
        return companyId;
    }

    /** licenseKey/accountEmail are credentials-adjacent: only for callers who may edit the licence. */
    private boolean canSeeSecrets() {
        return authorizationService.hasPermission(PermissionCode.SOFTWARE_LICENSE_UPDATE);
    }

    private SoftwareLicenseResponse toResponse(SoftwareLicense license) {
        return SoftwareLicenseMapper.toResponse(license,
                seatRepository.countByLicenseIdAndReleasedAtIsNull(license.getId()), canSeeSecrets());
    }

    private List<SoftwareLicenseResponse> toResponses(List<SoftwareLicense> licenses) {
        Map<Long, Long> counts = activeSeatCounts(licenses.stream().map(SoftwareLicense::getId).toList());
        boolean secrets = canSeeSecrets();
        return licenses.stream()
                .map(l -> SoftwareLicenseMapper.toResponse(l, counts.getOrDefault(l.getId(), 0L), secrets))
                .collect(Collectors.toList());
    }

    private Page<SoftwareLicenseResponse> toResponses(Page<SoftwareLicense> page) {
        Map<Long, Long> counts = activeSeatCounts(page.getContent().stream().map(SoftwareLicense::getId).toList());
        boolean secrets = canSeeSecrets();
        return page.map(l -> SoftwareLicenseMapper.toResponse(l, counts.getOrDefault(l.getId(), 0L), secrets));
    }

    private Map<Long, Long> activeSeatCounts(Collection<Long> licenseIds) {
        Map<Long, Long> counts = new HashMap<>();
        if (licenseIds.isEmpty()) return counts;
        for (Object[] row : seatRepository.countActiveByLicenseIds(licenseIds)) {
            counts.put((Long) row[0], ((Number) row[1]).longValue());
        }
        return counts;
    }

    /** PERPETUAL/OPEN_SOURCE may be free with no expiry; SUBSCRIPTION/TRIAL need both a positive cost and an expiry date. */
    private void validateByType(SoftwareLicenseRequest request) {
        LicenseType type = request.getLicenseType();
        boolean timeLimited = type == LicenseType.SUBSCRIPTION || type == LicenseType.TRIAL;
        if (timeLimited && request.getLicenseExpiryDate() == null) {
            throw new BadRequestException("License expiry date is required for " + type + " licenses");
        }
        if (timeLimited && request.getLicenseCost() != null
                && request.getLicenseCost().compareTo(BigDecimal.ZERO) <= 0) {
            throw new BadRequestException("License cost must be greater than 0 for " + type + " licenses");
        }
    }

    private void requireKeyAvailable(Long companyId, String licenseKey, Long exceptId) {
        // findByCompanyIdAndLicenseKey honours @SQLRestriction(deleted = false), so a soft-deleted licence never blocks key reuse.
        licenseRepository.findByCompanyIdAndLicenseKey(companyId, licenseKey)
                .filter(existing -> !existing.getId().equals(exceptId))
                .ifPresent(existing -> {
                    throw new BadRequestException("License key already exists: " + licenseKey);
                });
    }

    /** A unique-constraint hit the pre-check could not see (race, or a legacy deleted row) is a 400, not a 500/409. */
    private SoftwareLicense saveChecked(SoftwareLicense license) {
        try {
            return licenseRepository.saveAndFlush(license);
        } catch (DataIntegrityViolationException e) {
            throw new BadRequestException("License key already exists: " + license.getLicenseKey());
        }
    }

    @Override
    @Transactional
    public SoftwareLicenseResponse create(SoftwareLicenseRequest request) {
        authorizationService.checkPermission(PermissionCode.SOFTWARE_LICENSE_CREATE);
        Long companyId = requireCompanyId();
        validateByType(request);
        requireKeyAvailable(companyId, request.getLicenseKey().trim(), null);

        SoftwareLicense license = SoftwareLicenseMapper.toEntity(request);
        license.setCompanyId(companyId);
        license.setLicenseStatus(SoftwareLicense.statusForExpiry(license.getLicenseExpiryDate(), LocalDate.now()));
        license.applySeatCounts(0);

        license = saveChecked(license);
        return SoftwareLicenseMapper.toResponse(license, 0, canSeeSecrets());
    }

    @Override
    @Transactional(readOnly = true)
    public SoftwareLicenseResponse getById(Long id) {
        authorizationService.checkPermission(PermissionCode.SOFTWARE_LICENSE_VIEW);
        return toResponse(findInTenant(id));
    }

    @Override
    @Transactional(readOnly = true)
    public SoftwareLicenseResponse getByLicenseKey(String key) {
        // Looking a licence up BY its key is only meaningful to someone allowed to see keys.
        authorizationService.checkPermission(PermissionCode.SOFTWARE_LICENSE_UPDATE);
        Long companyId = requireCompanyId();
        SoftwareLicense license = licenseRepository.findByCompanyIdAndLicenseKey(companyId, key)
                .orElseThrow(() -> new ResourceNotFoundException("License not found"));
        return toResponse(license);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SoftwareLicenseResponse> getAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.SOFTWARE_LICENSE_VIEW);
        return toResponses(licenseRepository.findByCompanyId(requireCompanyId(), pageable));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SoftwareLicenseResponse> getByStatus(LicenseStatus status, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.SOFTWARE_LICENSE_VIEW);
        return toResponses(licenseRepository.findByCompanyIdAndLicenseStatus(requireCompanyId(), status, pageable));
    }

    @Override
    @Transactional(readOnly = true)
    public List<SoftwareLicenseResponse> getExpiringLicenses() {
        authorizationService.checkPermission(PermissionCode.SOFTWARE_LICENSE_VIEW);
        LocalDate today = LocalDate.now();
        return toResponses(licenseRepository.findExpiringBetweenDates(
                requireCompanyId(), today, today.plusDays(SoftwareLicense.EXPIRING_SOON_WINDOW_DAYS)));
    }

    @Override
    @Transactional(readOnly = true)
    public List<SoftwareLicenseResponse> getExpiredLicenses() {
        authorizationService.checkPermission(PermissionCode.SOFTWARE_LICENSE_VIEW);
        return toResponses(licenseRepository.findExpiredLicenses(requireCompanyId(), LocalDate.now()));
    }

    @Override
    @Transactional
    public SoftwareLicenseResponse update(Long id, SoftwareLicenseRequest request) {
        authorizationService.checkPermission(PermissionCode.SOFTWARE_LICENSE_UPDATE);
        Long companyId = requireCompanyId();
        validateByType(request);
        // Same row lock as assign/release: the capacity check must not race a concurrent seat assignment, and a fresh read avoids overwriting a status the scheduler just wrote.
        SoftwareLicense license = lockInTenant(id, companyId);

        long activeSeats = seatRepository.countByLicenseIdAndReleasedAtIsNull(id);
        if (request.getTotalSeatsLicensed() < activeSeats) {
            throw new BadRequestException(
                    "Cannot reduce total seats below the " + activeSeats + " currently assigned");
        }

        String newKey = request.getLicenseKey().trim();
        if (!newKey.equals(license.getLicenseKey())) {
            requireKeyAvailable(companyId, newKey, id);
            license.setLicenseKey(newKey);
        }

        boolean expiryChanged = !Objects.equals(license.getLicenseExpiryDate(), request.getLicenseExpiryDate());

        license.setSoftwareName(request.getSoftwareName());
        license.setPublisher(request.getPublisher());
        license.setVersion(request.getVersion());
        license.setLicenseType(request.getLicenseType());
        license.setTotalSeatsLicensed(request.getTotalSeatsLicensed());
        license.applySeatCounts(activeSeats);
        license.setLicensePurchaseDate(request.getLicensePurchaseDate());
        license.setLicenseCost(request.getLicenseCost());
        license.setLicenseExpiryDate(request.getLicenseExpiryDate());
        license.setRenewalType(request.getRenewalType());
        license.setNextRenewalDate(request.getNextRenewalDate());
        license.setRenewalCost(request.getRenewalCost());
        license.setVendor(request.getVendor());
        license.setAccountEmail(request.getAccountEmail());
        license.setLicenseUrl(request.getLicenseUrl());
        license.setInstallationLocation(request.getInstallationLocation());
        license.setEstimatedUserCount(request.getEstimatedUserCount());
        license.setComplianceNotes(request.getComplianceNotes());
        license.setAutoRenew(request.isAutoRenewOrDefault());
        license.setNotes(request.getNotes());
        license.setRenewalNotes(request.getRenewalNotes());

        // A new expiry date moves the status with it (a renewed expired licence is ACTIVE again); SUSPENDED/REVOKED stay put.
        if (expiryChanged) {
            license.recomputeStatusFromExpiry();
        }

        license = saveChecked(license);
        return SoftwareLicenseMapper.toResponse(license, activeSeats, canSeeSecrets());
    }

    @Override
    @Transactional
    public void assignSeat(Long licenseId, Long employeeId) {
        authorizationService.checkPermission(PermissionCode.SOFTWARE_LICENSE_ASSIGN);
        Long companyId = requireCompanyId();
        SoftwareLicense license = lockInTenant(licenseId, companyId);

        if (NON_ASSIGNABLE.contains(license.getLicenseStatus()) || license.isExpired()) {
            LicenseStatus shown = license.isExpired() ? LicenseStatus.EXPIRED : license.getLicenseStatus();
            throw new BadRequestException("Cannot assign a seat on a " + shown + " license");
        }

        // Locks the employee row: 404 unknown, 400 inactive/terminated, 400 being offboarded.
        employeeGuard.requireAssignable(employeeId, companyId);
        Employee employee = employeeRepository.findByIdAndCompanyId(employeeId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Employee not found"));

        if (seatRepository.findByLicenseIdAndEmployeeIdAndReleasedAtIsNull(licenseId, employeeId).isPresent()) {
            throw new BadRequestException(employeeGuard.fullName(employeeId, companyId) + " already has a seat on this license");
        }

        long activeSeats = seatRepository.countByLicenseIdAndReleasedAtIsNull(licenseId);
        if (activeSeats >= license.getTotalSeatsLicensed()) {
            throw new BadRequestException("No seats available");
        }

        seatRepository.save(SoftwareLicenseSeat.builder()
                .companyId(companyId)
                .license(license)
                .employee(employee)
                .assignedAt(LocalDate.now())
                .build());
        license.applySeatCounts(activeSeats + 1);
        licenseRepository.save(license);
    }

    @Override
    @Transactional
    public void releaseSeat(Long licenseId, Long employeeId) {
        authorizationService.checkPermission(PermissionCode.SOFTWARE_LICENSE_ASSIGN);
        SoftwareLicense license = lockInTenant(licenseId, requireCompanyId());

        SoftwareLicenseSeat seat = seatRepository
                .findByLicenseIdAndEmployeeIdAndReleasedAtIsNull(licenseId, employeeId)
                .orElseThrow(() -> new BadRequestException("This employee does not currently hold a seat on this license"));

        seat.setReleasedAt(LocalDate.now());
        seatRepository.saveAndFlush(seat);

        license.applySeatCounts(seatRepository.countByLicenseIdAndReleasedAtIsNull(licenseId));
        licenseRepository.save(license);
    }

    @Override
    @Transactional(readOnly = true)
    public List<SoftwareLicenseSeatResponse> getSeatHolders(Long licenseId) {
        authorizationService.checkPermission(PermissionCode.SOFTWARE_LICENSE_VIEW);
        Long companyId = requireCompanyId();
        findInTenant(licenseId); // ownership check
        return toSeatResponses(seatRepository.findActiveByLicenseId(licenseId), companyId);
    }

    @Override
    @Transactional(readOnly = true)
    public List<SoftwareLicenseSeatResponse> getLicensesForEmployee(Long employeeId) {
        Long companyId = requireCompanyId();
        // Anyone may list their own licences; other employees' need SOFTWARE_LICENSE_VIEW.
        if (!authorizationService.hasPermission(PermissionCode.SOFTWARE_LICENSE_VIEW)) {
            var user = securityUtil.getCurrentUser();
            Long myEmployeeId = user == null ? null
                    : employeeRepository.findByUserId(user.getId()).map(Employee::getId).orElse(null);
            if (myEmployeeId == null || !myEmployeeId.equals(employeeId)) {
                throw new ForbiddenException("You can only view licenses assigned to you");
            }
        }
        return toSeatResponses(seatRepository.findActiveByEmployeeIdAndCompanyId(employeeId, companyId), companyId);
    }

    /** Names are batch-resolved including terminated (soft-deleted) employees, whose lazy proxies would otherwise throw EntityNotFoundException when the name is read. */
    private List<SoftwareLicenseSeatResponse> toSeatResponses(List<SoftwareLicenseSeat> seats, Long companyId) {
        // getEmployee().getId() reads the FK from the proxy without initialising it.
        Map<Long, String> names = employeeGuard.fullNames(
                seats.stream().map(s -> s.getEmployee().getId()).collect(Collectors.toSet()), companyId);
        return seats.stream().map(seat -> SoftwareLicenseSeatResponse.builder()
                        .id(seat.getId())
                        .licenseId(seat.getLicense().getId())
                        .softwareName(seat.getLicense().getSoftwareName())
                        .employeeId(seat.getEmployee().getId())
                        .employeeName(names.get(seat.getEmployee().getId()))
                        .assignedAt(seat.getAssignedAt())
                        .build())
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.SOFTWARE_LICENSE_DELETE);
        SoftwareLicense license = lockInTenant(id, requireCompanyId());
        long activeSeats = seatRepository.countByLicenseIdAndReleasedAtIsNull(id);
        if (activeSeats > 0) {
            throw new BadRequestException(
                    "Cannot delete license with " + activeSeats + " active seat(s). Release all seats first.");
        }
        // The table still carries UNIQUE(company_id, license_key) (ddl-auto=update never drops it), so tombstone the key to let it be registered again after a delete.
        String suffix = "#deleted-" + license.getId();
        String key = license.getLicenseKey() == null ? "" : license.getLicenseKey();
        if (key.length() + suffix.length() > LICENSE_KEY_COLUMN_LENGTH) {
            key = key.substring(0, LICENSE_KEY_COLUMN_LENGTH - suffix.length());
        }
        license.setLicenseKey(key + suffix);
        license.softDelete();
        licenseRepository.save(license);
    }

}
