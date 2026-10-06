package com.zuhoocms.shared.storage;

import java.util.Locale;
import java.util.Map;
import java.util.Set;

/** Allowed upload types, their serving content type, and the magic-byte check proving the bytes match the extension - the browser-reported content type is caller-controlled and never trusted. */
public final class FileTypes {

    private FileTypes() {}

    // No .svg/.html: script-capable documents must never be accepted.
    public static final Set<String> IMAGES = Set.of("jpg", "jpeg", "png", "gif", "webp");
    public static final Set<String> RESUMES = Set.of("pdf", "doc", "docx");
    public static final Set<String> ALL = Set.of(
            "jpg", "jpeg", "png", "gif", "webp",
            "pdf", "doc", "docx", "xls", "xlsx", "csv", "txt");

    private static final Map<String, String> CONTENT_TYPES = Map.ofEntries(
            Map.entry("jpg", "image/jpeg"),
            Map.entry("jpeg", "image/jpeg"),
            Map.entry("png", "image/png"),
            Map.entry("gif", "image/gif"),
            Map.entry("webp", "image/webp"),
            Map.entry("pdf", "application/pdf"),
            Map.entry("doc", "application/msword"),
            Map.entry("docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
            Map.entry("xls", "application/vnd.ms-excel"),
            Map.entry("xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
            Map.entry("csv", "text/csv"),
            Map.entry("txt", "text/plain"));

    public static String extensionOf(String filename) {
        if (filename == null) return "";
        int dot = filename.lastIndexOf('.');
        return dot < 0 ? "" : filename.substring(dot + 1).toLowerCase(Locale.ROOT);
    }

    /** Serving content type by extension; unknown/legacy types are served as opaque bytes. */
    public static String contentTypeFor(String extension) {
        return CONTENT_TYPES.getOrDefault(extension, "application/octet-stream");
    }

    public static boolean isImage(String extension) {
        return IMAGES.contains(extension);
    }

    /** Images and PDFs render inline; everything else is forced to download. */
    public static boolean isInline(String extension) {
        return isImage(extension) || "pdf".equals(extension);
    }

    /** True when the leading bytes match the declared extension. */
    public static boolean magicMatches(String extension, byte[] head) {
        return switch (extension) {
            case "jpg", "jpeg" -> startsWith(head, 0xFF, 0xD8, 0xFF);
            case "png" -> startsWith(head, 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A);
            case "gif" -> startsWith(head, 'G', 'I', 'F', '8');
            case "webp" -> startsWith(head, 'R', 'I', 'F', 'F') && head.length >= 12
                    && head[8] == 'W' && head[9] == 'E' && head[10] == 'B' && head[11] == 'P';
            case "pdf" -> startsWith(head, '%', 'P', 'D', 'F', '-');
            case "doc", "xls" -> startsWith(head, 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1);
            case "docx", "xlsx" -> startsWith(head, 'P', 'K', 0x03, 0x04);
            case "csv", "txt" -> looksLikePlainText(head);
            default -> false;
        };
    }

    private static boolean startsWith(byte[] data, int... prefix) {
        if (data.length < prefix.length) return false;
        for (int i = 0; i < prefix.length; i++) {
            if ((data[i] & 0xFF) != (prefix[i] & 0xFF)) return false;
        }
        return true;
    }

    /** No NUL bytes, and not an HTML/XML/SVG document dressed up as text. */
    private static boolean looksLikePlainText(byte[] head) {
        int i = 0;
        // skip a UTF-8 BOM and leading whitespace
        if (head.length >= 3 && (head[0] & 0xFF) == 0xEF && (head[1] & 0xFF) == 0xBB && (head[2] & 0xFF) == 0xBF) i = 3;
        for (byte b : head) {
            if (b == 0) return false;
        }
        while (i < head.length && Character.isWhitespace(head[i])) i++;
        return i >= head.length || head[i] != '<';
    }
}
