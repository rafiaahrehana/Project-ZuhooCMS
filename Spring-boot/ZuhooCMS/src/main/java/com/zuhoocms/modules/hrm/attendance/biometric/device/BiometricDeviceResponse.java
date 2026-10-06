package com.zuhoocms.modules.hrm.attendance.biometric.device;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class BiometricDeviceResponse {
    
    private Long id;
    private Long companyId;
    
    private String deviceName;
    private BiometricDeviceType deviceType;
    private String deviceId;
    private String ipAddress;
    private int portNumber;
    
    private String location;
    private String department;
    
    private BiometricDeviceStatus status;
    private int matchThreshold;
    
    private boolean enabledForCheckIn;
    private boolean enabledForCheckOut;
    
    private LocalDateTime lastSyncTime;
    private LocalDateTime lastHealthCheckTime;
    /**
     * Pinned like AttendanceResponse.isLate: unpinned, Jackson emitted only the stripped "online", so the Angular
     * device list (which reads isOnline) showed every device as Offline. The stripped "online" key is deliberately
     * NOT suppressed here - the Flutter app reads it (biometric_models.dart falls back to it), so both spellings ship.
     */
    @com.fasterxml.jackson.annotation.JsonProperty("isOnline")
    private boolean isOnline;
    
    private String manufacturer;
    private String model;
    private String firmwareVersion;
    
    private int totalEnrollments;
    private int maxEnrollments;
    
    private String notes;
}
