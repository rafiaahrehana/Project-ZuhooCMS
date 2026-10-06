package com.zuhoocms.modules.crm.support;

import com.zuhoocms.shared.exception.BadRequestException;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;

import java.util.Set;

/** Whitelists the properties a caller may sort by: raw {@code sortBy} handed to {@link Sort#by} threw {@code PropertyReferenceException} as a 500, and {@code ?sortBy=password} probed which properties exist. */
public final class CrmSortWhitelist {

    public static final Set<String> LEAD = Set.of(
            "id", "createdAt", "updatedAt", "contactName", "companyName", "email", "phone",
            "status", "source", "priority", "estimatedValue", "expectedCloseDate",
            "lastContactDate", "lastActivityAt", "convertedAt");

    public static final Set<String> CONTACT = Set.of(
            "id", "createdAt", "updatedAt", "fullName", "email", "phone", "jobTitle", "department");

    private CrmSortWhitelist() {
    }

    /** The property itself, or a 400 naming the accepted values. */
    public static String require(Set<String> allowed, String property) {
        if (property == null || property.isBlank()) {
            return null;
        }
        String trimmed = property.trim();
        if (!allowed.contains(trimmed)) {
            throw new BadRequestException("Cannot sort by \"" + trimmed + "\". Allowed values: "
                    + allowed.stream().sorted().reduce((a, b) -> a + ", " + b).orElse(""));
        }
        return trimmed;
    }

    /** ASC/DESC, or a 400 - {@code Sort.Direction.fromString} otherwise throws IllegalArgumentException. */
    public static Sort.Direction direction(String value) {
        if (value == null || value.isBlank()) return Sort.Direction.DESC;
        try {
            return Sort.Direction.fromString(value.trim());
        } catch (IllegalArgumentException e) {
            throw new BadRequestException("Sort direction must be ASC or DESC");
        }
    }

    /** A validated Pageable whose sort always ends in {@code id}: a nullable or non-unique sort key alone gives Postgres no stable row order, so a row can appear on two pages or none. */
    public static Pageable pageable(int page, int size, Set<String> allowed, String sortBy, String sortDirection) {
        String property = require(allowed, sortBy);
        Sort.Direction direction = direction(sortDirection);
        Sort sort = property == null
                ? Sort.by(Sort.Direction.DESC, "createdAt").and(Sort.by(Sort.Direction.ASC, "id"))
                : Sort.by(direction, property).and(Sort.by(Sort.Direction.ASC, "id"));
        return PageRequest.of(page, size, sort);
    }

    /** Appends {@code id ASC} to an existing sort as a deterministic tiebreaker. */
    public static Pageable withIdTiebreaker(Pageable pageable) {
        if (pageable.getSort().getOrderFor("id") != null) {
            return pageable;
        }
        return PageRequest.of(pageable.getPageNumber(), pageable.getPageSize(),
                pageable.getSort().and(Sort.by(Sort.Direction.ASC, "id")));
    }
}
