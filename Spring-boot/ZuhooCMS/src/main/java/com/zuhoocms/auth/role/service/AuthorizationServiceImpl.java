package com.zuhoocms.auth.role.service;

import com.zuhoocms.auth.role.entity.CustomRole;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.role.repository.RolePermissionRepository;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.ForbiddenException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Arrays;
import java.util.List;

@Service
@RequiredArgsConstructor
public class AuthorizationServiceImpl implements AuthorizationService {

    private final SecurityUtil securityUtil;
    private final RolePermissionRepository rolePermissionRepository;

    @Override
    public void checkPermission(PermissionCode permission) {

        if (!hasPermission(permission)) {
            throw new ForbiddenException("You do not have permission: " + permission);
        }
    }

    @Override
    public void checkAnyPermission(PermissionCode... permissions) {
        for (PermissionCode permission : permissions) {
            if (hasPermission(permission)) {
                return;
            }
        }
        throw new ForbiddenException("You do not have any of the required permissions: " + Arrays.toString(permissions));
    }

    @Override
    public boolean hasPermission(PermissionCode permission) {

        User user = securityUtil.getCurrentUser();

        // Impersonation must act as owner here too, or tenant modules using checkPermission() instead of @PreAuthorize (Leave/Payroll/AI) get gated by the real admin's own role.
        if (securityUtil.isImpersonating()) {
            return true;
        }

        // Platform Admins can only access Platform Level permissions (Privacy)
        if (user.getRole() == Role.SUPER_ADMIN || user.getRole() == Role.SYSTEM_ADMIN) {
            return isPlatformPermission(permission);
        }

        if (user.getRole() == Role.COMPANY_OWNER) {
            return true;
        }

        CustomRole role = user.getCustomRole();
        if (role == null) {
            return false;
        }

        return rolePermissionRepository.existsByCustomRoleIdAndPermission_Code(
                role.getId(), permission.name());
    }

    private boolean isPlatformPermission(PermissionCode permission) {
        return switch (permission) {
            case COMPANY_VIEW, COMPANY_UPDATE,
                    USER_VIEW, USER_CREATE, USER_UPDATE, USER_DELETE,
                    AI_ADMIN,
                    TICKET_VIEW, SUPPORT_MESSAGE_VIEW, SUPPORT_CATEGORY_VIEW,
                    SLA_POLICY_VIEW, AUDIT_LOG_VIEW ->
                true;
            default -> false;
        };
    }

    @Override
    @Transactional(readOnly = true)
    public List<String> getMyPermissionCodes() {
        User user = securityUtil.getCurrentUser();
        if (user == null) {
            return List.of();
        }

        // Enumerates every code rather than a wildcard so the frontend's hasPermission(code) stays a plain list-membership test with no owner special-casing.
        if (securityUtil.isImpersonating() || user.getRole() == Role.COMPANY_OWNER) {
            return Arrays.stream(PermissionCode.values()).map(Enum::name).toList();
        }

        if (user.getRole() == Role.SUPER_ADMIN || user.getRole() == Role.SYSTEM_ADMIN) {
            return Arrays.stream(PermissionCode.values())
                    .filter(this::isPlatformPermission)
                    .map(Enum::name)
                    .toList();
        }

        CustomRole role = user.getCustomRole();
        if (role == null) {
            return List.of();
        }

        return rolePermissionRepository.findByCustomRoleId(role.getId()).stream()
                .map(rp -> rp.getPermission().getCode())
                .toList();
    }
}