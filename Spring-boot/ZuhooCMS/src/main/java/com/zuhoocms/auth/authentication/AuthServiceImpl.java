package com.zuhoocms.auth.authentication;

import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.token.TokenService;
import com.zuhoocms.auth.token.TokenType;
import com.zuhoocms.auth.token.UserToken;
import com.zuhoocms.auth.token.TokenRepository;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserMapper;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.auth.user.UserResponse;
import com.zuhoocms.auth.password.ChangePasswordRequest;
import com.zuhoocms.auth.password.ForgotPasswordRequest;
import com.zuhoocms.auth.password.ResetPasswordRequest;
import com.zuhoocms.auth.password.VerifyResetCodeRequest;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeNumberGenerator;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.enums.CompanyStatus;
import com.zuhoocms.enums.EmploymentStatus;
import com.zuhoocms.shared.audit.AuditService;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.company.RegisterRequest;
import com.zuhoocms.shared.email.EmailService;
import com.zuhoocms.security.JwtService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.exception.UnauthorizedException;
import com.zuhoocms.auth.authentication.google.GoogleAuthRequest;
import com.zuhoocms.auth.authentication.google.GoogleRegisterRequest;
import com.zuhoocms.auth.authentication.google.GoogleSignInResponse;
import com.zuhoocms.auth.authentication.google.GoogleTokenVerifier;
import com.zuhoocms.modules.crm.client.ClientService;
import com.zuhoocms.modules.crm.client.PublicClientRegisterRequest;
import com.zuhoocms.shared.notification.NotificationPreferenceService;
import lombok.RequiredArgsConstructor;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class AuthServiceImpl implements AuthService {

    private static final long PASSWORD_RESET_MINS = 15;
    private static final int  EMAIL_VERIFY_CODE_MINUTES = 15;
    // Caps guesses per issued email-verification/password-reset code: 6 digits is only 1,000,000 combinations, brute-forceable within the 15-minute window.
    private static final int  MAX_CODE_ATTEMPTS = 5;
    private static final java.security.SecureRandom CODE_RANDOM = new java.security.SecureRandom();

    private final UserRepository userRepository;
    private final CompanyRepository companyRepository;
    private final EmployeeRepository employeeRepository;
    private final ClientRepository clientRepository;
    private final TokenRepository tokenRepository;
    private final TokenService tokenService;
    private final PasswordEncoder passwordEncoder;
    private final GoogleTokenVerifier googleTokenVerifier;
    private final ClientService clientService;
    private final JwtService jwtService;
    private final AuthenticationManager authManager;
    private final EmailService emailService;
    private final AuditService auditService;
    private final NotificationPreferenceService notificationPreferenceService;
    private final SecurityUtil securityUtil;
    private final LoginAttemptService loginAttemptService;
    private final com.zuhoocms.shared.ratelimit.ClientIpResolver clientIpResolver;

    @Value("${jwt.refresh-expiration-ms:604800000}")
    private long refreshExpirationMs;

    @Value("${app.trial-days:14}")
    private int trialDays;

    @Override
    @Transactional
    public UserResponse register(RegisterRequest request) {
        // Case-insensitive and includes soft-deleted rows: "Foo@x.com" after "foo@x.com" otherwise passes here and dies on the unique index.
        String normalizedEmail = request.getEmail().toLowerCase().trim();
        if (userRepository.existsAnyByEmailIgnoreCase(normalizedEmail)) {
            throw new BadRequestException("An account with this email already exists");
        }
        String subdomain = request.getSubdomain().toLowerCase().trim();
        com.zuhoocms.modules.company.ReservedSubdomains.requireAllowed(subdomain);
        if (companyRepository.existsAnyBySubdomain(subdomain)) {
            throw new BadRequestException("This subdomain is already taken");
        }

        // Must start emailVerified(false): setting it true here makes verifyEmail()'s "already verified" guard fire and skip trial activation and the welcome email.
        String verificationCode = generateVerificationCode();
        User user = User.builder()
            .firstName(request.getFirstName())
            .lastName(request.getLastName())
            .email(request.getEmail().toLowerCase().trim())
            .password(passwordEncoder.encode(request.getPassword()))
            .role(Role.COMPANY_OWNER)
            .active(true)
            .emailVerified(false)
            .emailVerificationCode(verificationCode)
            .emailVerificationCodeExpiresAt(LocalDateTime.now().plusMinutes(EMAIL_VERIFY_CODE_MINUTES))
            .build();
        userRepository.save(user);

        Company company = Company.builder()
            .companyName(request.getCompanyName())
            .subdomain(request.getSubdomain().toLowerCase().trim())
            .companyEmail(blankToNull(request.getCompanyEmail() != null ? request.getCompanyEmail().toLowerCase().trim() : null))
            .companyPhone(blankToNull(request.getCompanyPhone()))
            .locationDetail(request.getLocation())
            .subscriptionPlan("FREE")
            .status(CompanyStatus.TRIAL)
            .owner(user)
            .build();
        companyRepository.save(company);

        // Every "my work" scope (leads, leaves, timesheets, expenses, payroll) looks up an Employee record; without this the owner hits "Employee profile not found".
        Employee ownerEmployee = Employee.builder()
            .user(user)
            .company(company)
            .employeeNumber(EmployeeNumberGenerator.next(employeeRepository, company.getId()))
            .jobTitle("Owner")
            .employmentStatus(EmploymentStatus.ACTIVE)
            .hireDate(LocalDate.now())
            .active(true)
            .build();
        employeeRepository.save(ownerEmployee);

        emailService.sendVerificationEmail(user.getEmail(), user.getFirstName(), verificationCode);

        return UserMapper.toResponse(user);
    }

    @Override
    @Transactional
    public LoginResponse login(LoginRequest request) {
        // Password brute-force guard: loginAttemptService locks the account after repeated failures, then isAccountNonLocked() fails the next attempt fast as a 403 LockedException.
        // Must stay a separate bean so the counter write gets its own REQUIRES_NEW transaction - see its Javadoc.
        try {
            authManager.authenticate(
                new UsernamePasswordAuthenticationToken(request.getEmail(), request.getPassword()));
        } catch (org.springframework.security.authentication.BadCredentialsException ex) {
            loginAttemptService.registerFailedAttempt(request.getEmail());
            throw ex;
        }

        User user = userRepository.findByEmail(request.getEmail())
            .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        // Checked after the password so it reveals nothing to a caller who doesn't know it; without it an unverified sign-up gets a session and a TRIAL company with no end date that never expires.
        if (user.getRole() == Role.COMPANY_OWNER && !user.isEmailVerified()) {
            throw new com.zuhoocms.shared.exception.ApiException(
                "Please verify your email address before logging in. Check your inbox for the code.",
                org.springframework.http.HttpStatus.FORBIDDEN);
        }

        if (user.getFailedLoginAttempts() > 0 || user.getLockedUntil() != null) {
            user.setFailedLoginAttempts(0);
            user.setLockedUntil(null);
        }

        Long companyId = resolveCompanyId(user);

        if (user.isTenantUser() && companyId != null) {
            Company company = companyRepository.findById(companyId).orElse(null);
            if (company != null && (company.getStatus() == CompanyStatus.SUSPENDED
                    || company.getStatus() == CompanyStatus.DEACTIVATED)) {
                throw new UnauthorizedException(
                    "This company account has been " + company.getStatus().name().toLowerCase()
                        + ". Please contact support.");
            }
        }

        String accessToken  = jwtService.generateAccessToken(
            user.getEmail(), user.getRole().name(), companyId);
        String refreshToken = jwtService.generateRefreshToken(user.getEmail());

        // Deliberately does NOT revoke existing refresh tokens: concurrent sessions must keep working. Only resetPassword()/changePassword() revoke them all.
        persistToken(user, refreshToken, TokenType.REFRESH,
            LocalDateTime.now().plusSeconds(refreshExpirationMs / 1000));

        // Extract IP synchronously on the main thread before passing to async audit
        auditService.logLogin(user, companyId, resolveClientIp());
        

        return new LoginResponse(user.getId(), user.getFirstName(), user.getEmail(),
            user.getRole(), companyId, accessToken, refreshToken);
    }

    @Override
    @Transactional
    public JwtResponse refreshToken(RefreshTokenRequest request) {
        UserToken stored = tokenRepository
            .findByTokenAndType(request.getRefreshToken(), TokenType.REFRESH)
            .orElseThrow(() -> new BadRequestException("Invalid refresh token"));

        if (!stored.isValid()) {
            // Reuse of a *revoked* token means the real client already rotated it away, so the presenter likely holds a stolen copy; revoke the whole chain rather than just this attempt.
            if (stored.isRevoked()) {
                revokeAllRefreshTokens(stored.getUser());
                throw new BadRequestException(
                    "This refresh token was already used. All sessions have been logged out for security - please log in again.");
            }
            throw new BadRequestException(
                "Refresh token has expired or been revoked. Please log in again.");
        }

        User user = stored.getUser();

        // PlatformUserService.deactivate() only flips this flag - it revokes no tokens, so without this a deactivated user keeps minting access tokens from a still-valid refresh token.
        if (!user.isActive()) {
            stored.setRevoked(true);
            throw new UnauthorizedException("Your account is inactive. Please contact admin.");
        }

        Long companyId = resolveCompanyId(user);

        // Mirrors login(): CompanyServiceImpl.changeStatus()'s token revocation is a best-effort sweep, so re-check here to close the race with a refresh landing mid-sweep.
        if (user.isTenantUser() && companyId != null) {
            Company company = companyRepository.findById(companyId).orElse(null);
            if (company != null && (company.getStatus() == CompanyStatus.SUSPENDED
                    || company.getStatus() == CompanyStatus.DEACTIVATED)) {
                throw new UnauthorizedException(
                    "This company account has been " + company.getStatus().name().toLowerCase()
                        + ". Please contact support.");
            }
        }

        stored.setRevoked(true);

        String newAccess  = jwtService.generateAccessToken(
            user.getEmail(), user.getRole().name(), companyId);
        String newRefresh = jwtService.generateRefreshToken(user.getEmail());

        persistToken(user, newRefresh, TokenType.REFRESH,
            LocalDateTime.now().plusSeconds(refreshExpirationMs / 1000));

        return new JwtResponse(newAccess, newRefresh);
    }

    @Override
    @Transactional
    public void logout(RefreshTokenRequest request) {
        tokenRepository.findByTokenAndType(request.getRefreshToken(), TokenType.REFRESH)
            .ifPresent(token -> {
                Long companyId = resolveCompanyId(token.getUser());
                // Extract IP synchronously on the main thread before passing to async audit
                String clientIp = resolveClientIp();
                auditService.logLogout(token.getUser(), companyId, clientIp);
                token.setRevoked(true);
            });
    }

    @Override
    @Transactional
    public void verifyEmail(VerifyEmailRequest request) {
        User user = userRepository.findByEmail(request.getEmail().toLowerCase().trim())
            .orElseThrow(() -> new BadRequestException("Invalid or expired verification code"));

        if (user.isEmailVerified()) {
            throw new BadRequestException("This email is already verified");
        }

        if (user.getEmailVerificationCode() == null
                || !user.getEmailVerificationCode().equals(request.getCode().trim())
                || user.getEmailVerificationCodeExpiresAt() == null
                || user.getEmailVerificationCodeExpiresAt().isBefore(LocalDateTime.now())) {
            registerBadCode(user, true);
            throw new BadRequestException("Invalid or expired verification code");
        }

        user.setActive(true);
        user.setEmailVerified(true);
        user.setEmailVerificationCode(null);
        user.setEmailVerificationCodeExpiresAt(null);
        user.setEmailVerificationAttempts(0);
        userRepository.save(user);

        companyRepository.findByOwnerId(user.getId()).ifPresent(company -> {
            company.setStatus(CompanyStatus.TRIAL);
            company.setSubscriptionStart(LocalDate.now());
            company.setSubscriptionEnd(LocalDate.now().plusDays(trialDays));
            companyRepository.save(company);
            notificationPreferenceService.createDefaultsForUser(user.getId());
            emailService.sendWelcomeCompanyEmail(user.getEmail(), user.getFirstName(), company.getCompanyName());
            
        });
    }

    @Override
    @Transactional
    public void resendVerification(ResendVerificationRequest request) {
        // ifPresent, not orElseThrow: always 200 OK regardless of whether the email exists, to prevent user enumeration.
        // Normalised like every other lookup in this class: registration stores the address lower-cased and trimmed,
        // and login, verification and resolveUserFromResetCode all normalise before looking it up. These two did not,
        // so "Pat@Example.com" matched nothing and no mail was sent. Both of these endpoints answer vaguely on
        // purpose, so as not to reveal whether an address is registered - which means the user had no way to tell a
        // silent miss from a delivered mail. Normalising one side of a pair and not the other is the same fault as
        // the role name trimmed after its own uniqueness check.
        userRepository.findByEmail(request.getEmail().toLowerCase().trim()).ifPresent(user -> {
            if (!user.isEmailVerified()) {
                String newCode = generateVerificationCode();
                user.setEmailVerificationCode(newCode);
                user.setEmailVerificationCodeExpiresAt(LocalDateTime.now().plusMinutes(EMAIL_VERIFY_CODE_MINUTES));
                // A fresh code resets the brute-force counter: guesses spent against the old code no longer apply.
                user.setEmailVerificationAttempts(0);
                userRepository.save(user);
                emailService.sendVerificationEmail(user.getEmail(), user.getFirstName(), newCode);
            }
        });
    }

    private String generateVerificationCode() {
        return String.format("%06d", CODE_RANDOM.nextInt(1_000_000));
    }

    // companyEmail/companyPhone are optional but @Column(unique = true): the Angular form sends "" for a blank field, which a unique constraint treats as a real value and 409s on the second registration.
    private String blankToNull(String value) {
        return (value == null || value.isBlank()) ? null : value;
    }

    @Override
    @Transactional
    public void forgotPassword(ForgotPasswordRequest request) {
        // Normalised like every other lookup in this class: registration stores the address lower-cased and trimmed,
        // and login, verification and resolveUserFromResetCode all normalise before looking it up. These two did not,
        // so "Pat@Example.com" matched nothing and no mail was sent. Both of these endpoints answer vaguely on
        // purpose, so as not to reveal whether an address is registered - which means the user had no way to tell a
        // silent miss from a delivered mail. Normalising one side of a pair and not the other is the same fault as
        // the role name trimmed after its own uniqueness check.
        userRepository.findByEmail(request.getEmail().toLowerCase().trim()).ifPresent(user -> {
            String resetCode = generateVerificationCode();
            user.setPasswordResetCode(resetCode);
            user.setPasswordResetCodeExpiresAt(LocalDateTime.now().plusMinutes(PASSWORD_RESET_MINS));
            // Same reasoning as resendVerification(): a newly issued code starts with a clean attempt counter.
            user.setPasswordResetAttempts(0);
            userRepository.save(user);
            emailService.sendPasswordResetEmail(user.getEmail(), user.getFirstName(), resetCode);
        });
    }

    @Override
    // Not readOnly: resolveUserFromResetCode() persists the failed-attempt counter, and readOnly's MANUAL flush mode would silently drop that write.
    @Transactional
    public void verifyResetCode(VerifyResetCodeRequest request) {
        resolveUserFromResetCode(request.getEmail(), request.getCode());
    }

    @Override
    @Transactional
    public void resetPassword(ResetPasswordRequest request) {
        if (!request.getNewPassword().equals(request.getConfirmPassword())) {
            throw new BadRequestException("Passwords do not match");
        }

        User user = (request.getToken() != null && !request.getToken().isBlank())
            ? resolveUserFromResetToken(request.getToken())
            : resolveUserFromResetCode(request.getEmail(), request.getCode());

        user.setPassword(passwordEncoder.encode(request.getNewPassword()));
        user.setPasswordResetCode(null);
        user.setPasswordResetCodeExpiresAt(null);
        user.setPasswordResetAttempts(0);
        userRepository.save(user);

        revokeAllRefreshTokens(user);

    }

    // Long-lived JWT link path, now only issued by ClientServiceImpl.invite() for the emailed "Set Your Password" link; forgotPassword() issues a code instead.
    private User resolveUserFromResetToken(String tokenStr) {
        if (!jwtService.isTokenValid(tokenStr) || jwtService.extractActionType(tokenStr) != TokenType.PASSWORD_RESET) {
            throw new BadRequestException("Invalid or expired reset link");
        }
        String email = jwtService.extractEmail(tokenStr);
        return userRepository.findByEmail(email)
            .orElseThrow(() -> new BadRequestException("User not found for this token"));
    }

    // "Forgot password" numeric-code path; the error is deliberately identical for unknown user, wrong code and expired code so registered emails aren't leaked (mirrors verifyEmail()).
    private User resolveUserFromResetCode(String email, String code) {
        if (email == null || code == null) {
            throw new BadRequestException("Invalid or expired reset code");
        }
        User user = userRepository.findByEmail(email.toLowerCase().trim())
            .orElseThrow(() -> new BadRequestException("Invalid or expired reset code"));

        if (user.getPasswordResetCode() == null
                || !user.getPasswordResetCode().equals(code)
                || user.getPasswordResetCodeExpiresAt() == null
                || user.getPasswordResetCodeExpiresAt().isBefore(LocalDateTime.now())) {
            registerBadCode(user, false);
            throw new BadRequestException("Invalid or expired reset code");
        }
        return user;
    }

    // Shared brute-force counter for verification and reset codes: at MAX_CODE_ATTEMPTS the code is invalidated outright so the 6-digit space can't keep being probed.
    private void registerBadCode(User user, boolean isEmailVerification) {
        if (isEmailVerification) {
            int attempts = user.getEmailVerificationAttempts() + 1;
            user.setEmailVerificationAttempts(attempts);
            if (attempts >= MAX_CODE_ATTEMPTS) {
                user.setEmailVerificationCode(null);
                user.setEmailVerificationCodeExpiresAt(null);
            }
        } else {
            int attempts = user.getPasswordResetAttempts() + 1;
            user.setPasswordResetAttempts(attempts);
            if (attempts >= MAX_CODE_ATTEMPTS) {
                user.setPasswordResetCode(null);
                user.setPasswordResetCodeExpiresAt(null);
            }
        }
        userRepository.save(user);
    }

    @Override
    @Transactional
    public void changePassword(ChangePasswordRequest request) {
        User principal = securityUtil.getCurrentUser();
        if (principal == null) {
            throw new UnauthorizedException("User not authenticated");
        }

        if (!request.getNewPassword().equals(request.getConfirmPassword())) {
            throw new BadRequestException("Passwords do not match");
        }

        User user = userRepository.findById(principal.getId())
            .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        if (!passwordEncoder.matches(request.getCurrentPassword(), user.getPassword())) {
            throw new BadRequestException("Current password is incorrect");
        }

        user.setPassword(passwordEncoder.encode(request.getNewPassword()));
        userRepository.save(user);

        // Logs out every other session, as resetPassword does; the current access token stays valid until it expires, so the frontend must redirect to login.
        revokeAllRefreshTokens(user);
    }


    private Long resolveCompanyId(User user) {
        return switch (user.getRole()) {
            // Platform staff have no home tenant, so their token must carry no companyId - a fixed one makes every platform login behave like a login into that tenant.
            case SUPER_ADMIN, SYSTEM_ADMIN, SUPPORT_AGENT, SUPPORT_MANAGER, MARKETING_MANAGER, PLATFORM_ACCOUNTANT, SALES_MANAGER -> null;
            case COMPANY_OWNER -> companyRepository.findByOwnerId(user.getId())
                .map(Company::getId).orElse(null);
            case EMPLOYEE -> employeeRepository.findCompanyIdByUserId(user.getId())
                .orElse(null);
            case CLIENT -> clientRepository.findCompanyIdByUserId(user.getId())
                .orElse(null);
        };
    }


    // Must NEVER be called from inside an @Async method (no request context there) — pass the resolved value as a parameter instead.
    private String resolveClientIp() {
        try {
            ServletRequestAttributes attrs =
                (ServletRequestAttributes) RequestContextHolder.currentRequestAttributes();
            HttpServletRequest request = attrs.getRequest();
            // Trusted-proxy aware: X-Forwarded-For only counts when the peer is a configured proxy.
            return clientIpResolver.resolve(request);
        } catch (Exception e) {
            return "unknown";
        }
    }

    @Override
    @Transactional
    public GoogleSignInResponse googleSignIn(GoogleAuthRequest request) {

        GoogleTokenVerifier.GoogleIdentity identity = googleTokenVerifier.verify(request.getIdToken());

        User user = userRepository.findByEmail(identity.email()).orElse(null);

        // Cannot create the user here: a Google token carries no tenant, so the app collects a company and calls googleRegister().
        if (user == null) {
            return GoogleSignInResponse.needsRegistration(
                    identity.email(), identity.firstName(), identity.lastName());
        }

        return GoogleSignInResponse.loggedIn(issueSession(user));
    }

    @Override
    @Transactional
    public LoginResponse googleRegister(GoogleRegisterRequest request) {

        // Verified again on purpose: the earlier googleSignIn() proves nothing about this request, so the email comes from this token, not from the client.
        GoogleTokenVerifier.GoogleIdentity identity = googleTokenVerifier.verify(request.getIdToken());

        if (userRepository.existsByEmail(identity.email())) {
            throw new BadRequestException(
                    "An account with this email already exists. Sign in instead.");
        }

        // Reuses ordinary public client registration so the company-active check, welcome email and notification defaults match an email/password signup.
        PublicClientRegisterRequest registration = new PublicClientRegisterRequest();
        registration.setFirstName(identity.firstName());
        registration.setLastName(identity.lastName());
        registration.setEmail(identity.email());
        // Random, never used: the account signs in with Google, and "forgot password" is the route to setting a real one.
        registration.setPassword(UUID.randomUUID() + "Aa1!");
        registration.setPhone(request.getPhone());
        registration.setCompanyId(request.getCompanyId());
        registration.setClientCompanyName(request.getClientCompanyName());
        registration.setIndustry(request.getIndustry());
        registration.setWebsite(request.getWebsite());

        clientService.registerPublic(registration);

        User user = userRepository.findByEmail(identity.email())
                .orElseThrow(() -> new ResourceNotFoundException("User not found after registration"));

        return issueSession(user);
    }

    /** Tail end of login(), shared so a Google sign-in yields an identical session: same claims, expiry and refresh behaviour. */
    private LoginResponse issueSession(User user) {

        Long companyId = resolveCompanyId(user);

        if (user.isTenantUser() && companyId != null) {
            Company company = companyRepository.findById(companyId).orElse(null);
            if (company != null && (company.getStatus() == CompanyStatus.SUSPENDED
                    || company.getStatus() == CompanyStatus.DEACTIVATED)) {
                throw new UnauthorizedException(
                    "This company account has been " + company.getStatus().name().toLowerCase()
                        + ". Please contact support.");
            }
        }

        String accessToken  = jwtService.generateAccessToken(
            user.getEmail(), user.getRole().name(), companyId);
        String refreshToken = jwtService.generateRefreshToken(user.getEmail());

        persistToken(user, refreshToken, TokenType.REFRESH,
            LocalDateTime.now().plusSeconds(refreshExpirationMs / 1000));

        auditService.logLogin(user, companyId, resolveClientIp());

        return new LoginResponse(user.getId(), user.getFirstName(), user.getEmail(),
            user.getRole(), companyId, accessToken, refreshToken);
    }

    private void persistToken(User user, String value, TokenType type, LocalDateTime expiresAt) {
        tokenRepository.save(UserToken.builder()
            .token(value)
            .tokenType(type)
            .user(user)
            .expiresAt(expiresAt)
            .build());
    }

    private void revokeAllRefreshTokens(User user) {
        tokenRepository.revokeAllByUserIdAndType(user.getId(), TokenType.REFRESH);
    }
}
