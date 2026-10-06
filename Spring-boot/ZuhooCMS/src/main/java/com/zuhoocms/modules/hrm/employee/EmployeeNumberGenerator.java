package com.zuhoocms.modules.hrm.employee;

/**
 * Generates a unique, per-company, sequential employee number in the form EMP-NNNN (e.g. EMP-0042).
 *
 * <p>Soft-deleted employees keep their number and still occupy the (company_id, employee_number) unique constraint, so they count towards the MAX.
 * Must be called inside the transaction that inserts the employee: the per-company advisory lock is held until that transaction commits.
 */
public final class EmployeeNumberGenerator {

    private static final String PREFIX = "EMP-";

    private EmployeeNumberGenerator() {}

    public static String next(EmployeeRepository employeeRepository, Long companyId) {
        employeeRepository.lockEmployeeNumberSequence(companyId);
        long max = employeeRepository
                .findMaxEmployeeSequenceIncludingDeleted(companyId, PREFIX)
                .orElse(0L);
        return String.format("%s%04d", PREFIX, max + 1);
    }
}
