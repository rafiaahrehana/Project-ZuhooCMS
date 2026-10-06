package com.zuhoocms.modules.itam.shared;

import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.springframework.stereotype.Component;

import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Employee lookups shared by ITAM (licence seats, offboarding, hardware/import).
 *
 * <p>Native SQL on purpose: {@code @SQLRestriction("deleted = false")} hides terminated employees from repository lookups and throws {@code EntityNotFoundException} on a lazy proxy - exactly the employees offboarding exists for. It also bypasses the tenant filter, hence the explicit company_id.
 *
 * <p>{@link #lock} serialises "what does this employee hold", so the "no open offboarding" / "nothing still assigned" checks cannot race the writes they guard. {@code FOR NO KEY UPDATE} does not block the {@code FOR KEY SHARE} that unrelated FK inserts (attendance, leave) take.
 */
@Component
public class ItamEmployeeGuard {

    private static final Set<String> TERMINAL_STATUSES = Set.of("RESIGNED", "TERMINATED", "RETIRED");

    @PersistenceContext
    private EntityManager em;

    /** Row-locks the employee (terminated/soft-deleted rows included) for the rest of the transaction. */
    public boolean lock(Long employeeId, Long companyId) {
        if (employeeId == null || companyId == null) return false;
        List<?> rows = em.createNativeQuery(
                        "SELECT id FROM employees WHERE id = ?1 AND company_id = ?2 FOR NO KEY UPDATE")
                .setParameter(1, employeeId)
                .setParameter(2, companyId)
                .getResultList();
        return !rows.isEmpty();
    }

    /** Locks the employee and verifies they may receive an asset or seat: exists in the company (404), active (400), no open offboarding checklist (400). */
    public void requireAssignable(Long employeeId, Long companyId) {
        if (!lock(employeeId, companyId)) {
            throw new ResourceNotFoundException("Employee not found: " + employeeId);
        }
        Object[] row = (Object[]) em.createNativeQuery(
                        "SELECT active, deleted, employment_status FROM employees WHERE id = ?1 AND company_id = ?2")
                .setParameter(1, employeeId)
                .setParameter(2, companyId)
                .getSingleResult();
        boolean active = Boolean.TRUE.equals(row[0]);
        boolean deleted = Boolean.TRUE.equals(row[1]);
        String status = row[2] != null ? row[2].toString() : null;
        if (!active || deleted || (status != null && TERMINAL_STATUSES.contains(status))) {
            throw new BadRequestException("Employee is not active and cannot be assigned assets or licences");
        }
        if (hasOpenOffboarding(employeeId, companyId)) {
            throw new BadRequestException("Employee is being offboarded - new assets and licences cannot be assigned");
        }
    }

    /** An offboarding checklist exists for this employee that is neither completed nor deleted. */
    public boolean hasOpenOffboarding(Long employeeId, Long companyId) {
        Number n = (Number) em.createNativeQuery(
                        "SELECT COUNT(*) FROM offboarding_checklists " +
                        "WHERE employee_id = ?1 AND company_id = ?2 AND deleted = false AND completed = false")
                .setParameter(1, employeeId)
                .setParameter(2, companyId)
                .getSingleResult();
        return n.longValue() > 0;
    }

    /** Display names for a batch of employees in one query - terminated ones included. */
    public Map<Long, String> fullNames(Collection<Long> employeeIds, Long companyId) {
        Map<Long, String> names = new HashMap<>();
        if (employeeIds == null || employeeIds.isEmpty() || companyId == null) return names;
        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery(
                        "SELECT e.id, u.first_name, u.last_name, e.employee_number " +
                        "FROM employees e LEFT JOIN users u ON u.id = e.user_id " +
                        "WHERE e.company_id = :companyId AND e.id IN (:ids)")
                .setParameter("companyId", companyId)
                .setParameter("ids", employeeIds)
                .getResultList();
        for (Object[] r : rows) {
            Long id = ((Number) r[0]).longValue();
            String first = r[1] != null ? r[1].toString() : "";
            String last = r[2] != null ? r[2].toString() : "";
            String full = (first + " " + last).trim();
            if (full.isEmpty()) full = r[3] != null ? r[3].toString() : String.valueOf(id);
            names.put(id, full);
        }
        return names;
    }

    public String fullName(Long employeeId, Long companyId) {
        if (employeeId == null) return null;
        return fullNames(List.of(employeeId), companyId).get(employeeId);
    }

    /** User id of the employee's reporting manager, if that manager is still an active employee. */
    public Long activeManagerUserId(Long employeeId, Long companyId) {
        List<?> rows = em.createNativeQuery(
                        "SELECT m.user_id FROM employees e JOIN employees m ON m.id = e.reporting_manager_id " +
                        "WHERE e.id = ?1 AND e.company_id = ?2 AND m.deleted = false AND m.active = true " +
                        "AND m.user_id IS NOT NULL")
                .setParameter(1, employeeId)
                .setParameter(2, companyId)
                .getResultList();
        return rows.isEmpty() || rows.get(0) == null ? null : ((Number) rows.get(0)).longValue();
    }
}
