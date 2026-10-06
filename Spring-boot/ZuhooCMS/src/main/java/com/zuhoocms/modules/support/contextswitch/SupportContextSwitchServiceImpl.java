package com.zuhoocms.modules.support.contextswitch;

import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.enums.AuditAction;
import com.zuhoocms.enums.AuditEntityType;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.audit.AuditService;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.LocalDateTime;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class SupportContextSwitchServiceImpl implements SupportContextSwitchService {

    /** Roles that may see every agent's switches (others only see their own). */
    private static final Set<Role> OVERSIGHT_ROLES = EnumSet.of(Role.SUPER_ADMIN, Role.SUPPORT_MANAGER);

    private final SupportContextSwitchRepository contextSwitchRepository;
    private final CompanyRepository companyRepository;
    private final SecurityUtil securityUtil;
    private final AuditService auditService;

    @Override
    @Transactional
    public SupportContextSwitchResponse switchContext(SupportContextSwitchRequest request, String ipAddress, String userAgent) {
        // The actor and IP/user-agent are derived server-side, never from the body.
        User user = securityUtil.getCurrentUser();
        if (user == null) {
            throw new ResourceNotFoundException("Current user not found");
        }

        Company company = companyRepository.findById(request.getViewedCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Company not found"));

        // One active switch per user: serialise on the user's row, then end every active switch (plural, tolerating legacy duplicates).
        contextSwitchRepository.lockUser(user.getId());
        LocalDateTime now = LocalDateTime.now();
        for (SupportContextSwitch active : contextSwitchRepository
                .findBySupportAgentIdAndStillActiveTrueOrderBySwitchedInTimeDesc(user.getId())) {
            active.setSwitchedOutTime(now);
            active.setStillActive(false);
            contextSwitchRepository.save(active);
        }

        SupportContextSwitch contextSwitch = SupportContextSwitch.builder()
                .supportAgent(user)
                .viewedCompany(company)
                .switchedInTime(now)
                .purpose(request.getPurpose().trim())
                .ipAddress(ipAddress)
                .userAgent(userAgent)
                .stillActive(true)
                .build();

        contextSwitch = contextSwitchRepository.save(contextSwitch);

        // Mirrored into the shared audit log the Support Audit Logs page reads.
        auditService.log(AuditEntityType.COMPANY, company.getId(), AuditAction.ASSIGN,
                null, "Support context switch by " + user.getEmail() + " - " + contextSwitch.getPurpose(),
                user, company.getId(), ipAddress);

        return SupportContextSwitchMapper.toResponse(contextSwitch);
    }

    /** Only the agent who started the switch, or a SUPER_ADMIN, can end it. */
    @Override
    @Transactional
    public void endContextSwitch(Long contextSwitchId) {
        User current = securityUtil.getCurrentUser();
        SupportContextSwitch contextSwitch = contextSwitchRepository.lockById(contextSwitchId)
                .orElseThrow(() -> new ResourceNotFoundException("Context switch not found"));

        boolean owner = current != null && contextSwitch.getSupportAgent() != null
                && contextSwitch.getSupportAgent().getId().equals(current.getId());
        boolean superAdmin = current != null && current.isPlatformUser() && current.getRole() == Role.SUPER_ADMIN;
        if (!owner && !superAdmin) {
            throw new ForbiddenException("Only the agent who started this context switch, or a SUPER_ADMIN, can end it");
        }

        if (contextSwitch.isStillActive()) {
            contextSwitch.setSwitchedOutTime(LocalDateTime.now());
            contextSwitch.setStillActive(false);
            contextSwitchRepository.save(contextSwitch);
        }
    }

    /** Ends one stale switch in its own transaction (per id from SupportContextSwitchExpiryScheduler), re-checking under the row lock so one ended meanwhile is left alone. */
    @Override
    @Transactional
    public boolean expireIfStale(Long contextSwitchId, LocalDateTime cutoff) {
        SupportContextSwitch contextSwitch = contextSwitchRepository.lockById(contextSwitchId).orElse(null);
        if (contextSwitch == null || !contextSwitch.isStillActive()
                || contextSwitch.getSwitchedInTime() == null || !contextSwitch.getSwitchedInTime().isBefore(cutoff)) {
            return false;
        }
        contextSwitch.setSwitchedOutTime(LocalDateTime.now());
        contextSwitch.setStillActive(false);
        contextSwitchRepository.save(contextSwitch);
        return true;
    }

    @Override
    @Transactional(readOnly = true)
    public List<Long> findStaleActiveIds(LocalDateTime cutoff) {
        return contextSwitchRepository.findActiveIdsSwitchedInBefore(cutoff);
    }

    /** Newest active switch for the agent; SUPPORT_AGENTs may only ask about themselves. */
    @Override
    @Transactional(readOnly = true)
    public SupportContextSwitchResponse getActiveContextSwitch(Long supportAgentId) {
        requireSelfOrOversight(supportAgentId);
        return contextSwitchRepository.findBySupportAgentIdAndStillActiveTrueOrderBySwitchedInTimeDesc(supportAgentId)
                .stream()
                .findFirst()
                .map(SupportContextSwitchMapper::toResponse)
                .orElseThrow(() -> new ResourceNotFoundException("No active context switch found"));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SupportContextSwitchResponse> getContextSwitchHistory(Long supportAgentId, Pageable pageable) {
        return contextSwitchRepository.findBySupportAgentId(supportAgentId, pageable)
                .map(SupportContextSwitchMapper::toResponse);
    }

    /** Managers/SUPER_ADMIN see every active switch; a SUPPORT_AGENT sees only their own. */
    @Override
    @Transactional(readOnly = true)
    public List<SupportContextSwitchResponse> getActiveContextSwitches() {
        User current = securityUtil.getCurrentUser();
        List<SupportContextSwitch> switches = hasOversight(current)
                ? contextSwitchRepository.findByStillActiveTrueOrderBySwitchedInTimeDesc()
                : contextSwitchRepository.findBySupportAgentIdAndStillActiveTrueOrderBySwitchedInTimeDesc(current.getId());
        return switches.stream()
                .map(SupportContextSwitchMapper::toResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public SupportContextSwitchResponse getById(Long id) {
        SupportContextSwitch contextSwitch = contextSwitchRepository.findWithDetailsById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Context switch not found"));
        return SupportContextSwitchMapper.toResponse(contextSwitch);
    }

    private static boolean hasOversight(User user) {
        return user != null && user.isPlatformUser() && OVERSIGHT_ROLES.contains(user.getRole());
    }

    private void requireSelfOrOversight(Long supportAgentId) {
        User current = securityUtil.getCurrentUser();
        if (current == null) {
            throw new ForbiddenException("Not authenticated");
        }
        if (!hasOversight(current) && !current.getId().equals(supportAgentId)) {
            throw new ForbiddenException("You can only view your own context switches");
        }
    }
}
