package com.zuhoocms.modules.hrm.employee;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.modules.hrm.attendance.shift.Shift;
import com.zuhoocms.modules.hrm.department.Department;

import com.zuhoocms.modules.hrm.designation.Designation;
import org.springframework.stereotype.Component;

@Component
public class EmployeeMapper {

    private final com.zuhoocms.shared.address.AddressMapper addressMapper;
    private final EmployeeUserResolver userResolver;

    public EmployeeMapper(com.zuhoocms.shared.address.AddressMapper addressMapper,
                          EmployeeUserResolver userResolver) {
        this.addressMapper = addressMapper;
        this.userResolver = userResolver;
    }

    public EmployeeResponse toDTO(Employee e) {
        // Associations go through EmployeeUserResolver: a lazy proxy to a soft-deleted row otherwise throws and 500s the whole employee list/detail.
        Long companyId = userResolver.companyId(e);
        User u = userResolver.liveUser(e);
        EmployeeUserResolver.UserSnapshot legacy = (u == null && e.getUser() != null)
                ? userResolver.snapshot(e.getId(), companyId) : null;
        Department d = userResolver.loadable(e.getDepartment());
        Designation designation = userResolver.loadable(e.getDesignation());
        Employee mgrRef = e.getReportingManager();
        Employee mgr = userResolver.loadable(mgrRef);
        Shift shift = userResolver.loadable(e.getShift());
        User mgrU = mgr != null ? userResolver.liveUser(mgr) : null;
        String mgrName = null;
        if (mgrU != null) {
            mgrName = mgrU.getFullName();
        } else if (mgrRef != null) {
            EmployeeUserResolver.UserSnapshot ms = userResolver.snapshot(userResolver.id(mgrRef), companyId);
            mgrName = ms != null ? ms.fullName() : null;
        }
        EmployeeResponse r = new EmployeeResponse();
        r.setId(e.getId());
        if (u != null) {
            r.setUserId(u.getId());
            r.setFirstName(u.getFirstName());
            r.setLastName(u.getLastName());
            r.setEmail(u.getEmail());
            r.setPhone(u.getPhone());
            r.setImage(u.getImage());
        } else if (legacy != null) {
            r.setUserId(legacy.id());
            r.setFirstName(legacy.firstName());
            r.setLastName(legacy.lastName());
            r.setEmail(legacy.email());
            r.setPhone(legacy.phone());
            r.setImage(legacy.image());
        }
        r.setEmployeeNumber(e.getEmployeeNumber());
        r.setOfficialEmail(e.getOfficialEmail());
        r.setWorkPhone(e.getWorkPhone());
        r.setProfileImageUrl(e.getProfileImageUrl());
        r.setNationalId(e.getNationalId());
        r.setTaxId(e.getTaxId());
        r.setCostCenter(e.getCostCenter());
        r.setOfficeLocation(e.getOfficeLocation());
        r.setJobTitle(e.getJobTitle());
        r.setEmploymentType(e.getEmploymentType());
        r.setEmploymentStatus(e.getEmploymentStatus());
        r.setGender(e.getGender());
        r.setDateOfBirth(e.getDateOfBirth());
        r.setFatherName(e.getFatherName());
        r.setMotherName(e.getMotherName());
        r.setLocation(addressMapper.toResponse(e.getLocation()));
        r.setHireDate(e.getHireDate());
        r.setConfirmationDate(e.getConfirmationDate());
        r.setProbationEndDate(e.getProbationEndDate());
        r.setContractEndDate(e.getContractEndDate());
        r.setDepartmentId(userResolver.id(e.getDepartment()));
        r.setDepartmentName(d != null ? d.getName() : null);
        r.setDesignationId(userResolver.id(e.getDesignation()));
        r.setDesignationName(designation != null ? designation.getName() : null);
        r.setReportingManagerId(userResolver.id(mgrRef));
        r.setReportingManagerName(mgrName);
        r.setShiftId(userResolver.id(e.getShift()));
        r.setShiftName(shift != null ? shift.getName() : null);
        r.setBasicSalary(e.getBasicSalary());
        r.setHouseRent(e.getHouseRent());
        r.setMedicalAllowance(e.getMedicalAllowance());
        r.setTransportAllowance(e.getTransportAllowance());
        r.setBillableRate(e.getBillableRate());
        r.setBankName(e.getBankName());
        // Needed by the payroll disbursement screen to show incomplete bank details before the bank file is run.
        r.setBankAccountNumber(e.getBankAccountNumber());
        r.setBankRoutingNumber(e.getBankRoutingNumber());
        r.setEmergencyContactName(e.getEmergencyContactName());
        r.setEmergencyContactPhone(e.getEmergencyContactPhone());
        r.setEmergencyContactRelation(e.getEmergencyContactRelation());
        r.setActive(e.isActive());
        r.setCreatedAt(e.getCreatedAt());
        com.zuhoocms.auth.role.entity.CustomRole customRole = u != null ? userResolver.loadable(u.getCustomRole()) : null;
        if (customRole != null) {
            r.setCustomRoleId(customRole.getId());
            r.setCustomRoleName(customRole.getName());
        } else if (legacy != null) {
            r.setCustomRoleId(legacy.customRoleId());
            r.setCustomRoleName(legacy.customRoleName());
        }
        return r;
    }
}
