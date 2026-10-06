package com.zuhoocms.shared.storage;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Answers which rows reference a file URL, in which company, and whether that reference is public - legacy {@code /uploads/{name}} files have no metadata row of their own.
 * Exact suffix match ({@code right(col, n) = suffix}) so absolute and relative forms both match and LIKE wildcards in file names ('_') cannot widen it.
 * Native SQL bypasses the tenant filter on purpose - the caller applies the company rule to the returned company ids.
 */
@Component
public class FileReferenceIndex {

    /** One file-URL column: table, column, SQL for its company id, public?, visible to CLIENT users?, has deleted flag? */
    private record Col(String table, String column, String companyExpr, boolean isPublic, boolean clientVisible, boolean hasDeleted) {}

    /** A matching reference: owning company (null = platform-level row), public?, client-visible? */
    public record Ref(Long companyId, boolean isPublic, boolean clientVisible) {}

    private static final String OWN = "t.company_id";
    private static final String USER_COMPANY = "coalesce("
            + "(select c.id from companies c where c.owner_id = t.id limit 1), "
            + "(select e.company_id from employees e where e.user_id = t.id and e.deleted = false limit 1), "
            + "(select cl.company_id from clients cl where cl.user_id = t.id and cl.deleted = false limit 1))";

    private static final List<Col> COLUMNS = List.of(
            // Public: images shown to anonymous visitors. (Service-desk "iconUrl" columns hold Bootstrap class names, not files.)
            new Col("users", "image", USER_COMPANY, true, true, true),
            new Col("employees", "profile_image_url", OWN, true, true, true),
            new Col("website_settings", "logo_url", OWN, true, true, true),
            new Col("website_settings", "favicon_url", OWN, true, true, true),
            new Col("website_settings", "hero_image_url", OWN, true, true, true),
            new Col("website_settings", "og_image", OWN, true, true, true),
            new Col("website_hero_images", "image_url",
                    "(select s.company_id from website_settings s where s.id = t.settings_id)", true, true, false),
            new Col("website_people", "photo_url", OWN, true, true, true),
            new Col("website_people", "avatar_url", OWN, true, true, true),
            new Col("website_content", "cover_image_url", OWN, true, true, true),
            new Col("website_services", "image_url", OWN, true, true, true),
            new Col("website_projects", "cover_image_url", OWN, true, true, true),
            // Private: business documents.
            new Col("announcements", "attachment_url", OWN, false, false, true),
            // Attendance selfies: HR reviewing a flagged punch is not the uploader, so without these the photo
            // would only be readable by the employee who took it.
            new Col("attendance", "check_in_selfie_url", OWN, false, false, true),
            new Col("attendance", "check_out_selfie_url", OWN, false, false, true),
            new Col("bank_reconciliations", "statement_file_url", OWN, false, false, true),
            new Col("documents", "file_url", OWN, false, true, true),
            new Col("employment_letters", "file_url", OWN, false, false, true),
            new Col("expenses", "receipt_url", OWN, false, false, true),
            new Col("job_applications", "resume_url", OWN, false, false, true),
            new Col("recruitment_candidates", "resume_url", OWN, false, false, true),
            new Col("recruitment_talent_pool", "resume_url", OWN, false, false, true),
            new Col("performance_review_attachments", "file_url", OWN, false, false, true),
            new Col("proposal_attachments", "file_url", OWN, false, true, true),
            new Col("request_comments", "attachment_url", OWN, false, true, true),
            new Col("support_tickets", "attachment_url", OWN, false, true, true),
            new Col("support_messages", "attachment_url",
                    "(select st.company_id from support_tickets st where st.id = t.ticket_id)", false, true, true));

    private static final String SQL = buildSql();
    private static final Duration CACHE_TTL = Duration.ofSeconds(30);

    private record Cached(List<Ref> refs, Instant at) {}

    private final Map<String, Cached> cache = new ConcurrentHashMap<>();

    @PersistenceContext
    private EntityManager entityManager;

    private static String buildSql() {
        StringBuilder sb = new StringBuilder();
        for (Col c : COLUMNS) {
            if (!sb.isEmpty()) sb.append(" UNION ALL ");
            sb.append("SELECT ").append(c.companyExpr()).append(" AS cid, ")
              .append(c.isPublic()).append(" AS pub, ")
              .append(c.clientVisible()).append(" AS cv FROM ").append(c.table()).append(" t WHERE right(t.")
              .append(c.column()).append(", :len) = :suffix");
            if (c.hasDeleted()) sb.append(" AND t.deleted = false");
        }
        return sb.toString();
    }

    /** Every row referencing a URL that ends with {@code suffix} (e.g. "/uploads/a.png", "/api/files/12"). */
    public List<Ref> referencesTo(String suffix) {
        Cached hit = cache.get(suffix);
        if (hit != null && hit.at().plus(CACHE_TTL).isAfter(Instant.now())) {
            return hit.refs();
        }
        List<?> rows = entityManager.createNativeQuery(SQL)
                .setParameter("len", suffix.length())
                .setParameter("suffix", suffix)
                .getResultList();
        List<Ref> refs = new ArrayList<>(rows.size());
        for (Object row : rows) {
            Object[] r = (Object[]) row;
            Long cid = r[0] == null ? null : ((Number) r[0]).longValue();
            refs.add(new Ref(cid, Boolean.TRUE.equals(r[1]), Boolean.TRUE.equals(r[2])));
        }
        if (cache.size() > 10_000) cache.clear();
        cache.put(suffix, new Cached(List.copyOf(refs), Instant.now()));
        return refs;
    }

    /** Drops cached lookups - called after a row starts referencing a new file. */
    public void invalidate(String suffix) {
        if (suffix != null) cache.remove(suffix);
    }
}
