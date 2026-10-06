package com.zuhoocms.modules.hrm.recruitment.offerletter;

import com.zuhoocms.modules.hrm.employee.Employee;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;

/**
 * Employee lookup for the letters module only, departed (soft-deleted) employees included.
 *
 * <p>Native SQL for the same reason as {@code ItamEmployeeGuard}: {@code BaseEntity}'s
 * {@code @SQLRestriction("deleted = false")} hides an employee soft-deleted by {@code DELETE /api/employees/{id}}
 * from every repository lookup, so {@code /api/hr/letters} 404'd for exactly the people HR issues EXPERIENCE,
 * relieving and NOC letters to. It also bypasses the tenant filter, hence the explicit company_id - this must never
 * reach across companies.
 *
 * <p>Deliberately confined to this package and used only by the letters service: nothing else should start seeing
 * departed employees, so the employee list, the pickers and every other module keep their own filtered lookups.
 *
 * <p>The row comes back as a managed {@code Employee}, so the letter prompt keeps reading designation, department,
 * hire date and job title as before. The employee's own {@code user} row is soft-deleted alongside the employee, so
 * callers still resolve names and addresses through {@code EmployeeUserResolver} rather than {@code getUser()}.
 */
@Component
class LetterEmployeeLookup {

    @PersistenceContext
    private EntityManager em;

    /** The employee in this company whether or not they have departed; empty when no such row exists. */
    @SuppressWarnings("unchecked")
    Optional<Employee> findIncludingDeparted(Long employeeId, Long companyId) {
        if (employeeId == null || companyId == null) return Optional.empty();
        List<Employee> rows = em.createNativeQuery(
                        "SELECT e.* FROM employees e WHERE e.id = ?1 AND e.company_id = ?2", Employee.class)
                .setParameter(1, employeeId)
                .setParameter(2, companyId)
                .getResultList();
        return rows.isEmpty() ? Optional.empty() : Optional.of(rows.get(0));
    }
}
