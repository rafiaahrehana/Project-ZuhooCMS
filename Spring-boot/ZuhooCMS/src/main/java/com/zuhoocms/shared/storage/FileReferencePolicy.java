package com.zuhoocms.shared.storage;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.Locale;
import java.util.Objects;
import java.util.Set;

/**
 * Guards file-URL columns: only this app's own URLs ({@code /api/files/{id}}, {@code /api/public/files/{id}}, legacy {@code /uploads/{name}}) and only files of the caller's company, so {@code http://evil/x.pdf} is a 400 rather than a link colleagues click.
 * Static entry points ({@link #requireOwn}) so callers need a one-line call rather than a constructor dependency.
 */
@Component
public class FileReferencePolicy {

    private static FileReferencePolicy instance;

    private final LocalFileStorageService storage;
    private final SecurityUtil securityUtil;
    private final CompanyRepository companyRepository;
    private final EmployeeRepository employeeRepository;
    private final ClientRepository clientRepository;
    private final FileReferenceIndex referenceIndex;
    private final Set<String> ownHosts = new HashSet<>();

    public FileReferencePolicy(@Lazy LocalFileStorageService storage, SecurityUtil securityUtil,
                               @Lazy CompanyRepository companyRepository,
                               @Lazy EmployeeRepository employeeRepository, @Lazy ClientRepository clientRepository,
                               @Lazy FileReferenceIndex referenceIndex,
                               @Value("${app.backend-url:http://localhost:8085}") String backendUrl) {
        this.storage = storage;
        this.securityUtil = securityUtil;
        this.companyRepository = companyRepository;
        this.employeeRepository = employeeRepository;
        this.clientRepository = clientRepository;
        this.referenceIndex = referenceIndex;
        for (String u : backendUrl.split(",")) {
            try {
                URI uri = URI.create(u.trim());
                if (uri.getAuthority() != null) ownHosts.add(uri.getAuthority().toLowerCase(Locale.ROOT));
            } catch (IllegalArgumentException ignored) { /* skip malformed entry */ }
        }
    }

    @PostConstruct
    void register() {
        instance = this;
    }

    /** Validates a new value for a file-URL column; returns it trimmed (null/blank -> null). */
    public static String requireOwn(String url) {
        return requireOwn(url, null);
    }

    /** As {@link #requireOwn(String)}, but an unchanged {@code current} value is accepted, so editing a row whose file predates these rules never fails. */
    public static String requireOwn(String url, String current) {
        if (url == null || url.isBlank()) return url; // clearing the column is always allowed
        String trimmed = url.trim();
        if (current != null && trimmed.equals(current.trim())) return trimmed;
        if (instance == null) return trimmed; // not in a Spring context (unit tests)
        instance.check(trimmed);
        return trimmed;
    }

    /** For anonymous flows with an explicit tenant (public careers apply): the URL must be a file stored for {@code companyId}. */
    public static String requireOwnForCompany(String url, Long companyId) {
        if (url == null || url.isBlank()) return url;
        String trimmed = url.trim();
        if (instance == null) return trimmed;
        Long id = LocalFileStorageService.parseFileId(trimmed);
        boolean ok = id != null && isOwnFileUrl(trimmed)
                && instance.storage.find(id).map(f -> Objects.equals(f.getCompanyId(), companyId)).orElse(false);
        if (!ok) {
            throw new BadRequestException("Upload your resume with the form instead of linking to it.");
        }
        return trimmed;
    }

    /** True when the URL is one of this app's own file URLs (shape only, no ownership check). */
    public static boolean isOwnFileUrl(String url) {
        if (url == null) return false;
        if (LocalFileStorageService.parseFileId(url) != null) return !url.contains("://") || instance == null || instance.ownHost(url);
        String[] legacy = LocalFileStorageService.parseLegacy(url);
        return legacy != null && (legacy[0] == null || instance == null || instance.ownHosts.contains(legacy[0].toLowerCase(Locale.ROOT)));
    }

    private boolean ownHost(String url) {
        try {
            String authority = URI.create(url).getAuthority();
            return authority != null && ownHosts.contains(authority.toLowerCase(Locale.ROOT));
        } catch (IllegalArgumentException ex) {
            return false;
        }
    }

    private void check(String url) {
        if (!isOwnFileUrl(url)) {
            throw new BadRequestException("Only files uploaded to this app can be attached - upload the file instead of linking to it.");
        }
        User user = securityUtil.getCurrentUser();
        Long companyId = securityUtil.getCurrentCompanyId();

        Long id = LocalFileStorageService.parseFileId(url);
        if (id != null) {
            StoredFile f = storage.find(id)
                    .orElseThrow(() -> new BadRequestException("The attached file does not exist."));
            boolean ok;
            if (companyId != null) {
                ok = companyId.equals(f.getCompanyId());
            } else {
                // Platform staff (no tenant context): platform-level files, or ones they uploaded.
                ok = f.getCompanyId() == null
                        || (user != null && Objects.equals(user.getId(), f.getUploaderUserId()));
            }
            if (!ok) {
                throw new BadRequestException("The attached file belongs to another company.");
            }
            referenceIndex.invalidate(LocalFileStorageService.PRIVATE_PREFIX + id);
            return;
        }

        String name = LocalFileStorageService.parseLegacy(url)[1];
        Path p = storage.legacyPath(name);
        if (p == null || !Files.isRegularFile(p)) {
            throw new BadRequestException("The attached file does not exist.");
        }
        if (companyId != null) {
            // A legacy file has no owner row; its name embeds the uploader's user id.
            Long uploader = LocalFileStorageService.legacyUploaderId(name);
            boolean sameCompany = uploader != null && userInCompany(uploader, companyId);
            boolean alreadyOurs = referenceIndex.referencesTo(LocalFileStorageService.LEGACY_PREFIX + name).stream()
                    .anyMatch(r -> companyId.equals(r.companyId()));
            if (!sameCompany && !alreadyOurs) {
                throw new BadRequestException("The attached file belongs to another company.");
            }
        }
        referenceIndex.invalidate(LocalFileStorageService.LEGACY_PREFIX + name);
    }

    private boolean userInCompany(Long userId, Long companyId) {
        if (companyRepository.findByOwnerId(userId).map(c -> companyId.equals(c.getId())).orElse(false)) return true;
        if (employeeRepository.findCompanyIdByUserId(userId).map(companyId::equals).orElse(false)) return true;
        return clientRepository.findCompanyIdByUserId(userId).map(companyId::equals).orElse(false);
    }

}
