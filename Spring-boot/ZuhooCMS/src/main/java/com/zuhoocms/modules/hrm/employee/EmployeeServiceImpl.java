package com.zuhoocms.modules.hrm.employee;

import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.hrm.department.Department;
import com.zuhoocms.modules.hrm.designation.Designation;
import com.zuhoocms.modules.hrm.attendance.shift.Shift;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.enums.EmploymentStatus;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.hrm.department.DepartmentRepository;
import com.zuhoocms.modules.hrm.designation.DesignationRepository;
import com.zuhoocms.modules.hrm.attendance.shift.ShiftRepository;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.email.EmailService;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.notification.NotificationPreferenceService;
import com.zuhoocms.shared.notification.NotificationService;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.extern.slf4j.Slf4j;

@Slf4j
@Service
@RequiredArgsConstructor
public class EmployeeServiceImpl implements EmployeeService {

    private final EmployeeRepository employeeRepository;
    private final UserRepository userRepository;
    private final CompanyRepository companyRepository;
    private final DepartmentRepository departmentRepository;
    private final DesignationRepository designationRepository;
    private final ShiftRepository shiftRepository;
    private final PasswordEncoder passwordEncoder;
    private final EmailService emailService;
    private final EmailBranding emailBranding;
    private final NotificationPreferenceService notificationPreferenceService;
    private final NotificationService notificationService;
    private final EmployeeMapper employeeMapper;
    private final com.zuhoocms.shared.address.AddressMapper addressMapper;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final com.zuhoocms.modules.itam.offboarding.OffboardingChecklistService offboardingChecklistService;
    private final EmployeeUserResolver userResolver;
    private final com.zuhoocms.auth.token.TokenRepository tokenRepository;

    private Long requireCompanyId() {
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null)
            throw new BadRequestException("No company context found in security context.");
        return companyId;
    }

    private Company findCompanyById(Long companyId) {
        return companyRepository.findById(companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found with id: " + companyId));
    }

    private Employee findEmployeeById(Long id) {
        Long companyId = requireCompanyId();
        return employeeRepository.findByIdAndCompanyId(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Employee not found with id: " + id));
    }

    /**
     * Backs getMyProfile/updateMyProfile, which return and mutate this row wholesale (nationalId, taxId,
     * emergency contacts, salary fields). Scoped to the active company: findByUserId alone served, and let the
     * caller overwrite, an employee record belonging to a different tenant.
     */
    private Employee findCurrentEmployee() {
        User user = securityUtil.getCurrentUser();
        return employeeRepository.findByUserIdAndCompanyId(user.getId(), requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Employee profile not found."));
    }

    private void validateEmployeeCreation(CreateEmployeeRequest request) {
        String normalizedEmail = request.getEmail().toLowerCase().trim();
        if (userRepository.existsByEmail(normalizedEmail))
            throw new BadRequestException("An account with this email already exists.");
    }

    private void validateNotSelfManager(Long employeeId, Long managerId) {
        if (managerId.equals(employeeId))
            throw new BadRequestException("An employee cannot be their own reporting manager.");
    }

    private User createPortalUser(CreateEmployeeRequest request) {
        User user = User.builder()
                .firstName(request.getFirstName())
                .lastName(request.getLastName())
                .email(request.getEmail().toLowerCase().trim())
                .password(passwordEncoder.encode(request.getPassword()))
                .role(Role.EMPLOYEE)
                .active(true)
                .emailVerified(true)
                .image(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getProfileImageUrl()))
                .build();
        userRepository.save(user);

        return user;
    }

    private Employee buildEmployee(CreateEmployeeRequest request, User user, Company company) {
        return Employee.builder()
                .user(user)
                .company(company)
                .employeeNumber(EmployeeNumberGenerator.next(employeeRepository, company.getId()))
                .officialEmail(request.getOfficialEmail())
                .workPhone(request.getWorkPhone())
                .profileImageUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getProfileImageUrl()))
                .nationalId(request.getNationalId())
                .taxId(request.getTaxId())
                .costCenter(request.getCostCenter())
                .officeLocation(request.getOfficeLocation())
                .jobTitle(request.getJobTitle())
                .employmentType(request.getEmploymentType())
                .employmentStatus(request.getEmploymentStatus() != null
                        ? request.getEmploymentStatus()
                        : EmploymentStatus.PROBATION)
                .gender(request.getGender())
                .dateOfBirth(request.getDateOfBirth())
                .fatherName(request.getFatherName())
                .motherName(request.getMotherName())
                .location(addressMapper.toEntity(request.getLocation()))
                .hireDate(request.getHireDate())
                .confirmationDate(request.getConfirmationDate())
                .probationEndDate(request.getProbationEndDate())
                .contractEndDate(request.getContractEndDate())
                .basicSalary(request.getBasicSalary())
                .houseRent(request.getHouseRent())
                .medicalAllowance(request.getMedicalAllowance())
                .transportAllowance(request.getTransportAllowance())
                .billableRate(request.getBillableRate())
                .bankName(request.getBankName())
                .bankAccountNumber(request.getBankAccountNumber())
                .bankRoutingNumber(request.getBankRoutingNumber())
                .emergencyContactName(request.getEmergencyContactName())
                .emergencyContactPhone(request.getEmergencyContactPhone())
                .emergencyContactRelation(request.getEmergencyContactRelation())
                .build();
    }

    private void assignEmployeeRelationships(Employee employee, CreateEmployeeRequest request, Long companyId) {
        if (request.getDepartmentId() != null)
            employee.setDepartment(findDepartmentById(request.getDepartmentId(), companyId));
        if (request.getDesignationId() != null)
            employee.setDesignation(findDesignationById(request.getDesignationId(), companyId));
        if (request.getReportingManagerId() != null)
            employee.setReportingManager(findReportingManagerById(request.getReportingManagerId(), companyId));
        if (request.getShiftId() != null)
            employee.setShift(findShiftById(request.getShiftId(), companyId));
    }

    private void sendWelcomeEmail(User user, Company company) {
        try {
            EmailBranding.Data branding = emailBranding.from(company);
            emailService.sendEmployeeWelcomeEmail(user.getEmail(), user.getFirstName(), branding);
        } catch (Exception ex) {
            // Email failure must not fail employee creation.
            log.error("Welcome email failed for platformuser {}: {}", user.getEmail(), ex.getMessage());
        }
    }

    private void updateEmployeeDetails(Employee emp, UpdateEmployeeRequest request) {
        if (request.getJobTitle() != null)
            emp.setJobTitle(request.getJobTitle());
        if (request.getEmploymentType() != null)
            emp.setEmploymentType(request.getEmploymentType());
        if (request.getEmploymentStatus() != null) {
            emp.setEmploymentStatus(request.getEmploymentStatus());
            // active drives payroll eligibility (findByCompanyIdAndActiveTrue) and headcount independently of employmentStatus; a terminal status set here otherwise left someone fully paid.
            // The login is deactivated, never soft-deleted: the employee row stays visible, and a soft-deleted user behind it fails every later list/detail/edit/delete.
            if (isTerminalStatus(request.getEmploymentStatus())) {
                emp.setActive(false);
                deactivatePortalUser(emp);
            }
        }
        if (request.getGender() != null)
            emp.setGender(request.getGender());
        if (request.getDateOfBirth() != null)
            emp.setDateOfBirth(request.getDateOfBirth());
        if (request.getFatherName() != null)
            emp.setFatherName(request.getFatherName());
        if (request.getMotherName() != null)
            emp.setMotherName(request.getMotherName());
        if (request.getLocation() != null) {
            if (emp.getLocation() == null) {
                emp.setLocation(addressMapper.toEntity(request.getLocation()));
            } else {
                addressMapper.updateEntityFromRequest(emp.getLocation(), request.getLocation());
            }
        }
        if (request.getHireDate() != null)
            emp.setHireDate(request.getHireDate());
        if (request.getConfirmationDate() != null)
            emp.setConfirmationDate(request.getConfirmationDate());
        if (request.getProbationEndDate() != null)
            emp.setProbationEndDate(request.getProbationEndDate());
        if (request.getContractEndDate() != null) {
            emp.setContractEndDate(request.getContractEndDate());
            emp.setContractEndReminderSentAt(null);
        }
        if (request.getBasicSalary() != null)
            emp.setBasicSalary(request.getBasicSalary());
        if (request.getHouseRent() != null)
            emp.setHouseRent(request.getHouseRent());
        if (request.getMedicalAllowance() != null)
            emp.setMedicalAllowance(request.getMedicalAllowance());
        if (request.getTransportAllowance() != null)
            emp.setTransportAllowance(request.getTransportAllowance());
        if (request.getBillableRate() != null)
            emp.setBillableRate(request.getBillableRate());
        if (request.getBankName() != null)
            emp.setBankName(request.getBankName());
        if (request.getBankAccountNumber() != null)
            emp.setBankAccountNumber(request.getBankAccountNumber());
        if (request.getBankRoutingNumber() != null)
            emp.setBankRoutingNumber(request.getBankRoutingNumber());
        if (request.getEmergencyContactName() != null)
            emp.setEmergencyContactName(request.getEmergencyContactName());
        if (request.getEmergencyContactPhone() != null)
            emp.setEmergencyContactPhone(request.getEmergencyContactPhone());
        if (request.getEmergencyContactRelation() != null)
            emp.setEmergencyContactRelation(request.getEmergencyContactRelation());
        if (request.getNationalId() != null)
            emp.setNationalId(request.getNationalId());
        if (request.getTaxId() != null)
            emp.setTaxId(request.getTaxId());
        if (request.getCostCenter() != null)
            emp.setCostCenter(request.getCostCenter());
        if (request.getOfficeLocation() != null)
            emp.setOfficeLocation(request.getOfficeLocation());
        if (request.getWorkPhone() != null)
            emp.setWorkPhone(request.getWorkPhone());
        if (request.getOfficialEmail() != null)
            emp.setOfficialEmail(request.getOfficialEmail());
        if (request.getProfileImageUrl() != null) {
            emp.setProfileImageUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getProfileImageUrl(), emp.getProfileImageUrl()));
            User user = userResolver.liveUser(emp);
            if (user != null) {
                user.setImage(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getProfileImageUrl(), user.getImage()));
            }
        }
        if (request.getLocation() != null) {
            if (emp.getLocation() == null) {
                emp.setLocation(addressMapper.toEntity(request.getLocation()));
            } else {
                addressMapper.updateEntityFromRequest(emp.getLocation(), request.getLocation());
            }
        }
    }

    private void updateEmployeeRelationships(Employee emp, UpdateEmployeeRequest request, Long companyId) {
        if (request.getDepartmentId() != null)
            emp.setDepartment(findDepartmentById(request.getDepartmentId(), companyId));
        if (request.getDesignationId() != null)
            emp.setDesignation(findDesignationById(request.getDesignationId(), companyId));
        if (request.getReportingManagerId() != null) {
            validateNotSelfManager(emp.getId(), request.getReportingManagerId());
            emp.setReportingManager(findReportingManagerById(request.getReportingManagerId(), companyId));
        }
        if (request.getShiftId() != null)
            emp.setShift(findShiftById(request.getShiftId(), companyId));
    }

    /** RESIGNED/TERMINATED/RETIRED/SUSPENDED all mean "not currently working here" for payroll/portal purposes. */
    private boolean isTerminalStatus(EmploymentStatus status) {
        return status == EmploymentStatus.RESIGNED || status == EmploymentStatus.TERMINATED
                || status == EmploymentStatus.RETIRED || status == EmploymentStatus.SUSPENDED;
    }

    /** Edit-form departure/suspension: login switched off (active=false, honoured by isEnabled()/login/refresh) and refresh tokens revoked, but NOT soft-deleted, so the user stays loadable. */
    private void deactivatePortalUser(Employee emp) {
        Long userId = userResolver.userId(emp);
        if (userId == null)
            return;
        User user = userResolver.liveUser(emp);
        if (user != null) {
            user.setActive(false);
            userRepository.save(user);
        }
        tokenRepository.revokeAllByUserIdAndType(userId, com.zuhoocms.auth.token.TokenType.REFRESH);
    }

    /** SUSPENDED -> ACTIVE from the edit form: employee and login are active again. */
    private void reactivatePortalUser(Employee emp, Long companyId) {
        emp.setActive(true);
        if (userResolver.userId(emp) == null)
            return;
        User user = userResolver.liveUser(emp);
        if (user != null) {
            user.setActive(true);
            userRepository.save(user);
        } else {
            // Suspended under the old code, which soft-deleted the login - restore it.
            userResolver.restoreUser(emp.getId(), companyId);
        }
    }

    /** DELETE/terminate, unlike the edit-form path: the login is deactivated and soft-deleted. */
    private void removePortalUser(Employee emp) {
        User user = userResolver.liveUser(emp);
        if (user == null)
            return; // none, or already soft-deleted
        user.setActive(false);
        user.softDelete();
        userRepository.save(user);
    }

    private Department findDepartmentById(Long departmentId, Long companyId) {
        return departmentRepository.findByIdAndCompanyId(departmentId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Department not found with id: " + departmentId));
    }

    private Designation findDesignationById(Long designationId, Long companyId) {
        return designationRepository.findByIdAndCompanyId(designationId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Designation not found with id: " + designationId));
    }

    private Shift findShiftById(Long shiftId, Long companyId) {
        return shiftRepository.findByIdAndCompanyId(shiftId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Shift not found with id: " + shiftId));
    }

    private Employee findReportingManagerById(Long managerId, Long companyId) {
        return employeeRepository.findByIdAndCompanyId(managerId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Reporting manager not found with id: " + managerId));
    }

    @Override
    @Transactional
    public EmployeeResponse create(CreateEmployeeRequest request) {
        authorizationService.checkPermission(PermissionCode.EMPLOYEE_CREATE);

        Long companyId = requireCompanyId();
        validateEmployeeCreation(request);
        Company company = findCompanyById(companyId);
        User user = createPortalUser(request);
        Employee employee = buildEmployee(request, user, company);
        assignEmployeeRelationships(employee, request, companyId);
        employeeRepository.save(employee);
        notificationPreferenceService.createDefaultsForUser(user.getId());
        sendWelcomeEmail(user, company);

        return employeeMapper.toDTO(employee);
    }

    /**
     * Withholds pay and bank details from a caller who may not see the workforce.
     *
     * <p>create, update and delete on this service each check their EMPLOYEE_* code; the reads checked nothing at
     * all, and EMPLOYEE_VIEW existed in the enum without ever being used here. So any employee of the company could
     * list every colleague and read their basic salary, bank name, account number and routing number. Confirmed on a
     * device with a role holding only the four OFFBOARDING_* codes.
     *
     * <p>Redacted rather than refused, because the list is what every person-picker in both clients is built on -
     * offboarding, manual attendance, leave approval, asset assignment. Gating it outright would take those away from
     * the roles that legitimately need to choose a colleague. Names stay visible; pay does not. This is the same
     * shape as the company bank details on CompanyController.me.
     *
     * <p>Your own record is never redacted: an employee may always see their own pay.
     */
    private EmployeeResponse withheldIfNotPermitted(EmployeeResponse dto, Long currentUserId) {
        if (dto == null || authorizationService.hasPermission(PermissionCode.EMPLOYEE_VIEW)) {
            return dto;
        }
        if (currentUserId != null && currentUserId.equals(dto.getUserId())) {
            return dto;
        }
        // The same set the microservice withholds, which got this right from the start: pay, bank, national ID and
        // tax ID. The pay components matter as much as basicSalary - house rent and the allowances reconstruct most
        // of a salary between them - and a national ID is identity data that no colleague needs to pick a name from
        // a list.
        dto.setBasicSalary(null);
        dto.setHouseRent(null);
        dto.setMedicalAllowance(null);
        dto.setTransportAllowance(null);
        dto.setBankName(null);
        dto.setBankAccountNumber(null);
        dto.setBankRoutingNumber(null);
        dto.setNationalId(null);
        dto.setTaxId(null);
        return dto;
    }

    /** The caller's own user id, or null when there is no authenticated user. */
    private Long currentUserIdOrNull() {
        User current = securityUtil.getCurrentUser();
        return current != null ? current.getId() : null;
    }

    @Override
    @Transactional(readOnly = true)
    public EmployeeResponse getById(Long id) {

        return withheldIfNotPermitted(employeeMapper.toDTO(findEmployeeById(id)), currentUserIdOrNull());
    }

    @Override
    @Transactional(readOnly = true)
    public EmployeeResponse getMyProfile() {

        return employeeMapper.toDTO(findCurrentEmployee());
    }

    @Override
    @Transactional
    public EmployeeResponse updateMyProfile(SelfUpdateEmployeeRequest request) {
        Employee emp = findCurrentEmployee();

        if (request.getWorkPhone() != null)
            emp.setWorkPhone(request.getWorkPhone());
        if (request.getPhone() != null) {
            User user = emp.getUser();
            if (user != null) {
                user.setPhone(request.getPhone());
            }
        }
        if (request.getGender() != null)
            emp.setGender(request.getGender());
        if (request.getFatherName() != null)
            emp.setFatherName(request.getFatherName());
        if (request.getMotherName() != null)
            emp.setMotherName(request.getMotherName());
        if (request.getNationalId() != null)
            emp.setNationalId(request.getNationalId());
        if (request.getTaxId() != null)
            emp.setTaxId(request.getTaxId());
        if (request.getEmergencyContactName() != null)
            emp.setEmergencyContactName(request.getEmergencyContactName());
        if (request.getEmergencyContactPhone() != null)
            emp.setEmergencyContactPhone(request.getEmergencyContactPhone());
        if (request.getEmergencyContactRelation() != null)
            emp.setEmergencyContactRelation(request.getEmergencyContactRelation());
        if (request.getLocation() != null) {
            if (emp.getLocation() == null) {
                emp.setLocation(addressMapper.toEntity(request.getLocation()));
            } else {
                addressMapper.updateEntityFromRequest(emp.getLocation(), request.getLocation());
            }
        }
        if (request.getProfileImageUrl() != null) {
            emp.setProfileImageUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getProfileImageUrl(), emp.getProfileImageUrl()));
            User user = emp.getUser();
            if (user != null) {
                user.setImage(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getProfileImageUrl(), user.getImage()));
            }
        }

        employeeRepository.save(emp);
        return employeeMapper.toDTO(emp);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<EmployeeResponse> listAll(Long departmentId, EmploymentStatus status, String search, boolean excludeOwner, Pageable pageable) {
        Long companyId = requireCompanyId();

        Long ownerUserId = null;
        if (excludeOwner) {
            try {
                Company company = findCompanyById(companyId);
                if (company != null && company.getOwner() != null) {
                    ownerUserId = company.getOwner().getId();
                }
            } catch (Exception ignored) {
                ownerUserId = null;
            }
        }

        boolean hasSearch = search != null && !search.trim().isEmpty();
        boolean hasStatus = status != null;
        boolean hasDept = departmentId != null;

        if (!hasSearch) {
            Page<Employee> page;
            if (hasDept && hasStatus) {
                page = employeeRepository.findByCompanyIdAndDepartmentIdAndEmploymentStatusExcludingOwner(companyId, departmentId, status, ownerUserId, pageable);
            } else if (hasDept) {
                page = employeeRepository.findByCompanyIdAndDepartmentIdExcludingOwner(companyId, departmentId, ownerUserId, pageable);
            } else if (hasStatus) {
                page = employeeRepository.findByCompanyIdAndEmploymentStatusExcludingOwner(companyId, status, ownerUserId, pageable);
            } else {
                page = employeeRepository.findByCompanyIdExcludingOwner(companyId, ownerUserId, pageable);
            }
            final Long meId = currentUserIdOrNull();
            return page.map(e -> withheldIfNotPermitted(employeeMapper.toDTO(e), meId));
        }

        String searchKeyword = search.trim();
        Page<Employee> page;
        if (hasStatus) {
            page = employeeRepository.searchEmployeesWithStatus(
                    companyId, departmentId, status, ownerUserId, searchKeyword, pageable);
        } else {
            page = employeeRepository.searchEmployeesWithoutStatus(
                    companyId, departmentId, ownerUserId, searchKeyword, pageable);
        }
        final Long meId2 = currentUserIdOrNull();
        return page.map(e -> withheldIfNotPermitted(employeeMapper.toDTO(e), meId2));
    }

    @Override
    @Transactional
    public EmployeeResponse update(Long id, UpdateEmployeeRequest request) {
        authorizationService.checkPermission(PermissionCode.EMPLOYEE_UPDATE);

        Long companyId = requireCompanyId();
        Employee emp = findEmployeeById(id);
        EmploymentStatus previousStatus = emp.getEmploymentStatus();
        updateEmployeeDetails(emp, request);
        updateEmployeeRelationships(emp, request, companyId);
        if (previousStatus == EmploymentStatus.SUSPENDED && emp.getEmploymentStatus() == EmploymentStatus.ACTIVE) {
            reactivatePortalUser(emp, companyId);
        }
        employeeRepository.save(emp);

        if (emp.getEmploymentStatus() != previousStatus) {
            startOffboardingIfDeparted(emp, companyId);
        }

        return employeeMapper.toDTO(emp);
    }

    /**
     * A departure recorded from the edit form gets the same offboarding checklist and OFFBOARDING_CREATED notification as terminate(), in the same transaction.
     * createForTermination is idempotent under the employee row lock, so a later DELETE or re-save never creates a second checklist; assets and licence seats are deliberately not released.
     */
    private void startOffboardingIfDeparted(Employee emp, Long companyId) {
        EmploymentStatus status = emp.getEmploymentStatus();
        if (status == EmploymentStatus.TERMINATED || status == EmploymentStatus.RESIGNED) {
            offboardingChecklistService.createForTermination(emp.getId(), companyId);
        }
    }

    @Override
    @Transactional
    public void terminate(Long id) {
        authorizationService.checkPermission(PermissionCode.EMPLOYEE_DELETE);

        Employee emp = findEmployeeById(id);
        emp.setActive(false);
        emp.setEmploymentStatus(EmploymentStatus.TERMINATED);
        emp.softDelete();
        // Resolved before the user is soft-deleted, and tolerant of one already soft-deleted (read via company-scoped native SQL).
        Long companyId = requireCompanyId();
        User liveUser = userResolver.liveUser(emp);
        EmployeeUserResolver.UserSnapshot legacyUser = liveUser == null && emp.getUser() != null
                ? userResolver.snapshot(emp.getId(), companyId) : null;
        String userEmail = liveUser != null ? liveUser.getEmail() : legacyUser != null ? legacyUser.email() : null;
        String userFirstName = liveUser != null ? liveUser.getFirstName() : legacyUser != null ? legacyUser.firstName() : null;
        String fullName = userResolver.fullName(emp);
        removePortalUser(emp);

        // Same transaction: a terminated employee always has an offboarding checklist; assets and licence seats are NOT released here, the checklist tracks collecting them.
        startOffboardingIfDeparted(emp, companyId);

        if (userEmail != null) {
            try {
                EmailBranding.Data branding = emailBranding.from(emp.getCompany());
                emailService.sendTerminationEmail(userEmail, userFirstName, branding);
            } catch (Exception ex) {
                // Best-effort: a failed email must not roll back the termination.
                log.warn("Termination email failed for employee {} (termination still saved): {}",
                        emp.getId(), ex.getMessage());
            }
        }

        // Notify the reporting manager to collect assets and reassign work; previously only the terminated employee was told.
        // A soft-deleted manager (or manager's login) would throw here, so it falls back to the owner, as with no manager.
        Employee manager = userResolver.loadable(emp.getReportingManager());
        User recipient = manager != null ? userResolver.liveUser(manager) : null;
        if (recipient == null) recipient = emp.getCompany().getOwner();
        if (recipient != null) {
            notificationService.send(CreateNotificationRequest.of(
                    com.zuhoocms.enums.NotificationType.EMPLOYEE_TERMINATED,
                    "Employee terminated",
                    fullName + " has been terminated - reassign their work and confirm asset return.",
                    "/hrm/employees/" + emp.getId(),
                    recipient.getId(),
                    emp.getCompany().getId()));
        }
    }

    @Override
    @Transactional(readOnly = true)
    public long getEmployeeCount() {
        // Active only, matching HrDashboardServiceImpl's headcount: countByCompanyId included resigned/deactivated staff, so the two figures disagreed.
        return employeeRepository.countByCompanyIdAndActiveTrue(requireCompanyId());
    }

    @Override
    @Transactional(readOnly = true)
    public boolean isEmployee(Long userId) {
        return employeeRepository.existsByUserIdAndCompanyId(userId, requireCompanyId());
    }
}
