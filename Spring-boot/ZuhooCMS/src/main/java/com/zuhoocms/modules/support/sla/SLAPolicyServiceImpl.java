package com.zuhoocms.modules.support.sla;

import com.zuhoocms.modules.support.ticket.TicketPriority;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class SLAPolicyServiceImpl implements SLAPolicyService {

    private final SLAPolicyRepository slaPolicyRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    @Transactional
    public SLAPolicyResponse create(SLAPolicyRequest request) {
        if (slaPolicyRepository.existsByApplicablePriority(request.getApplicablePriority())) {
            throw new BadRequestException("SLA policy already exists for priority: " + request.getApplicablePriority());
        }
        validateHours(request.getFirstResponseTimeHours(), request.getResolutionTimeHours());

        SLAPolicy policy = SLAPolicyMapper.toEntity(request);
        policy = slaPolicyRepository.save(policy);
        return SLAPolicyMapper.toResponse(policy);
    }

    @Override
    @Transactional(readOnly = true)
    public SLAPolicyResponse getById(Long id) {
        SLAPolicy policy = slaPolicyRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("SLA policy not found"));
        return SLAPolicyMapper.toResponse(policy);
    }

    /** Prefers the active policy for the priority; tolerates legacy duplicates (newest wins). */
    @Override
    @Transactional(readOnly = true)
    public SLAPolicyResponse getByPriority(TicketPriority priority) {
        SLAPolicy policy = slaPolicyRepository.findFirstByApplicablePriorityAndActiveTrueOrderByIdDesc(priority)
                .or(() -> slaPolicyRepository.findFirstByApplicablePriorityOrderByIdDesc(priority))
                .orElseThrow(() -> new ResourceNotFoundException("SLA policy not found for priority: " + priority));
        return SLAPolicyMapper.toResponse(policy);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SLAPolicyResponse> getAll(Pageable pageable) {
        checkTenantPermission();
        return slaPolicyRepository.findAll(pageable)
                .map(SLAPolicyMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<SLAPolicyResponse> getActive() {
        checkTenantPermission();
        return slaPolicyRepository.findByActiveTrue()
                .stream()
                .map(SLAPolicyMapper::toResponse)
                .collect(Collectors.toList());
    }

    /** {@code active}/{@code notes} left out of the body keep their current values; the result may never be a second ACTIVE policy for one priority. */
    @Override
    @Transactional
    public SLAPolicyResponse update(Long id, SLAPolicyRequest request) {
        SLAPolicy policy = slaPolicyRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("SLA policy not found"));
        validateHours(request.getFirstResponseTimeHours(), request.getResolutionTimeHours());

        boolean active = request.getActive() != null ? request.getActive() : policy.isActive();
        if (active && slaPolicyRepository.existsByApplicablePriorityAndActiveTrueAndIdNot(request.getApplicablePriority(), id)) {
            throw new BadRequestException("Another active SLA policy already exists for priority: "
                    + request.getApplicablePriority() + " - deactivate it first");
        }

        policy.setPolicyName(request.getPolicyName());
        policy.setApplicablePriority(request.getApplicablePriority());
        policy.setFirstResponseTimeHours(request.getFirstResponseTimeHours());
        policy.setResolutionTimeHours(request.getResolutionTimeHours());
        policy.setBusinessHoursOnly(request.isBusinessHoursOnly());
        policy.setDescription(request.getDescription());
        policy.setActive(active);
        if (request.getNotes() != null) {
            policy.setNotes(request.getNotes());
        }

        policy = slaPolicyRepository.save(policy);
        return SLAPolicyMapper.toResponse(policy);
    }

    @Override
    @Transactional
    public void updateStatus(Long id, boolean active) {
        SLAPolicy policy = slaPolicyRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("SLA policy not found"));
        if (active && !policy.isActive()
                && slaPolicyRepository.existsByApplicablePriorityAndActiveTrueAndIdNot(policy.getApplicablePriority(), id)) {
            throw new BadRequestException("Another active SLA policy already exists for priority: "
                    + policy.getApplicablePriority() + " - deactivate it first");
        }
        policy.setActive(active);
        slaPolicyRepository.save(policy);
    }

    @Override
    @Transactional
    public SLAPolicyResponse delete(Long id) {
        SLAPolicy policy = slaPolicyRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("SLA policy not found"));
        policy.softDelete();
        slaPolicyRepository.save(policy);
        return SLAPolicyMapper.toResponse(policy);
    }

    private static void validateHours(int firstResponseHours, int resolutionHours) {
        if (firstResponseHours < 0 || resolutionHours < 0) {
            throw new BadRequestException("SLA hours cannot be negative");
        }
    }

    // SLA policies are a platform-wide catalog: platform staff have no CustomRole and are gated by @PreAuthorize, so only the tenant caller is checked here.
    private void checkTenantPermission() {
        User current = securityUtil.getCurrentUser();
        if (current != null && !current.isPlatformUser()) {
            authorizationService.checkPermission(PermissionCode.SLA_POLICY_VIEW);
        }
    }
}
