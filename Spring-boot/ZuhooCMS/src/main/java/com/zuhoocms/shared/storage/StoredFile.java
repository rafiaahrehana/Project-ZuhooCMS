package com.zuhoocms.shared.storage;

import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** Metadata for one uploaded file; storageKey is {@code {companyId|platform}/{yyyy}/{uuid}} and never contains the original name, so nothing a user typed reaches the filesystem path. */
@Entity
@Table(name = "stored_files", indexes = {
        @Index(name = "idx_stored_files_company", columnList = "company_id"),
        @Index(name = "idx_stored_files_uploader_created", columnList = "uploader_user_id, created_at")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class StoredFile extends BaseEntity {

    /** Owning tenant; null for platform-staff and pre-tenant uploads. */
    @Column(name = "company_id")
    private Long companyId;

    /** Null for anonymous uploads (public careers resume). */
    @Column(name = "uploader_user_id")
    private Long uploaderUserId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private FilePurpose purpose;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private FileVisibility visibility;

    @Column(name = "original_name", length = 255)
    private String originalName;

    /** Canonical type derived from the validated extension, not the browser's header. */
    @Column(name = "content_type", length = 120)
    private String contentType;

    @Column(nullable = false)
    private long size;

    @Column(length = 64)
    private String sha256;

    @Column(name = "storage_key", nullable = false, unique = true, length = 200)
    private String storageKey;
}
