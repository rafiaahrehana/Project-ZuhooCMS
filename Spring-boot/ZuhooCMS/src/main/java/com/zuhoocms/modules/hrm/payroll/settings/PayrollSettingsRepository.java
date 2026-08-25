package com.zuhoocms.modules.hrm.payroll.settings;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface PayrollSettingsRepository extends JpaRepository<PayrollSettings, Long> {

    Optional<PayrollSettings> findByCompanyId(Long companyId);
}
