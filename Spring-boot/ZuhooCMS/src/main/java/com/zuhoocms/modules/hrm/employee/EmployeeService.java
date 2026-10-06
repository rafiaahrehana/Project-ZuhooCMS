package com.zuhoocms.modules.hrm.employee;

import com.zuhoocms.enums.EmploymentStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

public interface EmployeeService {

    /** ADMIN / OWNER: onboard a new employee — creates User + Employee in one transaction */
    EmployeeResponse create(CreateEmployeeRequest request);

    /** ADMIN / OWNER: get full employee details by id */
    EmployeeResponse getById(Long id);

    /** EMPLOYEE: get own profile */
    EmployeeResponse getMyProfile();

    /** EMPLOYEE: self-edit a narrow subset of own profile fields - see SelfUpdateEmployeeRequest */
    EmployeeResponse updateMyProfile(SelfUpdateEmployeeRequest request);

    /**
     * ADMIN / OWNER: list all employees, optionally filtered by department, status, or search term.
     * excludeOwner=true drops the owner's auto-created Employee record (the Employees admin page); other callers pass false to keep including them.
     */
    Page<EmployeeResponse> listAll(Long departmentId, EmploymentStatus status, String search, boolean excludeOwner, Pageable pageable);

    default Page<EmployeeResponse> listAll(Long departmentId, boolean excludeOwner, Pageable pageable) {
        return listAll(departmentId, null, null, excludeOwner, pageable);
    }

    /** ADMIN / OWNER: update employee profile fields and relationships */
    EmployeeResponse update(Long id, UpdateEmployeeRequest request);

    /** ADMIN / OWNER: terminate employment — sets requeststatus TERMINATED and soft-deletes platformuser */
    void terminate(Long id);

    /** ADMIN / OWNER: get total number of employees for the current company */
    /** Active headcount for the caller's company - the same figure the HR dashboard shows; resigned/deactivated staff are excluded. */
    long getEmployeeCount();

    /** Checks if a platformuser is an employee of the current company */
    boolean isEmployee(Long userId);
}
