package com.zuhoocms.auth.platformuser;

import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.token.TokenRepository;
import com.zuhoocms.auth.token.TokenType;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserMapper;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.auth.user.UserResponse;
import com.zuhoocms.enums.AuditAction;
import com.zuhoocms.enums.AuditEntityType;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.audit.AuditService;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
public class PlatformUserService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final AuditService auditService;
    private final SecurityUtil securityUtil;
    private final TokenRepository tokenRepository;

    // Same roles as User.isPlatformUser(), duplicated because this is the only place needing them as a queryable list rather than a boolean.
    private static final List<Role> PLATFORM_ROLES = List.of(
        Role.SUPER_ADMIN, Role.SYSTEM_ADMIN, Role.SUPPORT_AGENT,
        Role.SUPPORT_MANAGER, Role.MARKETING_MANAGER,
        Role.PLATFORM_ACCOUNTANT, Role.SALES_MANAGER
    );

    public UserResponse createPlatformUser(PlatformUserRequest request) {
        if (userRepository.existsByEmail(request.getEmail())) {
            throw new BadRequestException("Email already exists");
        }

        if (!PLATFORM_ROLES.contains(request.getRole())) {
            throw new BadRequestException("Invalid platform role selected");
        }

        requireNotSystemAdminGrantingSuperAdmin(request.getRole());

        User user = new User();
        user.setFirstName(request.getFirstName());
        user.setLastName(request.getLastName());
        user.setEmail(request.getEmail().toLowerCase().trim());
        user.setPassword(passwordEncoder.encode(request.getPassword()));
        user.setRole(request.getRole());
        user.setPhone(request.getPhone());
        user.setActive(true);
        user.setEmailVerified(true);

        user = userRepository.save(user);
        return UserMapper.toResponse(user);
    }

    public Page<UserResponse> list(Pageable pageable) {
        return userRepository.findByRoleIn(PLATFORM_ROLES, pageable).map(UserMapper::toResponse);
    }

    public UserResponse getById(Long id) {
        return UserMapper.toResponse(getPlatformUserOrThrow(id));
    }

    public UserResponse update(Long id, PlatformUserRequest request) {
        User user = getPlatformUserOrThrow(id);

        if (request.getFirstName() == null || request.getFirstName().isBlank()) {
            throw new BadRequestException("First name is required");
        }
        if (request.getLastName() == null || request.getLastName().isBlank()) {
            throw new BadRequestException("Last name is required");
        }
        if (request.getEmail() == null || request.getEmail().isBlank()) {
            throw new BadRequestException("Email is required");
        }
        if (request.getRole() == null || !PLATFORM_ROLES.contains(request.getRole())) {
            throw new BadRequestException("Invalid platform role selected");
        }
        if (!user.getEmail().equalsIgnoreCase(request.getEmail()) && userRepository.existsByEmail(request.getEmail())) {
            throw new BadRequestException("Email already exists");
        }

        Role oldRole = user.getRole();

        // Only checked when the role actually changes, so editing an existing SUPER_ADMIN's other fields isn't blocked as if it were a fresh grant.
        if (oldRole != request.getRole()) {
            requireNotSystemAdminGrantingSuperAdmin(request.getRole());
        }
        boolean passwordReset = request.getPassword() != null && !request.getPassword().isBlank();

        user.setFirstName(request.getFirstName());
        user.setLastName(request.getLastName());
        user.setEmail(request.getEmail().toLowerCase().trim());
        user.setRole(request.getRole());
        user.setPhone(request.getPhone());
        if (passwordReset) {
            user.setPassword(passwordEncoder.encode(request.getPassword()));
        }

        User saved = userRepository.save(user);

        // Promoting an account and setting someone else's password are the two most sensitive admin actions here, so both must leave an audit trace.
        User actor = securityUtil.getCurrentUser();
        if (oldRole != request.getRole()) {
            auditService.log(AuditEntityType.USER, saved.getId(), AuditAction.PERMISSION_CHANGE,
                    oldRole != null ? oldRole.name() : null, request.getRole().name(), actor, null, null);
        }
        if (passwordReset) {
            auditService.log(AuditEntityType.USER, saved.getId(), AuditAction.PASSWORD_CHANGE,
                    null, null, actor, null, null);
        }

        return UserMapper.toResponse(saved);
    }

    public void deactivate(Long id) {
        User user = getPlatformUserOrThrow(id);
        user.setActive(false);
        userRepository.save(user);
        // isEnabled() blocks future authentication, but a live refresh token would still mint access tokens until presented, so revoke it eagerly.
        tokenRepository.revokeAllByUserIdAndType(user.getId(), TokenType.REFRESH);
        auditService.log(AuditEntityType.USER, user.getId(), AuditAction.UPDATE,
                "active", "inactive", securityUtil.getCurrentUser(), null, null);
    }

    // The controller only requires hasAnyRole('SUPER_ADMIN','SYSTEM_ADMIN'), so without this a SYSTEM_ADMIN could grant itself SUPER_ADMIN - privilege escalation.
    private void requireNotSystemAdminGrantingSuperAdmin(Role targetRole) {
        if (targetRole != Role.SUPER_ADMIN) {
            return;
        }
        User actor = securityUtil.getCurrentUser();
        if (actor == null || actor.getRole() != Role.SUPER_ADMIN) {
            throw new ForbiddenException("Only a SUPER_ADMIN may grant the SUPER_ADMIN role");
        }
    }

    private User getPlatformUserOrThrow(Long id) {
        User user = userRepository.findByIdAndDeletedFalse(id)
            .orElseThrow(() -> new ResourceNotFoundException("Platform user not found"));
        if (!user.isPlatformUser()) {
            throw new ResourceNotFoundException("Platform user not found");
        }
        return user;
    }
}
