package com.zuhoocms.shared.storage;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.exception.UnauthorizedException;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.Setter;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.CacheControl;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;

/**
 * {@code GET /api/public/files/{id}} needs no auth and caches publicly; {@code GET /api/files/{id}} needs bearer auth or a valid {@code ?exp&sig} and is {@code private, no-store}.
 * {@code GET /uploads/{name}} is public only while a public column references the legacy file; {@code POST /api/files/sign} signs up to 100 URLs the caller may read.
 * All responses carry {@code X-Content-Type-Options: nosniff}; images and PDFs are inline, anything else is a download.
 */
@RestController
@RequiredArgsConstructor
public class FileServeController {

    private static final int MAX_SIGN_URLS = 100;

    private final LocalFileStorageService storage;
    private final FileAccessService access;
    private final FileSigningService signing;
    private final SecurityUtil securityUtil;

    @GetMapping("/api/public/files/{id}")
    public ResponseEntity<Resource> publicFile(@PathVariable Long id) {
        StoredFile f = storage.find(id)
                .filter(file -> file.getVisibility() == FileVisibility.PUBLIC)
                .orElseThrow(() -> new ResourceNotFoundException("File not found"));
        return serve(storage.pathOf(f), FileTypes.extensionOf(f.getOriginalName()), f.getOriginalName(), true);
    }

    @GetMapping("/api/files/{id}")
    public ResponseEntity<Resource> privateFile(@PathVariable Long id,
                                                @RequestParam(required = false) String exp,
                                                @RequestParam(required = false) String sig) {
        StoredFile f;
        if (exp != null || sig != null) {
            if (!signing.verify(FileSigningService.fileSubject(id), exp, sig)) {
                throw new ForbiddenException("This file link is invalid or has expired.");
            }
            f = storage.find(id).orElseThrow(() -> new ResourceNotFoundException("File not found"));
        } else {
            User user = securityUtil.getCurrentUser();
            if (user == null) {
                throw new UnauthorizedException("Sign in to view this file.");
            }
            f = storage.find(id)
                    .filter(file -> access.canRead(file, user, securityUtil.getCurrentCompanyId()))
                    // 404 rather than 403: another company's file id is none of the caller's business.
                    .orElseThrow(() -> new ResourceNotFoundException("File not found"));
        }
        return serve(storage.pathOf(f), FileTypes.extensionOf(f.getOriginalName()), f.getOriginalName(), false);
    }

    @GetMapping("/uploads/{name:.+}")
    public ResponseEntity<Resource> legacyFile(@PathVariable String name,
                                               @RequestParam(required = false) String exp,
                                               @RequestParam(required = false) String sig) {
        Path path = storage.legacyPath(name);
        if (path == null) {
            throw new ResourceNotFoundException("File not found");
        }
        boolean isPublic = access.legacyIsPublic(name);
        if (!isPublic) {
            if (exp != null || sig != null) {
                if (!signing.verify(FileSigningService.legacySubject(name), exp, sig)) {
                    throw new ForbiddenException("This file link is invalid or has expired.");
                }
            } else {
                User user = securityUtil.getCurrentUser();
                if (user == null) {
                    throw new UnauthorizedException("Sign in to view this file.");
                }
                if (!Files.isRegularFile(path)) {
                    throw new ResourceNotFoundException("File not found");
                }
                if (!access.canReadLegacy(name, user, securityUtil.getCurrentCompanyId())) {
                    throw new ForbiddenException("You do not have access to this file.");
                }
            }
        }
        return serve(path, FileTypes.extensionOf(name), name, isPublic);
    }

    @Getter @Setter
    public static class SignRequest {
        private List<String> urls;
    }

    @PostMapping("/api/files/sign")
    @PreAuthorize("isAuthenticated()")
    public Map<String, Map<String, String>> sign(@RequestBody SignRequest request) {
        List<String> urls = request.getUrls();
        if (urls == null) {
            throw new BadRequestException("urls is required");
        }
        if (urls.size() > MAX_SIGN_URLS) {
            throw new BadRequestException("At most " + MAX_SIGN_URLS + " urls can be signed per request");
        }
        User user = securityUtil.getCurrentUser();
        Long companyId = securityUtil.getCurrentCompanyId();
        long exp = signing.newExpiry();
        Map<String, String> signed = new LinkedHashMap<>();
        for (String url : urls) {
            if (url == null || signed.containsKey(url) || !FileReferencePolicy.isOwnFileUrl(url)) continue;
            String base = url.contains("?") ? url.substring(0, url.indexOf('?')) : url;
            Long id = LocalFileStorageService.parseFileId(base);
            String subject = null;
            if (id != null) {
                if (storage.find(id).filter(f -> access.canRead(f, user, companyId)).isPresent()) {
                    subject = FileSigningService.fileSubject(id);
                }
            } else {
                String name = LocalFileStorageService.parseLegacy(base)[1];
                if (storage.legacyPath(name) != null && access.canReadLegacy(name, user, companyId)) {
                    subject = FileSigningService.legacySubject(name);
                }
            }
            if (subject != null) {
                signed.put(url, base + "?exp=" + exp + "&sig=" + signing.sign(subject, exp));
            }
        }
        return Map.of("signed", signed);
    }

    private ResponseEntity<Resource> serve(Path path, String extension, String downloadName, boolean publicCache) {
        if (path == null || !Files.isRegularFile(path)) {
            throw new ResourceNotFoundException("File not found");
        }
        String name = downloadName == null || downloadName.isBlank() ? "file" : downloadName;
        ContentDisposition disposition = (FileTypes.isInline(extension)
                ? ContentDisposition.inline() : ContentDisposition.attachment())
                .filename(name, StandardCharsets.UTF_8).build();
        HttpHeaders headers = new HttpHeaders();
        headers.setContentDisposition(disposition);
        headers.set("X-Content-Type-Options", "nosniff");
        headers.setCacheControl(publicCache
                ? CacheControl.maxAge(365, TimeUnit.DAYS).cachePublic().immutable()
                : CacheControl.noStore().cachePrivate());
        return ResponseEntity.ok()
                .headers(headers)
                .contentType(MediaType.parseMediaType(FileTypes.contentTypeFor(extension)))
                .body(new FileSystemResource(path));
    }
}
