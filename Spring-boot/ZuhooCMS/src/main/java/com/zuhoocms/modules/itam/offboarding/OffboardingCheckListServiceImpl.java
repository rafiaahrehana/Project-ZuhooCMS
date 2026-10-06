package com.zuhoocms.modules.itam.offboarding;

import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.hrm.asset.AssetRepository;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.itam.shared.ItamEmployeeGuard;
import com.zuhoocms.modules.itam.software.SoftwareLicenseSeatRepository;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Consumer;
import java.util.stream.Collectors;

/** Every write takes the employee row lock first (ItamEmployeeGuard.lock), the same one seat/asset assignment takes, serialising checklist creation and the "no open offboarding" / "nothing still assigned" checks. */
@Service
@RequiredArgsConstructor
public class OffboardingCheckListServiceImpl implements OffboardingChecklistService {

    /** /pending is an unpaged list - bounded so a large backlog can't produce an unbounded response. */
    private static final int PENDING_LIMIT = 500;

    private final OffboardingChecklistRepository checklistRepository;
    private final EmployeeRepository employeeRepository;
    private final AssetRepository assetRepository;
    private final SoftwareLicenseSeatRepository softwareLicenseSeatRepository;
    private final CompanyRepository companyRepository;
    private final NotificationService notificationService;
    private final ItamEmployeeGuard employeeGuard;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    @Transactional
    public OffboardingChecklistResponse create(OffboardingChecklistRequest request) {
        authorizationService.checkPermission(PermissionCode.OFFBOARDING_CREATE);
        Long companyId = requireCompanyId();
        OffboardingChecklist checklist = createLocked(request.getEmployeeId(), companyId, request.getNotes())
                .orElseThrow(() -> new BadRequestException("Offboarding checklist already exists for this employee"));
        return OffboardingChecklistMapper.toResponse(checklist,
                employeeGuard.fullName(request.getEmployeeId(), companyId));
    }

    @Override
    @Transactional
    public void createForTermination(Long employeeId, Long companyId) {
        createLocked(employeeId, companyId, null);
    }

    /** Creates under the employee row lock so concurrent creates produce exactly one (empty if one exists); terminated employees are included, since offboarding follows termination. */
    private Optional<OffboardingChecklist> createLocked(Long employeeId, Long companyId, String notes) {
        if (!employeeGuard.lock(employeeId, companyId)) {
            throw new ResourceNotFoundException("Employee not found or doesn't belong to your company");
        }
        if (checklistRepository.findFirstByEmployeeIdAndCompanyIdOrderByCreatedAtAscIdAsc(employeeId, companyId).isPresent()) {
            return Optional.empty();
        }

        OffboardingChecklist checklist = OffboardingChecklist.builder()
                .companyId(companyId)
                .employee(employeeRepository.getReferenceById(employeeId))
                .offboardingDate(LocalDate.now())
                .hardwareCollected(false)
                .licensesRevoked(false)
                .accessRevoked(false)
                .dataHandedOver(false)
                .exitInterviewCompleted(false)
                .overallNotes(notes)
                .build();

        checklist = checklistRepository.save(checklist);
        notifyCreated(employeeId, companyId);
        return Optional.of(checklist);
    }

    // Without this, asset/licence collection sat untouched until someone opened the checklist list; goes to the active reporting manager or else the company owner, after commit.
    private void notifyCreated(Long employeeId, Long companyId) {
        Long recipientId = employeeGuard.activeManagerUserId(employeeId, companyId);
        if (recipientId == null) {
            Company company = companyRepository.findById(companyId).orElse(null);
            recipientId = company != null && company.getOwner() != null ? company.getOwner().getId() : null;
        }
        if (recipientId == null) return;

        String name = employeeGuard.fullName(employeeId, companyId);
        notificationService.send(CreateNotificationRequest.of(
                NotificationType.OFFBOARDING_CREATED,
                "Offboarding checklist started",
                (name != null ? name : "An employee") + " has an offboarding checklist to complete",
                "/itam/offboarding",
                recipientId,
                companyId));
    }

    @Override
    @Transactional(readOnly = true)
    public OffboardingChecklistResponse getById(Long id) {
        authorizationService.checkPermission(PermissionCode.OFFBOARDING_VIEW);
        return toResponse(findInTenant(id));
    }

    @Override
    @Transactional(readOnly = true)
    public OffboardingChecklistResponse getByEmployee(Long employeeId) {
        authorizationService.checkPermission(PermissionCode.OFFBOARDING_VIEW);
        Long companyId = requireCompanyId();
        OffboardingChecklist checklist = checklistRepository
                .findFirstByEmployeeIdAndCompanyIdOrderByCreatedAtAscIdAsc(employeeId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Offboarding checklist not found"));
        return toResponse(checklist);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<OffboardingChecklistResponse> getAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.OFFBOARDING_VIEW);
        Long companyId = requireCompanyId();
        Page<OffboardingChecklist> page = checklistRepository.findByCompanyId(companyId, pageable);
        Map<Long, String> names = namesFor(page.getContent(), companyId);
        return page.map(c -> OffboardingChecklistMapper.toResponse(c, names.get(c.getEmployee().getId())));
    }

    @Override
    @Transactional(readOnly = true)
    public List<OffboardingChecklistResponse> getPendingChecklists() {
        authorizationService.checkPermission(PermissionCode.OFFBOARDING_VIEW);
        Long companyId = requireCompanyId();
        List<OffboardingChecklist> pending = checklistRepository.findByCompanyIdAndCompletedFalse(
                companyId, PageRequest.of(0, PENDING_LIMIT, Sort.by("createdAt").descending().and(Sort.by("id").descending())));
        Map<Long, String> names = namesFor(pending, companyId);
        return pending.stream()
                .map(c -> OffboardingChecklistMapper.toResponse(c, names.get(c.getEmployee().getId())))
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public void markHardwareCollected(Long id, String notes) {
        authorizationService.checkPermission(PermissionCode.OFFBOARDING_MANAGE);
        updateStep(id, checklist -> {
            requireNoAssets(checklist, "Cannot mark hardware collected");
            checklist.setHardwareCollected(true);
            checklist.setHardwareCollectedDate(LocalDate.now());
            checklist.setHardwareCollectedBy(currentUserName());
            if (notes != null && !notes.isBlank()) checklist.setHardwareNotes(notes);
        });
    }

    @Override
    @Transactional
    public void markLicensesRevoked(Long id, String notes) {
        authorizationService.checkPermission(PermissionCode.OFFBOARDING_MANAGE);
        updateStep(id, checklist -> {
            requireNoSeats(checklist, "Cannot mark licenses revoked");
            checklist.setLicensesRevoked(true);
            checklist.setLicensesRevokedDate(LocalDate.now());
            if (notes != null && !notes.isBlank()) checklist.setLicensesNotes(notes);
        });
    }

    @Override
    @Transactional
    public void markAccessRevoked(Long id, String notes) {
        authorizationService.checkPermission(PermissionCode.OFFBOARDING_MANAGE);
        updateStep(id, checklist -> {
            checklist.setAccessRevoked(true);
            checklist.setAccessRevokedDate(LocalDate.now());
            if (notes != null && !notes.isBlank()) checklist.setAccessNotes(notes);
        });
    }

    @Override
    @Transactional
    public void markDataHandedOver(Long id, String notes) {
        authorizationService.checkPermission(PermissionCode.OFFBOARDING_MANAGE);
        updateStep(id, checklist -> {
            checklist.setDataHandedOver(true);
            checklist.setDataHandoverDate(LocalDate.now());
            if (notes != null && !notes.isBlank()) checklist.setDataHandoverNotes(notes);
        });
    }

    @Override
    @Transactional
    public void markExitInterviewCompleted(Long id, String notes) {
        authorizationService.checkPermission(PermissionCode.OFFBOARDING_MANAGE);
        updateStep(id, checklist -> {
            checklist.setExitInterviewCompleted(true);
            checklist.setExitInterviewDate(LocalDate.now());
            if (notes != null && !notes.isBlank()) checklist.setExitInterviewNotes(notes);
        });
    }

    @Override
    @Transactional
    public OffboardingChecklistResponse delete(Long id) {
        authorizationService.checkPermission(PermissionCode.OFFBOARDING_DELETE);
        OffboardingChecklist checklist = lockForUpdate(id);
        checklist.softDelete();
        checklistRepository.save(checklist);
        return toResponse(checklist);
    }

    /** Employee lock, then a fresh locked read of the checklist, then the step, then the completion check. */
    private void updateStep(Long id, Consumer<OffboardingChecklist> step) {
        OffboardingChecklist checklist = lockForUpdate(id);
        step.accept(checklist);
        checkCompletionStatus(checklist);
        checklistRepository.save(checklist);
    }

    private OffboardingChecklist lockForUpdate(Long id) {
        Long companyId = requireCompanyId();
        Long employeeId = checklistRepository.findEmployeeIdByIdAndCompanyId(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Checklist not found"));
        employeeGuard.lock(employeeId, companyId);
        return checklistRepository.findByIdAndCompanyIdForUpdate(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Checklist not found"));
    }

    private void requireNoAssets(OffboardingChecklist checklist, String action) {
        long stillAssigned = assetRepository
                .findByCompanyIdAndAssignedToId(checklist.getCompanyId(), checklist.getEmployee().getId())
                .size();
        if (stillAssigned > 0) {
            throw new BadRequestException(action + " - " + stillAssigned
                    + " asset(s) are still assigned to this employee. Unassign them first.");
        }
    }

    private void requireNoSeats(OffboardingChecklist checklist, String action) {
        long stillHeld = softwareLicenseSeatRepository.countByEmployeeIdAndCompanyIdAndReleasedAtIsNull(
                checklist.getEmployee().getId(), checklist.getCompanyId());
        if (stillHeld > 0) {
            throw new BadRequestException(action + " - " + stillHeld
                    + " license seat(s) are still held by this employee. Release them first.");
        }
    }

    /** Re-verifies under the employee lock that nothing is still assigned: the hardware/licence steps may have been ticked long before, and completing lifts the "being offboarded" block. */
    private void checkCompletionStatus(OffboardingChecklist checklist) {
        if (checklist.isAllTasksCompleted() && !checklist.isCompleted()) {
            requireNoAssets(checklist, "Cannot complete offboarding");
            requireNoSeats(checklist, "Cannot complete offboarding");
            checklist.setCompleted(true);
            checklist.setCompletionDate(LocalDate.now());
            checklist.setCompletedBy(currentUserName());
        }
    }

    private OffboardingChecklistResponse toResponse(OffboardingChecklist checklist) {
        return OffboardingChecklistMapper.toResponse(checklist,
                employeeGuard.fullName(checklist.getEmployee().getId(), checklist.getCompanyId()));
    }

    private Map<Long, String> namesFor(List<OffboardingChecklist> checklists, Long companyId) {
        return employeeGuard.fullNames(
                checklists.stream().map(c -> c.getEmployee().getId()).collect(Collectors.toSet()), companyId);
    }

    private String currentUserName() {
        var user = securityUtil.getCurrentUser();
        return user != null ? user.getFullName() : null;
    }

    private OffboardingChecklist findInTenant(Long id) {
        return checklistRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Checklist not found"));
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) {
            throw new BadRequestException("No company context found in security token");
        }
        return id;
    }
}
