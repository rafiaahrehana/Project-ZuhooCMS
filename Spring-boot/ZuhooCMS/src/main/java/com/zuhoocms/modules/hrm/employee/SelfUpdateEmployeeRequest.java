package com.zuhoocms.modules.hrm.employee;

import com.zuhoocms.enums.Gender;
import jakarta.validation.constraints.Size;
import lombok.Data;

/**
 * Fields an employee may edit on their OWN record via PATCH /api/employees/me: a deliberately narrow subset of UpdateEmployeeRequest.
 * Job title, department, designation, employment type/status, salary, bank details, hire dates and date of birth are EMPLOYEE_UPDATE-only, since self-editing them would change own pay or job standing.
 * National ID and Tax ID stay self-editable as self-reported identity fields.
 */
@Data
public class SelfUpdateEmployeeRequest {
    @Size(max = 30)
    private String workPhone;
    // Personal mobile number: lives on the linked User account (User.phone), distinct from workPhone on the Employee record.
    @Size(max = 30)
    private String phone;
    @Size(max = 500)
    private String profileImageUrl;
    private Gender gender;
    @Size(max = 100)
    private String fatherName;
    @Size(max = 100)
    private String motherName;
    @Size(max = 50)
    private String nationalId;
    @Size(max = 50)
    private String taxId;
    private com.zuhoocms.shared.address.AddressRequest location;
    @Size(max = 100)
    private String emergencyContactName;
    @Size(max = 30)
    private String emergencyContactPhone;
    @Size(max = 50)
    private String emergencyContactRelation;
}
