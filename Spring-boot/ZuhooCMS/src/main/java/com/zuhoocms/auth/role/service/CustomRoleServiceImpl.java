package com.zuhoocms.auth.role.service;

import com.zuhoocms.auth.role.dto.CustomRoleRequest;
import com.zuhoocms.auth.role.dto.CustomRoleResponse;
import com.zuhoocms.auth.role.entity.CustomRole;
import com.zuhoocms.auth.role.entity.Permission;
import com.zuhoocms.auth.role.entity.RolePermission;
import com.zuhoocms.auth.role.mapper.CustomRoleMapper;
import com.zuhoocms.auth.role.repository.CustomRoleRepository;
import com.zuhoocms.auth.role.repository.PermissionRepository;
import com.zuhoocms.auth.role.repository.RolePermissionRepository;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.audit.AuditService;
import com.zuhoocms.enums.AuditAction;
import com.zuhoocms.enums.AuditEntityType;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
public class CustomRoleServiceImpl implements CustomRoleService {

    private final CustomRoleRepository customRoleRepository;
    private final CompanyRepository companyRepository;
    private final com.zuhoocms.auth.user.UserRepository userRepository;
    private final PermissionRepository permissionRepository;
    private final RolePermissionRepository rolePermissionRepository;
    private final EmployeeRepository employeeRepository;
    private final SecurityUtil securityUtil;
    private final AuditService auditService;

    @Override
    public CustomRoleResponse create(CustomRoleRequest request) {

        Long companyId = securityUtil.getCurrentCompanyId();

        // Trimmed BEFORE the uniqueness check, because the name is stored trimmed (CustomRoleMapper.toEntity) and was
        // checked untrimmed: " Admin " missed an existing "Admin" here and then hit UNIQUE (company_id, name), so the
        // caller got a generic 409 instead of the clear 400 this very line is trying to give them. @NotBlank means it
        // cannot be null. The microservice already trims first.
        request.setName(request.getName().trim());

        if (customRoleRepository.existsByCompanyIdAndNameIgnoreCase(companyId, request.getName())) {
            throw new BadRequestException("Role already exists.");
        }

        Company company = companyRepository.findById(companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found."));

        CustomRole role = CustomRoleMapper.toEntity(request);
        role.setCompany(company);
        role = customRoleRepository.save(role);
        auditService.log(AuditEntityType.ROLE, role.getId(), AuditAction.CREATE,
                null, role.getName(), securityUtil.getCurrentUser(), companyId, null);
        return CustomRoleMapper.toResponse(role);
    }

    @Override
    public CustomRoleResponse update(Long id, CustomRoleRequest request) {

        Long companyId = securityUtil.getCurrentCompanyId();

        CustomRole role = customRoleRepository.findByIdAndCompanyId(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Role not found."));

        if (Boolean.TRUE.equals(role.getSystemRole())) {
            throw new BadRequestException("System roles cannot be updated.");
        }

        // Same ordering fix as create: trimmed once, then compared and stored, so a rename differing only by
        // whitespace cannot slip past this check into the database constraint.
        request.setName(request.getName().trim());

        if (!role.getName().equalsIgnoreCase(request.getName()) &&
            customRoleRepository.existsByCompanyIdAndNameIgnoreCase(companyId, request.getName())) {
            throw new BadRequestException("A role with that name already exists.");
        }

        role.setName(request.getName());
        role.setDescription(request.getDescription());

        return CustomRoleMapper.toResponse(role);
    }

    @Override
    public void delete(Long id) {

        Long companyId = securityUtil.getCurrentCompanyId();

        CustomRole role = customRoleRepository.findByIdAndCompanyId(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Role not found."));

        if (Boolean.TRUE.equals(role.getSystemRole())) {
            throw new BadRequestException("System roles cannot be deleted.");
        }

        // Blocked while users are assigned: clearCustomRoleForAllUsers() below would silently strip their permissions, so the admin must reassign them first.
        long assignedUsers = userRepository.countByCustomRoleId(role.getId());
        if (assignedUsers > 0) {
            throw new BadRequestException(
                "Cannot delete this role: it is currently assigned to " + assignedUsers
                    + " user(s). Reassign them to a different role first.");
        }

        // Stands in for the CascadeType.SET_NULL that JPA does not have (see User.customRole).
        userRepository.clearCustomRoleForAllUsers(role.getId());
        rolePermissionRepository.deleteByCustomRoleId(role.getId());

        role.softDelete();
        customRoleRepository.save(role);
        auditService.log(AuditEntityType.ROLE, role.getId(), AuditAction.DELETE,
                role.getName(), null, securityUtil.getCurrentUser(), companyId, null);
    }

    @Override
    @Transactional(readOnly = true)
    public List<CustomRoleResponse> getAll() {

        Long companyId = securityUtil.getCurrentCompanyId();

        return customRoleRepository.findByCompanyIdAndActiveTrue(companyId)
                .stream()
                .map(CustomRoleMapper::toResponse)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public CustomRoleResponse getById(Long id) {

        Long companyId = securityUtil.getCurrentCompanyId();

        CustomRole role = customRoleRepository.findByIdAndCompanyId(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Role not found."));

        return CustomRoleMapper.toResponse(role);
    }

    @Override
    @Transactional(readOnly = true)
    public List<String> getPermissions(Long roleId) {
        CustomRole role = findInTenant(roleId);
        return rolePermissionRepository.findByCustomRoleId(role.getId())
                .stream()
                .map(rp -> rp.getPermission().getCode())
                .toList();
    }

    @Override
    public List<String> setPermissions(Long roleId, List<String> permissionCodes) {
        Long companyId = securityUtil.getCurrentCompanyId();
        CustomRole role = findInTenant(roleId);
        if (Boolean.TRUE.equals(role.getSystemRole())) {
            throw new BadRequestException("System roles cannot be modified.");
        }

        List<String> before = getPermissions(roleId);

        // Flush the delete first: Hibernate orders inserts before deletes in one flush, so an overlapping permission set violates the (custom_role_id, permission_id) unique constraint.
        rolePermissionRepository.deleteByCustomRoleId(role.getId());
        rolePermissionRepository.flush();

        List<String> codes = permissionCodes == null ? List.of() : permissionCodes;
        for (String code : codes) {
            Permission permission = permissionRepository.findByCode(code)
                    .orElseThrow(() -> new ResourceNotFoundException("Unknown permission: " + code));
            rolePermissionRepository.save(RolePermission.builder()
                    .customRole(role)
                    .permission(permission)
                    .build());
        }

        List<String> after = getPermissions(roleId);
        // Audited because this can grant a role access to salary or financial data, or anything else in the permission catalog.
        auditService.log(AuditEntityType.ROLE, role.getId(), AuditAction.PERMISSION_CHANGE,
                String.join(",", before), String.join(",", after), securityUtil.getCurrentUser(), companyId, null);

        return after;
    }

    @Override
    public void assignEmployee(Long roleId, Long employeeId) {
        Long companyId = securityUtil.getCurrentCompanyId();
        CustomRole role = findInTenant(roleId);

        Employee employee = employeeRepository.findByIdAndCompanyId(employeeId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Employee not found: " + employeeId));

        User user = employee.getUser();
        if (user == null) {
            throw new BadRequestException("Employee has no linked user account");
        }
        user.setCustomRole(role);
        userRepository.save(user);
    }

    @Override
    public void unassignEmployee(Long employeeId) {
        Long companyId = securityUtil.getCurrentCompanyId();

        Employee employee = employeeRepository.findByIdAndCompanyId(employeeId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Employee not found: " + employeeId));

        User user = employee.getUser();
        if (user == null) {
            throw new BadRequestException("Employee has no linked user account");
        }
        user.setCustomRole(null);
        userRepository.save(user);
    }

    private CustomRole findInTenant(Long roleId) {
        Long companyId = securityUtil.getCurrentCompanyId();
        return customRoleRepository.findByIdAndCompanyId(roleId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Role not found."));
    }
}
