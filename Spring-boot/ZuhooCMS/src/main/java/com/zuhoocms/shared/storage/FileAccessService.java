package com.zuhoocms.shared.storage;

import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.user.User;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Objects;

/**
 * PRIVATE files are readable by platform staff, the uploader, the owning company, or a company with a row referencing the file.
 * CLIENT users are narrower: only files referenced by client-facing rows of their company, never payroll, HR or finance documents.
 * Legacy /uploads files have no metadata, so they are public only while a public column references them, plus the uploader id embedded in the file name.
 */
@Service
@RequiredArgsConstructor
public class FileAccessService {

    private final FileReferenceIndex referenceIndex;

    public boolean canRead(StoredFile file, User user, Long companyId) {
        if (file.getVisibility() == FileVisibility.PUBLIC) return true;
        if (user == null) return false;
        if (user.isPlatformUser()) return true;
        if (file.getUploaderUserId() != null && file.getUploaderUserId().equals(user.getId())) return true;
        boolean client = user.getRole() == Role.CLIENT;
        if (!client && companyId != null && companyId.equals(file.getCompanyId())) return true;
        return referencedByCompany(referenceIndex.referencesTo(LocalFileStorageService.PRIVATE_PREFIX + file.getId()),
                companyId, client);
    }

    /** True when some public column (avatar, logo, website image, service icon) references the legacy file. */
    public boolean legacyIsPublic(String name) {
        return referenceIndex.referencesTo(LocalFileStorageService.LEGACY_PREFIX + name).stream()
                .anyMatch(FileReferenceIndex.Ref::isPublic);
    }

    public boolean canReadLegacy(String name, User user, Long companyId) {
        List<FileReferenceIndex.Ref> refs = referenceIndex.referencesTo(LocalFileStorageService.LEGACY_PREFIX + name);
        if (refs.stream().anyMatch(FileReferenceIndex.Ref::isPublic)) return true;
        if (user == null) return false;
        if (user.isPlatformUser()) return true;
        Long uploader = LocalFileStorageService.legacyUploaderId(name);
        if (uploader != null && uploader.equals(user.getId())) return true;
        return referencedByCompany(refs, companyId, user.getRole() == Role.CLIENT);
    }

    private static boolean referencedByCompany(List<FileReferenceIndex.Ref> refs, Long companyId, boolean client) {
        if (companyId == null) return false;
        return refs.stream().anyMatch(r -> Objects.equals(r.companyId(), companyId) && (!client || r.clientVisible()));
    }
}
