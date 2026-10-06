package com.zuhoocms.auth.user;

import com.zuhoocms.auth.role.entity.CustomRole;
import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.shared.address.Address;
import jakarta.persistence.*;
import lombok.*;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;

import java.util.Collection;
import java.util.List;
import com.fasterxml.jackson.annotation.JsonIgnore;

@Entity
@Table(name = "users")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class User extends BaseEntity implements UserDetails {

    @Column(nullable = false)
    private String firstName;

    @Column(nullable = false)
    private String lastName;

    @Column(nullable = false, unique = true)
    private String email;

    private String phone;

    @JsonIgnore
    @Column(nullable = false)
    private String password;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private Role role;

    @OneToOne(cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @JoinColumn(name = "address_id")
    private Address location;

    /** Set by JwtAuthFilter on the request principal only, never persisted; JPA uses field access, so the getRole() override below cannot alter the {@code role} column even if this instance is saved. */
    @Transient
    @JsonIgnore
    private Role impersonatedRole;

    @Transient
    @JsonIgnore
    private String impersonationSessionId;

    /** Effective role for this request, so every isPlatformUser()/getRole() branch treats an impersonating admin as a tenant. */
    public Role getRole() {
        return impersonatedRole != null ? impersonatedRole : role;
    }

    /** The role actually stored for this account, ignoring any impersonation. */
    @JsonIgnore
    public Role getRealRole() {
        return role;
    }

    @JsonIgnore
    public boolean isImpersonationPrincipal() {
        return impersonatedRole != null;
    }

    public boolean isPlatformUser() {
        return isPlatformRole(getRole());
    }

    /** Platform-ness of the stored role - true for an impersonating platform admin too. */
    @JsonIgnore
    public boolean isRealPlatformUser() {
        return isPlatformRole(role);
    }

    private static boolean isPlatformRole(Role r) {
        return r == Role.SUPER_ADMIN || r == Role.SYSTEM_ADMIN ||
               r == Role.SUPPORT_AGENT || r == Role.SUPPORT_MANAGER ||
               r == Role.MARKETING_MANAGER || r == Role.PLATFORM_ACCOUNTANT ||
               r == Role.SALES_MANAGER;
    }

    public boolean isTenantUser() {
        return !isPlatformUser();
    }

    @Builder.Default
    private boolean active = true;

    private String image;

    @Builder.Default
    private boolean emailVerified = false;

    /** 6-digit code shown in the "Verify your email" message; cleared once used. */
    @Column(length = 6)
    private String emailVerificationCode;

    private java.time.LocalDateTime emailVerificationCodeExpiresAt;

    // Throttles the otherwise brute-forceable 6-digit code: AuthServiceImpl.verifyEmail() invalidates the code at the threshold, forcing a fresh resendVerification().
    @Builder.Default
    private int emailVerificationAttempts = 0;

    /** 6-digit code shown in the "Reset your password" email; cleared once used. */
    @Column(length = 6)
    private String passwordResetCode;

    private java.time.LocalDateTime passwordResetCodeExpiresAt;

    // Same throttle for the password-reset code: AuthServiceImpl.resolveUserFromResetCode() invalidates it at the threshold.
    @Builder.Default
    private int passwordResetAttempts = 0;

    // Brute-force login protection: AuthServiceImpl.login() increments this per BadCredentialsException and sets lockedUntil at the threshold.
    @Builder.Default
    private int failedLoginAttempts = 0;

    private java.time.LocalDateTime lockedUntil;

    @Builder.Default
    private String languagePreference = "EN";

    /** JPA has no CascadeType.SET_NULL, so the service layer must null this out explicitly before deleting a CustomRole. */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "custom_role_id")
    private CustomRole customRole;

    @Override
    public @NonNull Collection<? extends GrantedAuthority> getAuthorities() {
        return List.of(new SimpleGrantedAuthority("ROLE_" + getRole().name()));
    }

    @Override
    public @NonNull String getUsername() {
        return email;
    }

    @Override
    public boolean isAccountNonLocked() {
        return lockedUntil == null || lockedUntil.isBefore(java.time.LocalDateTime.now());
    }

    @Override
    public boolean isEnabled() {
        // Must check `active`: PlatformUserService.deactivate() only sets active=false, so ignoring it lets a deactivated user keep logging in and using issued refresh tokens.
        return !isDeleted() && active;
    }

    public String getFullName() {
        return firstName + " " + lastName;
    }
}
