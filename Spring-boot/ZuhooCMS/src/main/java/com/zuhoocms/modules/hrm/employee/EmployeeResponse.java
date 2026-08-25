package com.zuhoocms.modules.hrm.employee;

import com.zuhoocms.enums.EmploymentStatus;
import com.zuhoocms.enums.EmploymentType;
import com.zuhoocms.enums.Gender;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Getter
@Setter
public class EmployeeResponse {
    private Long id;
    private Long userId;
    private String firstName;
    private String lastName;
    private String email;
    private String phone;
    private String image;
    private String employeeNumber;
    private String officialEmail;
    private String workPhone;
    private String profileImageUrl;
    private String nationalId;
    private String taxId;
    private String costCenter;
    private String officeLocation;
    private String jobTitle;
    private EmploymentType employmentType;
    private EmploymentStatus employmentStatus;
    private Gender gender;
    private LocalDate dateOfBirth;
    private String fatherName;
    private String motherName;
    private com.zuhoocms.shared.address.AddressResponse location;
    private LocalDate hireDate;
    private LocalDate confirmationDate;
    private LocalDate probationEndDate;
    private LocalDate contractEndDate;
    private Long departmentId;
    private String departmentName;
    private Long designationId;
    private String designationName;
    private Long reportingManagerId;
    private String reportingManagerName;
    private Long shiftId;
    private String shiftName;
    private BigDecimal basicSalary;
    private BigDecimal houseRent;
    private BigDecimal medicalAllowance;
    private BigDecimal transportAllowance;
    private BigDecimal billableRate;
    private String bankName;
    private String bankAccountNumber;
    private String bankRoutingNumber;
    private String emergencyContactName;
    private String emergencyContactPhone;
    private String emergencyContactRelation;
    private boolean active;
    private LocalDateTime createdAt;
    private Long customRoleId;
    private String customRoleName;
}
