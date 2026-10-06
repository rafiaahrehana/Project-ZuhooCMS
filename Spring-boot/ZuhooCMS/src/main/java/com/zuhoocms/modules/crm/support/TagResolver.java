package com.zuhoocms.modules.crm.support;

import com.zuhoocms.modules.crm.tag.Tag;
import com.zuhoocms.modules.crm.tag.TagRepository;
import com.zuhoocms.shared.exception.BadRequestException;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;

/**
 * Resolves tag ids to Tag rows, refusing to silently lose any: {@code findByIdInAndCompanyId} drops ids from another tenant or deleted since page load, so a record saved with two tags reported three. Comparing counts makes that a 400.
 *
 * Used by the lead, opportunity and client services, all six places that accept tagIds.
 */
public final class TagResolver {

    private TagResolver() {
    }

    /** Never null; an empty request list clears the record's tags. */
    public static List<Tag> resolve(TagRepository tagRepository, List<Long> tagIds, Long companyId) {
        if (tagIds == null || tagIds.isEmpty()) {
            return new ArrayList<>();
        }
        // Duplicate ids in the request are the caller's business, not a mismatch.
        List<Long> requested = new ArrayList<>(new LinkedHashSet<>(tagIds));
        List<Tag> found = tagRepository.findByIdInAndCompanyId(requested, companyId);
        if (found.size() != requested.size()) {
            List<Long> missing = requested.stream()
                    .filter(id -> found.stream().noneMatch(tag -> tag.getId().equals(id)))
                    .toList();
            throw new BadRequestException("Unknown tag(s): " + missing
                    + ". They may have been deleted - reload the page and try again.");
        }
        return new ArrayList<>(found);
    }
}
