package com.zuhoocms.modules.hrm.employee;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.core.base.SoftDeletedProxies;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Safe access from an {@link Employee} to its (lazy) {@link User} and other associations.
 *
 * <p>{@code BaseEntity}'s {@code @SQLRestriction("deleted = false")} makes a lazy proxy to a soft-deleted row throw {@code EntityNotFoundException} the moment it is touched, which 500'd every list/detail/edit of an employee whose user had been soft-deleted.
 * {@link #loadable} returns null instead of throwing, and {@link #snapshot} reads the user's display fields with company-scoped native SQL that bypasses the restriction.
 */
@Component
public class EmployeeUserResolver {

    @PersistenceContext
    private EntityManager em;

    /** Read-only view of an employee's user row, soft-deleted or not. */
    public record UserSnapshot(Long id, String firstName, String lastName, String email, String phone,
                               String image, boolean active, boolean deleted,
                               Long customRoleId, String customRoleName) {
        public String fullName() {
            String first = firstName != null ? firstName : "";
            String last = lastName != null ? lastName : "";
            return (first + " " + last).trim();
        }
    }

    /** The association if it can be loaded, else null when it points at a soft-deleted row; a failed proxy load never goes through the session's exception converter, so it can't mark the transaction rollback-only. */
    public <T> T loadable(T association) {
        return SoftDeletedProxies.loadable(association);
    }

    /**
     * Display name for a lazy employee association, without a query and without touching a soft-deleted row:
     * {@link Employee#getFullName()} reads {@code user}, so it throws for an employee whose login was soft-deleted,
     * and the employee proxy itself throws once the employee is terminated. Null when neither row is readable.
     * Static so the static response mappers (recruitment, job postings) can use it; {@link #fullName(Employee)} is
     * the richer version for callers that have the bean and can fall back to a native snapshot.
     */
    public static String displayName(Employee employee) {
        Employee e = SoftDeletedProxies.loadable(employee);
        if (e == null) return null;
        User u = SoftDeletedProxies.loadable(e.getUser());
        if (u != null) return u.getFullName();
        return e.getEmployeeNumber() != null ? e.getEmployeeNumber() : String.valueOf(SoftDeletedProxies.id(employee));
    }

    /** The employee's user if it is a live (not soft-deleted) account, else null. */
    public User liveUser(Employee e) {
        return e != null ? loadable(e.getUser()) : null;
    }

    /** FK value of employee.user_id, read from the proxy without loading (or failing to load) the user. */
    public Long userId(Employee e) {
        return e != null ? id(e.getUser()) : null;
    }

    /** Id of an association without loading it: a proxy whose load failed answers getId() by loading again and throwing, so the id comes from the lazy initializer. */
    public Long id(com.zuhoocms.core.base.BaseEntity association) {
        return SoftDeletedProxies.id(association);
    }

    /** The employee's user row (deleted or not), company-scoped; null when there is none. */
    public UserSnapshot snapshot(Long employeeId, Long companyId) {
        if (employeeId == null || companyId == null) return null;
        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery(
                        "SELECT u.id, u.first_name, u.last_name, u.email, u.phone, u.image, u.active, u.deleted, " +
                        "       cr.id, cr.name " +
                        "FROM employees e JOIN users u ON u.id = e.user_id " +
                        "LEFT JOIN custom_roles cr ON cr.id = u.custom_role_id AND cr.deleted = false " +
                        "WHERE e.id = ?1 AND e.company_id = ?2")
                .setParameter(1, employeeId)
                .setParameter(2, companyId)
                .getResultList();
        if (rows.isEmpty()) return null;
        Object[] r = rows.get(0);
        return new UserSnapshot(
                r[0] != null ? ((Number) r[0]).longValue() : null,
                str(r[1]), str(r[2]), str(r[3]), str(r[4]), str(r[5]),
                Boolean.TRUE.equals(r[6]), Boolean.TRUE.equals(r[7]),
                r[8] != null ? ((Number) r[8]).longValue() : null, str(r[9]));
    }

    /** Display name for the employee: live user, else the user row regardless of soft-delete, else the employee number. */
    public String fullName(Employee e) {
        if (e == null) return null;
        User u = liveUser(e);
        if (u != null) return e.getFullName();
        UserSnapshot s = snapshot(e.getId(), companyId(e));
        if (s != null && !s.fullName().isEmpty()) return s.fullName();
        return e.getEmployeeNumber() != null ? e.getEmployeeNumber() : String.valueOf(e.getId());
    }

    /** Re-enables the employee's login after SUSPENDED -> ACTIVE, including an account soft-deleted on suspension (only reachable through native SQL); company-scoped through the employee row. */
    public int restoreUser(Long employeeId, Long companyId) {
        return em.createNativeQuery(
                        "UPDATE users SET active = true, deleted = false, deleted_at = NULL, updated_at = now() " +
                        "WHERE id = (SELECT e.user_id FROM employees e WHERE e.id = ?1 AND e.company_id = ?2)")
                .setParameter(1, employeeId)
                .setParameter(2, companyId)
                .executeUpdate();
    }

    public Long companyId(Employee e) {
        return e != null ? id(e.getCompany()) : null;
    }

    private static String str(Object o) {
        return o != null ? o.toString() : null;
    }
}
