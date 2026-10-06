package com.zuhoocms.modules.demo;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.Objects;
import java.util.Optional;

/** Identifies the demo tenant as the company the demo user owns, never whatever company holds subdomain "demo" - a regular tenant could hold that. */
@Component
@RequiredArgsConstructor
public class DemoAccount {

    private final UserRepository userRepository;
    private final CompanyRepository companyRepository;

    private volatile Long demoUserId;

    public boolean isDemoUser(User user) {
        return user != null && user.getEmail() != null
                && DemoDataSeeder.DEMO_OWNER_EMAIL.equalsIgnoreCase(user.getEmail());
    }

    /** The demo owner's user id, or null when there is no demo account. Cached once found. */
    public Long demoUserId() {
        Long id = demoUserId;
        if (id == null) {
            id = userRepository.findByEmail(DemoDataSeeder.DEMO_OWNER_EMAIL).map(User::getId).orElse(null);
            demoUserId = id;
        }
        return id;
    }

    /** Uses the owner FK only (a lazy proxy's id needs no initialisation), so it is safe outside a transaction. */
    public boolean isDemoCompany(Company company) {
        if (company == null || company.getOwner() == null) return false;
        Long demo = demoUserId();
        return demo != null && Objects.equals(company.getOwner().getId(), demo);
    }

    public Optional<Company> demoCompany() {
        Long demo = demoUserId();
        return demo == null ? Optional.empty() : companyRepository.findByOwnerId(demo);
    }

    public Optional<Long> demoCompanyId() {
        return demoCompany().map(Company::getId);
    }
}
