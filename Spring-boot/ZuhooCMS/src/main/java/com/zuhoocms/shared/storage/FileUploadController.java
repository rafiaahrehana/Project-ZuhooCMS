package com.zuhoocms.shared.storage;

import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.util.LinkedHashMap;
import java.util.Map;

/** Upload endpoints: multipart {@code file} plus optional {@code purpose} (default DOCUMENT); the returned fileUrl is public for AVATAR/LOGO/WEBSITE and relative, so clients resolve it against the API origin. */
@RestController
@RequestMapping("/api/upload")
@RequiredArgsConstructor
@PreAuthorize("isAuthenticated()")
public class FileUploadController {

    private final LocalFileStorageService fileStorageService;

    @PostMapping
    public ResponseEntity<Map<String, Object>> uploadFile(@RequestParam("file") MultipartFile file,
                                                          @RequestParam(value = "purpose", required = false) String purpose) {
        StoredFile stored = fileStorageService.store(file, FilePurpose.parse(purpose, FilePurpose.DOCUMENT));
        return ResponseEntity.ok(toResponse(stored));
    }

    /** Profile picture: always AVATAR (public, images only, 5MB). */
    @PostMapping("/avatar")
    public ResponseEntity<Map<String, Object>> uploadAvatar(@RequestParam("file") MultipartFile file) {
        return ResponseEntity.ok(toResponse(fileStorageService.store(file, FilePurpose.AVATAR)));
    }

    private Map<String, Object> toResponse(StoredFile stored) {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("fileName", stored.getOriginalName());
        response.put("fileUrl", fileStorageService.urlFor(stored));
        response.put("fileId", stored.getId());
        response.put("message", "File uploaded successfully!");
        return response;
    }
}
