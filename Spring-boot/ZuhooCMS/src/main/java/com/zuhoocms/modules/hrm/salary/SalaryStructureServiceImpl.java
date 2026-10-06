package com.zuhoocms.modules.hrm.salary;

import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.email.EmailService;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class SalaryStructureServiceImpl implements SalaryStructureService {

    private final SalaryStructureRepository salaryStructureRepository;
    private final EmployeeRepository employeeRepository;
    private final CompanyRepository companyRepository;
    private final SecurityUtil securityUtil;
    private final EmailService emailService;
    private final EmailBranding emailBranding;
    private final AuthorizationService authorizationService;

    @Override
    @Transactional
    public SalaryStructureResponse create(SalaryStructureRequest request) {
        authorizationService.checkPermission(PermissionCode.SALARY_STRUCTURE_CREATE);
        Long companyId = requireCompanyId();
        if (request.getEffectiveFrom() == null) {
            throw new BadRequestException("Effective from date is required");
        }
        // Row lock on the employee: two simultaneous creates otherwise both find the same (or no) active structure and leave two open-ended structures behind.
        Employee employee = salaryStructureRepository.lockEmployee(request.getEmployeeId(), companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Employee not found: " + request.getEmployeeId()));

        List<SalaryStructure> open = salaryStructureRepository
            .findByCompanyIdAndEmployeeIdAndEffectiveToIsNullOrderByEffectiveFromDesc(companyId, employee.getId());
        for (SalaryStructure existing : open) {
            if (!request.getEffectiveFrom().isAfter(existing.getEffectiveFrom())) {
                throw new BadRequestException("The new structure must start after the current one, which starts on "
                    + existing.getEffectiveFrom());
            }
        }
        // Expire current structures the day before the new one starts; more than one open-ended row exists only in legacy data, and all are closed.
        for (SalaryStructure existing : open) {
            existing.setEffectiveTo(request.getEffectiveFrom().minusDays(1));
            salaryStructureRepository.save(existing);
        }

        SalaryStructure s = SalaryStructure.builder()
            .employee(employee)
            .company(companyRef(companyId))
            .effectiveFrom(request.getEffectiveFrom())
            .grossSalary(request.getGrossSalary())
            .basicSalary(request.getBasicSalary())
            .houseRent(orZero(request.getHouseRent()))
            .medicalAllowance(orZero(request.getMedicalAllowance()))
            .transportAllowance(orZero(request.getTransportAllowance()))
            .foodAllowance(orZero(request.getFoodAllowance()))
            .specialAllowance(orZero(request.getSpecialAllowance()))
            .providentFund(orZero(request.getProvidentFund()))
            .taxDeduction(orZero(request.getTaxDeduction()))
            .notes(request.getNotes())
            .approvedBy(securityUtil.getCurrentUser())
            .build();

        salaryStructureRepository.saveAndFlush(s);

        // A future-dated structure must not change the profile yet; the profile follows today's structure, and SalaryStructureActivationScheduler applies it on its start date.
        syncEmployeeToStructureInEffect(employee, companyId);

        // Best-effort notification: re-throwing aborted the @Transactional create, so a failed email silently discarded the saved structure.
        if (employee.getUser() != null) {
            try {
                Company fullCompany = companyRepository.findById(companyId).orElse(null);
                if (fullCompany != null) {
                    EmailBranding.Data branding = emailBranding.from(fullCompany);
                    emailService.sendSalaryRevisionEmail(
                        employee.getUser().getEmail(), employee.getUser().getFirstName(), branding);
                }
            } catch (Exception ex) {
                log.warn("Salary revision email failed for employee {} (structure was still saved): {}",
                    employee.getId(), ex.getMessage());
            }
        }

        return SalaryStructureMapper.toSalaryStructureResponse(s);
    }

    @Override
    @Transactional
    public SalaryStructureResponse update(Long id, SalaryStructureRequest request) {
        authorizationService.checkPermission(PermissionCode.SALARY_STRUCTURE_CREATE);
        Long companyId = requireCompanyId();
        SalaryStructure s = findInTenant(id);

        // Only the active structure may be edited; superseded ones are locked to preserve payroll history.
        if (s.getEffectiveTo() != null) {
            throw new BadRequestException(
                "Only the current salary structure can be edited. Create a new one to supersede this.");
        }
        if (request.getEffectiveFrom() == null) {
            throw new BadRequestException("Effective from date is required");
        }
        Long employeeId = s.getEmployee().getId();
        Employee employee = salaryStructureRepository.lockEmployee(employeeId, companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Employee not found: " + employeeId));

        // Moving effectiveFrom keeps ranges contiguous: the predecessor is re-closed the day before the new start, which may not reach back to its own start or the range inverts.
        if (!request.getEffectiveFrom().equals(s.getEffectiveFrom())) {
            SalaryStructure predecessor = salaryStructureRepository
                .findByCompanyIdAndEmployeeIdOrderByEffectiveFromDesc(companyId, employeeId).stream()
                .filter(other -> !other.getId().equals(s.getId()))
                .filter(other -> other.getEffectiveTo() != null)
                .findFirst().orElse(null);
            if (predecessor != null) {
                if (!request.getEffectiveFrom().isAfter(predecessor.getEffectiveFrom())) {
                    throw new BadRequestException("Effective from must be after the previous structure's start ("
                        + predecessor.getEffectiveFrom() + ")");
                }
                predecessor.setEffectiveTo(request.getEffectiveFrom().minusDays(1));
                salaryStructureRepository.save(predecessor);
            }
        }

        s.setEffectiveFrom(request.getEffectiveFrom());
        s.setGrossSalary(request.getGrossSalary());
        s.setBasicSalary(request.getBasicSalary());
        s.setHouseRent(orZero(request.getHouseRent()));
        s.setMedicalAllowance(orZero(request.getMedicalAllowance()));
        s.setTransportAllowance(orZero(request.getTransportAllowance()));
        s.setFoodAllowance(orZero(request.getFoodAllowance()));
        s.setSpecialAllowance(orZero(request.getSpecialAllowance()));
        s.setProvidentFund(orZero(request.getProvidentFund()));
        s.setTaxDeduction(orZero(request.getTaxDeduction()));
        s.setNotes(request.getNotes());
        salaryStructureRepository.saveAndFlush(s);

        // Syncs the employee's denormalized salary fields with the structure in effect today, not necessarily this one if it is future-dated.
        syncEmployeeToStructureInEffect(employee, companyId);

        return SalaryStructureMapper.toSalaryStructureResponse(s);
    }

    @Override
    @Transactional(readOnly = true)
    public SalaryStructureResponse getById(Long id) {
        authorizationService.checkPermission(PermissionCode.SALARY_STRUCTURE_VIEW);
        return SalaryStructureMapper.toSalaryStructureResponse(findInTenant(id));
    }

    @Override
    @Transactional(readOnly = true)
    public SalaryStructureResponse getActiveForEmployee(Long employeeId) {
        requireViewOrOwn(employeeId);
        Long companyId = requireCompanyId();
        // The structure in effect today; if only a future-dated one exists so far, that one.
        SalaryStructure s = salaryStructureRepository
            .findInEffectForEmployeeOnDate(companyId, employeeId, LocalDate.now()).stream().findFirst()
            .or(() -> salaryStructureRepository
                .findByCompanyIdAndEmployeeIdAndEffectiveToIsNullOrderByEffectiveFromDesc(companyId, employeeId)
                .stream().findFirst())
            .orElseThrow(() -> new ResourceNotFoundException("No active salary structure for employee: " + employeeId));
        return SalaryStructureMapper.toSalaryStructureResponse(s);
    }

    /** These per-employee lookups had no permission check, so any colleague could read anyone's salary by employeeId; viewing your own still needs none, as for payslips and attendance. */
    private void requireViewOrOwn(Long employeeId) {
        if (authorizationService.hasPermission(PermissionCode.SALARY_STRUCTURE_VIEW)) {
            return;
        }
        var currentUser = securityUtil.getCurrentUser();
        Employee me = currentUser != null ? employeeRepository.findByUserId(currentUser.getId()).orElse(null) : null;
        if (me == null || employeeId == null || !me.getId().equals(employeeId)) {
            throw new com.zuhoocms.shared.exception.ForbiddenException(
                    "Access denied: you can only view your own salary structure");
        }
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SalaryStructureResponse> listAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.SALARY_STRUCTURE_VIEW);
        return salaryStructureRepository.findAllInCompany(requireCompanyId(), pageable)
            .map(SalaryStructureMapper::toSalaryStructureResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SalaryStructureResponse> listForEmployee(Long employeeId, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.SALARY_STRUCTURE_VIEW);
        return salaryStructureRepository.findByCompanyIdAndEmployeeId(requireCompanyId(), employeeId, pageable)
            .map(SalaryStructureMapper::toSalaryStructureResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<SalaryStructureResponse> historyForEmployee(Long employeeId) {
        requireViewOrOwn(employeeId);
        return salaryStructureRepository
            .findByCompanyIdAndEmployeeIdOrderByEffectiveFromDesc(requireCompanyId(), employeeId)
            .stream().map(SalaryStructureMapper::toSalaryStructureResponse).toList();
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.SALARY_STRUCTURE_DELETE);
        SalaryStructure s = findInTenant(id);
        if (s.getEffectiveTo() == null) {
            throw new BadRequestException("Cannot delete the currently active salary structure. Supersede it by creating a new one.");
        }
        s.softDelete();
    }

    @Override
    @Transactional
    public int applyDueStructures() {
        int applied = 0;
        for (SalaryStructure s : salaryStructureRepository.findDueNotYetApplied(LocalDate.now())) {
            applyToEmployee(s.getEmployee(), s);
            applied++;
        }
        if (applied > 0) log.info("Applied {} salary structure(s) whose effective date has arrived", applied);
        return applied;
    }

    /** Copies the structure in effect today (if any) onto the employee profile; leaves the profile unchanged otherwise. */
    private void syncEmployeeToStructureInEffect(Employee employee, Long companyId) {
        salaryStructureRepository.findInEffectForEmployeeOnDate(companyId, employee.getId(), LocalDate.now())
            .stream().findFirst()
            .ifPresent(current -> applyToEmployee(employee, current));
    }

    private void applyToEmployee(Employee employee, SalaryStructure s) {
        employee.setBasicSalary(s.getBasicSalary());
        employee.setHouseRent(orZero(s.getHouseRent()));
        employee.setMedicalAllowance(orZero(s.getMedicalAllowance()));
        employee.setTransportAllowance(orZero(s.getTransportAllowance()));
        employee.setSalaryStructure(s);
        employeeRepository.save(employee);
    }

    private SalaryStructure findInTenant(Long id) {
        return salaryStructureRepository.findByIdAndCompanyId(id, requireCompanyId())
            .orElseThrow(() -> new ResourceNotFoundException("Salary structure not found: " + id));
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    private Company companyRef(Long companyId) {
        Company c = new Company(); c.setId(companyId); return c;
    }

    private BigDecimal orZero(BigDecimal v) {
        return v != null ? v : BigDecimal.ZERO;
    }
}
