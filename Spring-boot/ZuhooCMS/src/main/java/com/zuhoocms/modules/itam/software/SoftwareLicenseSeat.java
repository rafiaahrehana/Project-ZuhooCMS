package com.zuhoocms.modules.itam.software;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.hrm.employee.Employee;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.time.LocalDate;

/** Which employee holds a seat: the licence itself only stores an aggregate count, so offboarding could not answer "which licences does this employee have?". releasedAt == null means still held. */
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "software_license_seats")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class SoftwareLicenseSeat extends BaseEntity {

    private Long companyId;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "license_id", nullable = false)
    private SoftwareLicense license;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "employee_id", nullable = false)
    private Employee employee;

    private LocalDate assignedAt;
    private LocalDate releasedAt;
}
