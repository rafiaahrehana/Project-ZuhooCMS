package com.zuhoocms.modules.hrm.attendance.biometric.device;

import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;
import java.time.LocalDateTime;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "biometric_devices")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class BiometricDevice extends BaseEntity {

    private Long companyId;

    private String deviceName; // "Main Gate Fingerprint Terminal"

    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private BiometricDeviceType deviceType;

    private String deviceId; // Serial number or unique ID
    private String ipAddress; // For network-based devices
    private int portNumber;

    private String location; // "Main Office - Ground Floor"
    private String department; // "Administration"

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private BiometricDeviceStatus status = BiometricDeviceStatus.ACTIVE;

    private String apiEndpoint;
    private String apiKey;
    private String apiSecret;

    @Builder.Default
    private int matchThreshold = 95; // 95% for fingerprint

    @Builder.Default
    private boolean enabledForCheckIn = true;

    @Builder.Default
    private boolean enabledForCheckOut = true;

    private LocalDateTime lastSyncTime;
    private LocalDateTime lastHealthCheckTime;

    @Builder.Default
    private boolean isOnline = true;

    private String manufacturer; // "Suprema", "ZKTeco", etc.
    private String model;
    private String firmwareVersion;

    @Builder.Default
    private int totalEnrollments = 0;

    @Builder.Default
    private int maxEnrollments = 5000;

    private String notes;
    private String maintenanceNotes;

    public boolean isAtCapacity() {
        return totalEnrollments >= maxEnrollments;
    }

    public boolean canAddEnrollments(int count) {
        return (totalEnrollments + count) <= maxEnrollments;
    }
}
