package com.zuhoocms.auth.user.config;

import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.shared.exception.InternalServerException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.enums.CompanyStatus;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.security.SecureRandom;
import java.util.Base64;

@Slf4j
@Component
@RequiredArgsConstructor
public class AdminInitializer implements CommandLineRunner {

    private final UserRepository userRepository;
    private final CompanyRepository companyRepository;
    private final PasswordEncoder passwordEncoder;
    private final SecureRandom secureRandom = new SecureRandom();

    // Never seed a shared default password: a fixed one means knowing one string logs into every deployment as SUPER_ADMIN.
    // Unless an operator sets one explicitly, each seeded admin gets a random one-time password, stored only hashed and printed once at startup.
    @Value("${admin.initial-password:}")
    private String configuredInitialPassword;

    @Override
    public void run(String... args) {
        User superAdmin = createAdminIfNotExists("superadmin@businessos.com", "Super", "Admin", Role.SUPER_ADMIN);
        createAdminIfNotExists("systemadmin@businessos.com", "System", "Admin", Role.SYSTEM_ADMIN);

        if (superAdmin != null) {
            createPlatformCompanyIfNotExists(superAdmin);
        }
    }

    private User createAdminIfNotExists(String email,
                                        String firstName,
                                        String lastName,
                                        Role role) {
        try {
            if (!userRepository.existsByEmail(email)) {
                String initialPassword = resolveInitialPassword();
                User admin = User.builder()
                        .email(email)
                        .firstName(firstName)
                        .lastName(lastName)
                        .password(passwordEncoder.encode(initialPassword))
                        .role(role)
                        .active(true)
                        .emailVerified(true)
                        .build();

                User saved = userRepository.save(admin);
                log.warn("Seeded {} account {} with a one-time generated password - " +
                                "capture it now and rotate it immediately, it will not be shown again: {}",
                        role, email, initialPassword);
                return saved;
            }
            return userRepository.findByEmail(email).orElse(null);
        } catch (Exception ex) {
            throw new InternalServerException(
                    "Failed to initialize " + role + " account.",
                    ex
            );
        }
    }

    private String resolveInitialPassword() {
        if (configuredInitialPassword != null && !configuredInitialPassword.isBlank()) {
            return configuredInitialPassword;
        }
        byte[] randomBytes = new byte[18];
        secureRandom.nextBytes(randomBytes);
        // One of each character class, so the generated value always satisfies the app's own password policy.
        return "Aa1!" + Base64.getUrlEncoder().withoutPadding().encodeToString(randomBytes);
    }

    private void createPlatformCompanyIfNotExists(User owner) {
        try {
            if (!companyRepository.existsBySubdomain("admin")) {
                Company platformCompany = Company.builder()
                        .companyName("BusinessOS HQ")
                        .companyEmail("hq@businessos.com")
                        .subdomain("admin")
                        .website("businessos.com")
                        .owner(owner)
                        .status(CompanyStatus.ACTIVE)
                        .subscriptionPlan("ENTERPRISE")
                        .active(true)
                        .isPlatformTenant(true)
                        .build();

                companyRepository.save(platformCompany);
                log.info("Successfully seeded BusinessOS Platform Company!");
            }
        } catch (Exception ex) {
            log.error("Failed to seed platform company", ex);
        }
    }
}
