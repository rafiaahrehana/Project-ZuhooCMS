package com.zuhoocms.modules.support.audit;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.enums.AuditAction;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.audit.AuditLog;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.EnumSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

/** Tenants see their own company's audit trail; platform reviewers see every company, because their tokens carry no company and a "company = mine" query becomes "company_id IS NULL". */
@Service
@RequiredArgsConstructor
public class SupportAuditServiceImpl implements SupportAuditService {

    private static final Set<Role> PLATFORM_AUDIT_ROLES =
            EnumSet.of(Role.SUPPORT_MANAGER, Role.SUPER_ADMIN, Role.SYSTEM_ADMIN);

    private final SupportAuditLogRepository auditRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    @Transactional(readOnly = true)
    public SupportAuditLogResponse getById(Long id) {
        boolean platform = checkAccess();
        AuditLog log = auditRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Audit log not found"));
        if (!platform && (log.getCompany() == null
                || !Objects.equals(log.getCompany().getId(), securityUtil.getCurrentCompanyId()))) {
            throw new ResourceNotFoundException("Audit log not found");
        }
        return SupportAuditLogMapper.toResponse(log);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SupportAuditLogResponse> getAll(Pageable pageable) {
        Page<AuditLog> page = checkAccess()
                ? auditRepository.findAll(pageable)
                : auditRepository.findByCompanyId(securityUtil.getCurrentCompanyId(), pageable);
        return page.map(SupportAuditLogMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SupportAuditLogResponse> getByActionType(String actionType, Pageable pageable) {
        boolean platform = checkAccess();
        AuditAction action;
        try {
            action = AuditAction.valueOf(actionType);
        } catch (IllegalArgumentException e) {
            throw new BadRequestException("Invalid action type");
        }
        Page<AuditLog> page = platform
                ? auditRepository.findByAction(action, pageable)
                : auditRepository.findByCompanyIdAndAction(securityUtil.getCurrentCompanyId(), action, pageable);
        return page.map(SupportAuditLogMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<SupportAuditLogResponse> getByResourceId(Long resourceId) {
        List<AuditLog> logs = checkAccess()
                ? auditRepository.findTop500ByEntityIdOrderByPerformedAtDesc(resourceId)
                : auditRepository.findTop500ByCompanyIdAndEntityIdOrderByPerformedAtDesc(
                        securityUtil.getCurrentCompanyId(), resourceId);
        return logs.stream()
                .map(SupportAuditLogMapper::toResponse)
                .collect(Collectors.toList());
    }

    /** Both dates inclusive: [start 00:00, end + 1 day 00:00). */
    @Override
    @Transactional(readOnly = true)
    public Page<SupportAuditLogResponse> getByDateRange(LocalDate start, LocalDate end, Pageable pageable) {
        boolean platform = checkAccess();
        if (end.isBefore(start)) {
            throw new BadRequestException("End date must not be before start date");
        }
        LocalDateTime from = start.atStartOfDay();
        LocalDateTime toExclusive = end.plusDays(1).atStartOfDay();
        Page<AuditLog> page = platform
                ? auditRepository.findByPerformedAtGreaterThanEqualAndPerformedAtLessThan(from, toExclusive, pageable)
                : auditRepository.findByCompanyIdAndPerformedAtGreaterThanEqualAndPerformedAtLessThan(
                        securityUtil.getCurrentCompanyId(), from, toExclusive, pageable);
        return page.map(SupportAuditLogMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SupportAuditLogResponse> getByUser(Long userId, Pageable pageable) {
        Page<AuditLog> page = checkAccess()
                ? auditRepository.findByPerformedById(userId, pageable)
                : auditRepository.findByCompanyIdAndPerformedById(securityUtil.getCurrentCompanyId(), userId, pageable);
        return page.map(SupportAuditLogMapper::toResponse);
    }

    /** @return true for platform reviewers (all companies), false for a tenant caller, who must hold AUDIT_LOG_VIEW and is scoped to the current company. */
    private boolean checkAccess() {
        User current = securityUtil.getCurrentUser();
        if (current == null) {
            throw new ForbiddenException("Not authenticated");
        }
        if (current.isPlatformUser()) {
            if (!PLATFORM_AUDIT_ROLES.contains(current.getRole())) {
                throw new ForbiddenException("Not allowed to view support audit logs");
            }
            return true;
        }
        authorizationService.checkPermission(PermissionCode.AUDIT_LOG_VIEW);
        return false;
    }
}
