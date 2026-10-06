package com.zuhoocms.auth.impersonation;

import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.enums.AuditAction;
import com.zuhoocms.enums.AuditEntityType;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.security.JwtService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.audit.AuditService;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Transactional
public class ImpersonationServiceImpl implements ImpersonationService {

    private final CompanyRepository companyRepository;
    private final ImpersonationAuditLogRepository impersonationAuditLogRepository;
    private final JwtService jwtService;
    private final SecurityUtil securityUtil;
    private final AuditService auditService;

    @Override
    public ImpersonationResponse startImpersonation(Long companyId, ImpersonateRequest request) {
        User admin = securityUtil.getCurrentUser();

        Company company = companyRepository.findById(companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Company not found"));

        String sessionId = UUID.randomUUID().toString();

        String accessToken = jwtService.generateImpersonationToken(
            admin.getEmail(), Role.COMPANY_OWNER.name(), companyId, admin.getId(), sessionId);

        impersonationAuditLogRepository.save(ImpersonationAuditLog.builder()
            .admin(admin)
            .company(company)
            .reason(request.getReason())
            .impersonationSessionId(sessionId)
            .startedAt(LocalDateTime.now())
            .build());

        // Also logged to the main audit table because the Support Audit Logs page never reads ImpersonationAuditLog; mirrors SupportContextSwitchServiceImpl.switchContext().
        auditService.log(AuditEntityType.COMPANY, company.getId(), AuditAction.ASSIGN,
                null, "Impersonation started by " + admin.getEmail()
                        + (request.getReason() != null ? " - " + request.getReason() : ""),
                admin, companyId, null);

        return new ImpersonationResponse(
            accessToken,
            companyId,
            company.getCompanyName(),
            sessionId,
            jwtService.getImpersonationExpirationMs() / 1000);
    }

    /** Only the starting admin or a SUPER_ADMIN may end a session, and a caller using an impersonation token may end only its own; setting endedAt revokes the token immediately, since JwtAuthFilter rejects ended sessions. */
    @Override
    public void endImpersonation(EndImpersonationRequest request) {
        User caller = securityUtil.getCurrentUser();
        if (caller == null) {
            throw new ForbiddenException("Not authenticated");
        }

        ImpersonationAuditLog log = impersonationAuditLogRepository
            .findByImpersonationSessionId(request.getImpersonationSessionId())
            .orElseThrow(() -> new ResourceNotFoundException("Impersonation session not found"));

        boolean owner = log.getAdmin() != null && log.getAdmin().getId().equals(caller.getId());
        if (caller.isImpersonationPrincipal()) {
            if (!request.getImpersonationSessionId().equals(caller.getImpersonationSessionId())) {
                throw new ForbiddenException("You can only end your own impersonation session");
            }
        } else if (!owner && caller.getRealRole() != Role.SUPER_ADMIN) {
            throw new ForbiddenException("Only the admin who started this impersonation session, or a SUPER_ADMIN, can end it");
        }

        if (log.getEndedAt() == null) {
            log.setEndedAt(LocalDateTime.now());
            impersonationAuditLogRepository.save(log);
        }
    }
}
