package com.zuhoocms.auth.authentication;

import com.zuhoocms.auth.password.ResetPasswordRequest;
import com.zuhoocms.auth.token.TokenRepository;
import com.zuhoocms.auth.token.TokenService;
import com.zuhoocms.auth.token.TokenType;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.crm.client.ClientService;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.security.JwtService;
import com.zuhoocms.shared.audit.AuditService;
import com.zuhoocms.shared.email.EmailService;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.notification.NotificationPreferenceService;
import com.zuhoocms.shared.ratelimit.ClientIpResolver;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.auth.authentication.google.GoogleTokenVerifier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Covers AuthServiceImpl.resetPassword()'s two mutually-exclusive paths: email+code, and the JWT link ClientServiceImpl.invite() emails.
 * The token path is covered here because it cannot be exercised through the browser in dev (no SMTP credentials to deliver the invite), and uses the real JwtService bean rather than a hand-crafted token.
 */
class ResetPasswordTest {

    private UserRepository userRepository;
    private TokenRepository tokenRepository;
    private PasswordEncoder passwordEncoder;
    private JwtService jwtService;
    private AuthServiceImpl authService;

    private static final String SECRET =
        "bHVzT3M3S3k4d1VhQlhuUXZtZjdkTkVqcFpzMlJpNlFGdFljV2VBb0doSXBLbERNbFZiMDkzNFhuVzY=";

    @BeforeEach
    void setUp() {
        userRepository = mock(UserRepository.class);
        tokenRepository = mock(TokenRepository.class);
        passwordEncoder = mock(PasswordEncoder.class);

        // Real bean, not a mock: the point is that a token this class issues is one resetPassword() accepts.
        jwtService = new JwtService();
        ReflectionTestUtils.setField(jwtService, "secret", SECRET);

        authService = new AuthServiceImpl(
            userRepository,
            mock(CompanyRepository.class),
            mock(EmployeeRepository.class),
            mock(ClientRepository.class),
            tokenRepository,
            mock(TokenService.class),
            passwordEncoder,
            mock(GoogleTokenVerifier.class),
            mock(ClientService.class),
            jwtService,
            mock(AuthenticationManager.class),
            mock(EmailService.class),
            mock(AuditService.class),
            mock(NotificationPreferenceService.class),
            mock(SecurityUtil.class),
            // A bare mock suffices: only login() uses this bean, and resetPassword() clears passwordResetAttempts on the entity directly.
            mock(LoginAttemptService.class),
            // Only the login/forgot-password paths resolve a caller IP; resetPassword() never touches this bean.
            mock(ClientIpResolver.class)
        );

        when(passwordEncoder.encode(anyString())).thenAnswer(inv -> "encoded:" + inv.getArgument(0));
    }

    @Test
    void tokenPath_acceptsTheSameTokenClientInviteWouldMint() {
        String email = "invited-client@example.com";
        User user = User.builder().email(email).password("old-hash").build();
        ReflectionTestUtils.setField(user, "id", 42L);
        when(userRepository.findByEmail(email)).thenReturn(Optional.of(user));

        // Exactly ClientServiceImpl.invite()'s call: 7-day PASSWORD_RESET action token.
        String token = jwtService.generateActionToken(email, TokenType.PASSWORD_RESET, 7L * 24 * 60 * 60 * 1000);

        ResetPasswordRequest request = new ResetPasswordRequest();
        request.setToken(token);
        request.setNewPassword("BrandNewPass1!");
        request.setConfirmPassword("BrandNewPass1!");

        authService.resetPassword(request);

        verify(passwordEncoder).encode("BrandNewPass1!");
        assertEquals("encoded:BrandNewPass1!", user.getPassword());
        verify(userRepository).save(user);
        verify(tokenRepository).revokeAllByUserIdAndType(42L, TokenType.REFRESH);
    }

    @Test
    void tokenPath_rejectsAGarbageToken() {
        ResetPasswordRequest request = new ResetPasswordRequest();
        request.setToken("not-a-real-jwt");
        request.setNewPassword("BrandNewPass1!");
        request.setConfirmPassword("BrandNewPass1!");

        BadRequestException ex = assertThrows(BadRequestException.class, () -> authService.resetPassword(request));
        assertTrue(ex.getMessage().contains("Invalid or expired reset link"));
        verifyNoInteractions(userRepository);
    }

    @Test
    void tokenPath_rejectsATokenOfTheWrongActionType() {
        String email = "someone@example.com";
        // A refresh-style token carries no actionType claim, so extractActionType() returns null, which must not equal TokenType.PASSWORD_RESET.
        String accessToken = jwtService.generateAccessToken(email, "COMPANY_OWNER", null);

        ResetPasswordRequest request = new ResetPasswordRequest();
        request.setToken(accessToken);
        request.setNewPassword("BrandNewPass1!");
        request.setConfirmPassword("BrandNewPass1!");

        assertThrows(BadRequestException.class, () -> authService.resetPassword(request));
        verifyNoInteractions(userRepository);
    }

    @Test
    void codePath_stillWorksForForgotPassword() {
        String email = "forgetful-owner@example.com";
        User user = User.builder().email(email).password("old-hash").build();
        ReflectionTestUtils.setField(user, "id", 7L);
        user.setPasswordResetCode("123456");
        user.setPasswordResetCodeExpiresAt(LocalDateTime.now().plusMinutes(10));
        when(userRepository.findByEmail(email)).thenReturn(Optional.of(user));

        ResetPasswordRequest request = new ResetPasswordRequest();
        request.setEmail(email);
        request.setCode("123456");
        request.setNewPassword("AnotherPass1!");
        request.setConfirmPassword("AnotherPass1!");

        authService.resetPassword(request);

        assertEquals("encoded:AnotherPass1!", user.getPassword());
        assertNull(user.getPasswordResetCode());
        assertNull(user.getPasswordResetCodeExpiresAt());
        verify(tokenRepository).revokeAllByUserIdAndType(7L, TokenType.REFRESH);
    }

    @Test
    void codePath_rejectsAnExpiredCode() {
        String email = "forgetful-owner@example.com";
        User user = User.builder().email(email).password("old-hash").build();
        user.setPasswordResetCode("123456");
        user.setPasswordResetCodeExpiresAt(LocalDateTime.now().minusMinutes(1));
        when(userRepository.findByEmail(email)).thenReturn(Optional.of(user));

        ResetPasswordRequest request = new ResetPasswordRequest();
        request.setEmail(email);
        request.setCode("123456");
        request.setNewPassword("AnotherPass1!");
        request.setConfirmPassword("AnotherPass1!");

        assertThrows(BadRequestException.class, () -> authService.resetPassword(request));

        // A save is expected: registerBadCode() records the failed attempt, so never().save() would be wrong here - this test only asserts the password was left alone.
        assertEquals("old-hash", user.getPassword());
        assertEquals(1, user.getPasswordResetAttempts());
        verify(passwordEncoder, never()).encode(anyString());
    }
}
