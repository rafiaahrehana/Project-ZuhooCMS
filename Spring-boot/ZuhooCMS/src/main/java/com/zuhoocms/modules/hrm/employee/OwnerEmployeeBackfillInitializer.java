package com.zuhoocms.modules.hrm.employee;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.enums.EmploymentStatus;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.CommandLineRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;

/** One-time startup backfill of the owner's Employee record (see AuthServiceImpl.register): without it every "current user's employee profile" lookup fails with "Employee profile not found". */
@Component
@Order(1)
@RequiredArgsConstructor
public class OwnerEmployeeBackfillInitializer implements CommandLineRunner {

    private final CompanyRepository companyRepository;
    private final EmployeeRepository employeeRepository;

    @Override
    @Transactional
    public void run(String... args) {
        for (Company company : companyRepository.findAll()) {
            User owner = company.getOwner();
            // Per company, not per user: one person can own several companies, and findByUserId matched their employee
            // row in ANY of them, so every company after the first was left with no owner employee record at all -
            // which is exactly the "Employee profile not found" this backfill exists to prevent.
            if (owner == null || employeeRepository.existsByUserIdAndCompanyId(owner.getId(), company.getId())) {
                continue;
            }

            Employee ownerEmployee = Employee.builder()
                .user(owner)
                .company(company)
                .employeeNumber(EmployeeNumberGenerator.next(employeeRepository, company.getId()))
                .jobTitle("Owner")
                .employmentStatus(EmploymentStatus.ACTIVE)
                .hireDate(LocalDate.now())
                .active(true)
                .build();
            // saveAndFlush so the next iteration's MAX-based number lookup sees this row.
            employeeRepository.saveAndFlush(ownerEmployee);
        }
    }
}
