package com.zuhoocms.shared.storage;

import com.zuhoocms.shared.exception.BadRequestException;

import java.util.Locale;
import java.util.Set;

/** Why a file was uploaded - decides visibility, size cap and allowed types; AVATAR/LOGO/WEBSITE are PUBLIC, everything else PRIVATE. */
public enum FilePurpose {
    AVATAR(FileVisibility.PUBLIC, 5, FileTypes.IMAGES),
    LOGO(FileVisibility.PUBLIC, 5, FileTypes.IMAGES),
    WEBSITE(FileVisibility.PUBLIC, 10, FileTypes.IMAGES),
    ATTACHMENT(FileVisibility.PRIVATE, 10, FileTypes.ALL),
    RECEIPT(FileVisibility.PRIVATE, 10, FileTypes.ALL),
    STATEMENT(FileVisibility.PRIVATE, 10, FileTypes.ALL),
    DOCUMENT(FileVisibility.PRIVATE, 10, FileTypes.ALL),
    RESUME(FileVisibility.PRIVATE, 10, FileTypes.RESUMES);

    private final FileVisibility visibility;
    private final long maxBytes;
    private final Set<String> allowedExtensions;

    FilePurpose(FileVisibility visibility, int maxMb, Set<String> allowedExtensions) {
        this.visibility = visibility;
        this.maxBytes = maxMb * 1024L * 1024L;
        this.allowedExtensions = allowedExtensions;
    }

    public FileVisibility visibility() { return visibility; }
    public long maxBytes() { return maxBytes; }
    public Set<String> allowedExtensions() { return allowedExtensions; }

    /** Parses the optional {@code purpose} form field; absent means a general DOCUMENT upload. */
    public static FilePurpose parse(String raw, FilePurpose fallback) {
        if (raw == null || raw.isBlank()) return fallback;
        try {
            return FilePurpose.valueOf(raw.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException ex) {
            throw new BadRequestException("Unknown purpose '" + raw + "'. Allowed: AVATAR, LOGO, WEBSITE, "
                    + "ATTACHMENT, RECEIPT, STATEMENT, DOCUMENT, RESUME");
        }
    }
}
