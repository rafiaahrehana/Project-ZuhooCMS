package com.zuhoocms.modules.demo;

import com.zuhoocms.auth.authentication.LoginResponse;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.security.JwtService;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * "See Demo" drops an anonymous visitor into the seeded demo tenant by minting a short-lived access token for the demo owner: no password exchange, and the stored password is random, so this endpoint is the only way in.
 * Handing sessions to the whole internet is only acceptable because DemoReadOnlyFilter blocks every mutation the token could attempt.
 * No refresh token on purpose: when the access token dies, the demo is over.
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/public/demo")
public class DemoSessionController {

    /** Demo sessions outlive a coffee break but not a lunch: 45 minutes. */
    private static final long DEMO_SESSION_MS = 45L * 60 * 1000;

    private final UserRepository userRepository;
    private final CompanyRepository companyRepository;
    private final JwtService jwtService;

    @Value("${app.demo.enabled:false}")
    private boolean demoEnabled;

    @PostMapping("/session")
    public ResponseEntity<LoginResponse> start() {
        if (!demoEnabled) {
            throw new ResourceNotFoundException("The demo is not available right now");
        }
        User demoUser = userRepository.findByEmail(DemoDataSeeder.DEMO_OWNER_EMAIL)
                .orElseThrow(() -> new ResourceNotFoundException("The demo is not available right now"));
        // The demo owner's own company - not whichever company holds subdomain "demo".
        Company company = companyRepository.findByOwnerId(demoUser.getId())
                .orElseThrow(() -> new ResourceNotFoundException("The demo is not available right now"));

        // Minting is rate-limited per IP by PublicEndpointRateLimitFilter.
        String accessToken = jwtService.generateAccessToken(
                demoUser.getEmail(), demoUser.getRole().name(), company.getId(), DEMO_SESSION_MS);

        return ResponseEntity.ok(new LoginResponse(
                demoUser.getId(), demoUser.getFirstName(), demoUser.getEmail(),
                demoUser.getRole(), company.getId(), accessToken, null));
    }
}
