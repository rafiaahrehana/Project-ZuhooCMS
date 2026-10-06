package com.zuhoocms.core.base;

import jakarta.persistence.EntityNotFoundException;
import org.hibernate.Hibernate;
import org.hibernate.ObjectNotFoundException;
import org.hibernate.proxy.HibernateProxy;
import org.hibernate.proxy.LazyInitializer;

/**
 * Safe reads of a lazy association that may point at a soft-deleted row.
 *
 * <p>{@link BaseEntity}'s {@code @SQLRestriction("deleted = false")} makes a lazy proxy to a soft-deleted row throw
 * {@code EntityNotFoundException} the moment it is touched, and a {@code != null} check does not help because the
 * proxy itself is not null. {@code EmployeeUserResolver} established the fix for employees/users; this is the same
 * logic as plain statics, so the static response mappers (recruitment, job postings) can use it without a bean.
 */
public final class SoftDeletedProxies {

    private SoftDeletedProxies() {}

    /** The association if it can be loaded, else null when it points at a soft-deleted row; a failed proxy load never goes through the session's exception converter, so it can't mark the transaction rollback-only. */
    public static <T> T loadable(T association) {
        if (association == null) return null;
        try {
            // unproxy, not just initialize: a proxy whose load already failed reports itself initialized but has no target, and only resolving the implementation re-checks that.
            Hibernate.unproxy(association);
            return association;
        } catch (EntityNotFoundException | ObjectNotFoundException ex) {
            return null;
        }
    }

    /** Id of an association without loading it: a proxy whose load failed answers getId() by loading again and throwing, so the id comes from the lazy initializer. */
    public static Long id(BaseEntity association) {
        if (association == null) return null;
        LazyInitializer li = HibernateProxy.extractLazyInitializer(association);
        return li != null ? (Long) li.getInternalIdentifier() : association.getId();
    }
}
