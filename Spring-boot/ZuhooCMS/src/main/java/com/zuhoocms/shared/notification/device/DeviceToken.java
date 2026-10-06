package com.zuhoocms.shared.notification.device;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * One row per app install registered for notifications; the token is unique because FCM can hand it to another account after a reinstall and re-registering must move the row.
 * companyId is denormalised so a tenant's tokens can be scoped without joining through the user.
 */
@Entity
@Table(name = "device_tokens",
       uniqueConstraints = @UniqueConstraint(name = "uk_device_tokens_token", columnNames = "token"))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class DeviceToken extends BaseEntity {

    @Column(nullable = false, length = 512)
    private String token;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private DevicePlatform platform;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(name = "company_id")
    private Long companyId;

    /** Refreshed on every re-registration, so stale installs can be pruned later. */
    private LocalDateTime lastSeenAt;
}
