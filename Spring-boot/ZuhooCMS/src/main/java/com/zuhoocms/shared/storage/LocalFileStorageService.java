package com.zuhoocms.shared.storage;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.ApiException;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.ratelimit.SlidingWindowRateLimiter;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.time.Year;
import java.util.HexFormat;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Stores uploads at {@code {upload-dir}/{companyId}/{yyyy}/{uuid}} with a {@link StoredFile} row; PUBLIC files are addressed as {@code /api/public/files/{id}}, PRIVATE ones as {@code /api/files/{id}}.
 * Type is checked by extension AND magic bytes; size by purpose (5MB avatar/logo, 10MB otherwise); per-company quota and per-user upload rate are enforced.
 * Legacy files stay at {@code {upload-dir}/{name}} and are still served at {@code /uploads/{name}} - see FileServeController.
 */
@Service
@RequiredArgsConstructor
public class LocalFileStorageService {

    public static final String PRIVATE_PREFIX = "/api/files/";
    public static final String PUBLIC_PREFIX = "/api/public/files/";
    public static final String LEGACY_PREFIX = "/uploads/";

    /** Legacy flat file names: letters, digits, dot, dash, underscore - never a path. */
    private static final Pattern LEGACY_NAME = Pattern.compile("[A-Za-z0-9][A-Za-z0-9._-]{0,200}");
    /** Legacy names embed the uploader's user id: {first_last}_{userId}_{8 hex}.{ext}. */
    private static final Pattern LEGACY_UPLOADER = Pattern.compile(".*_(\\d+)_[0-9a-f]{8}\\.[A-Za-z0-9]+$");
    private static final Pattern NEW_URL = Pattern.compile("^(?:https?://[^/]+)?/api/(public/)?files/(\\d+)$");
    private static final Pattern LEGACY_URL = Pattern.compile("^(?:https?://([^/]+))?/uploads/([^/?#]+)$");

    private final SecurityUtil securityUtil;
    private final StoredFileRepository storedFileRepository;
    private final SlidingWindowRateLimiter uploadLimiter = new SlidingWindowRateLimiter();

    @Value("${file.upload-dir:uploads}")
    private String uploadDir;

    @Value("${app.files.company-quota-mb:2048}")
    private long companyQuotaMb;

    @Value("${app.files.user-uploads-per-minute:30}")
    private int userUploadsPerMinute;

    /** Authenticated upload for the current user and their company. */
    public StoredFile store(MultipartFile file, FilePurpose purpose) {
        User user = securityUtil.getCurrentUser();
        Long companyId = securityUtil.getCurrentCompanyId();
        if (user != null && !uploadLimiter.tryAcquire("user:" + user.getId(), userUploadsPerMinute, Duration.ofMinutes(1))) {
            throw new ApiException("Too many uploads. Please wait a minute and try again.", HttpStatus.TOO_MANY_REQUESTS);
        }
        return persist(file, purpose, companyId, user != null ? user.getId() : null);
    }

    /** Anonymous resume upload from the public careers page, stored PRIVATE under that company; per-IP limits live in PublicCareersRateLimitFilter. */
    public String storeResume(MultipartFile file, Long companyId) {
        return urlFor(persist(file, FilePurpose.RESUME, companyId, null));
    }

    public String urlFor(StoredFile f) {
        return (f.getVisibility() == FileVisibility.PUBLIC ? PUBLIC_PREFIX : PRIVATE_PREFIX) + f.getId();
    }

    private StoredFile persist(MultipartFile file, FilePurpose purpose, Long companyId, Long uploaderId) {
        String extension = validate(file, purpose);

        if (companyId != null && companyQuotaMb > 0) {
            long used = storedFileRepository.sumSizeByCompanyId(companyId);
            if (used + file.getSize() > companyQuotaMb * 1024L * 1024L) {
                throw new ApiException("Your company's file storage quota (" + companyQuotaMb
                        + "MB) is full. Delete unused files or contact support.", HttpStatus.PAYLOAD_TOO_LARGE);
            }
        }

        String storageKey = (companyId != null ? companyId.toString() : "platform")
                + "/" + Year.now().getValue() + "/" + UUID.randomUUID();
        Path root = root();
        Path target = root.resolve(storageKey).normalize();
        if (!target.startsWith(root)) {
            throw new BadRequestException("Invalid storage path");
        }
        String sha256;
        try {
            Files.createDirectories(target.getParent());
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (InputStream in = new DigestInputStream(file.getInputStream(), digest)) {
                Files.copy(in, target, StandardCopyOption.REPLACE_EXISTING);
            }
            sha256 = HexFormat.of().formatHex(digest.digest());
        } catch (IOException | NoSuchAlgorithmException ex) {
            throw new RuntimeException("Could not store file. Please try again!", ex);
        }

        String original = StringUtils.cleanPath(file.getOriginalFilename() != null ? file.getOriginalFilename() : "");
        if (original.length() > 255) {
            original = original.substring(original.length() - 255);
        }
        try {
            return storedFileRepository.save(StoredFile.builder()
                    .companyId(companyId)
                    .uploaderUserId(uploaderId)
                    .purpose(purpose)
                    .visibility(purpose.visibility())
                    .originalName(original)
                    .contentType(FileTypes.contentTypeFor(extension))
                    .size(file.getSize())
                    .sha256(sha256)
                    .storageKey(storageKey)
                    .build());
        } catch (RuntimeException ex) {
            try { Files.deleteIfExists(target); } catch (IOException ignored) { /* best effort */ }
            throw ex;
        }
    }

    /** Extension whitelist per purpose, size cap per purpose, and magic-byte check. Returns the extension. */
    private String validate(MultipartFile file, FilePurpose purpose) {
        if (file == null || file.isEmpty()) {
            throw new BadRequestException("File must not be empty");
        }
        if (file.getSize() > purpose.maxBytes()) {
            throw new BadRequestException("File is too large. Maximum size for " + purpose.name().toLowerCase()
                    + " uploads is " + (purpose.maxBytes() / (1024 * 1024)) + "MB");
        }
        String name = StringUtils.cleanPath(file.getOriginalFilename() != null ? file.getOriginalFilename() : "");
        String extension = FileTypes.extensionOf(name);
        if (extension.isEmpty()) {
            throw new BadRequestException("File must have a valid extension");
        }
        if (!purpose.allowedExtensions().contains(extension)) {
            throw new BadRequestException("File type '." + extension + "' is not allowed for "
                    + purpose.name().toLowerCase() + " uploads. Allowed types: " + purpose.allowedExtensions());
        }
        byte[] head;
        try (InputStream in = file.getInputStream()) {
            head = in.readNBytes(8192);
        } catch (IOException ex) {
            throw new BadRequestException("Could not read the uploaded file");
        }
        if (!FileTypes.magicMatches(extension, head)) {
            throw new BadRequestException("File content does not match its '." + extension + "' extension");
        }
        return extension;
    }

    public Path root() {
        return Paths.get(uploadDir).toAbsolutePath().normalize();
    }

    /** The on-disk path of a stored file, or null if the key escapes the upload root. */
    public Path pathOf(StoredFile f) {
        Path root = root();
        Path p = root.resolve(f.getStorageKey()).normalize();
        return p.startsWith(root) ? p : null;
    }

    /** A legacy flat file's path, or null for anything that is not a plain file name. */
    public Path legacyPath(String name) {
        if (name == null || !LEGACY_NAME.matcher(name).matches()) return null;
        Path root = root();
        Path p = root.resolve(name).normalize();
        return p.startsWith(root) && p.getParent().equals(root) ? p : null;
    }

    /** Stored-file id of a {@code /api/files/{id}} or {@code /api/public/files/{id}} URL (relative or absolute). */
    public static Long parseFileId(String url) {
        if (url == null) return null;
        Matcher m = NEW_URL.matcher(stripQuery(url.trim()));
        return m.matches() ? Long.valueOf(m.group(2)) : null;
    }

    /** Host part (may be null for relative) and file name of a legacy {@code /uploads/{name}} URL. */
    public static String[] parseLegacy(String url) {
        if (url == null) return null;
        Matcher m = LEGACY_URL.matcher(stripQuery(url.trim()));
        return m.matches() ? new String[] {m.group(1), m.group(2)} : null;
    }

    /** Uploader user id embedded in a legacy file name, if any. */
    public static Long legacyUploaderId(String name) {
        Matcher m = LEGACY_UPLOADER.matcher(name);
        return m.matches() ? Long.valueOf(m.group(1)) : null;
    }

    private static String stripQuery(String url) {
        int q = url.indexOf('?');
        return q >= 0 ? url.substring(0, q) : url;
    }

    public Optional<StoredFile> find(Long id) {
        return id == null ? Optional.empty() : storedFileRepository.findById(id);
    }

    /** A readable local copy of an own-file URL (new or legacy) with its extension - for server-side processing (ATS). */
    public record LocalFile(Path path, String extension) {}

    public Optional<LocalFile> resolveLocal(String url) {
        Long id = parseFileId(url);
        if (id != null) {
            return find(id).map(f -> {
                Path p = pathOf(f);
                return p == null ? null : new LocalFile(p, FileTypes.extensionOf(f.getOriginalName()));
            });
        }
        String[] legacy = parseLegacy(url);
        if (legacy != null) {
            Path p = legacyPath(legacy[1]);
            return p == null ? Optional.empty() : Optional.of(new LocalFile(p, FileTypes.extensionOf(legacy[1])));
        }
        return Optional.empty();
    }
}
