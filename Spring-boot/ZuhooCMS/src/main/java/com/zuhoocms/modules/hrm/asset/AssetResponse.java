package com.zuhoocms.modules.hrm.asset;

import com.zuhoocms.enums.AssetStatus;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Getter
@Setter
public class AssetResponse {
    private Long id;
    private String name;
    private String category;
    private String serialNumber;
    private String description;
    private LocalDate purchaseDate;
    private BigDecimal purchaseCost;
    private AssetStatus status;
    private LocalDate assignedAt;
    private LocalDate returnDate;
    private String notes;
    private Long assignedToId;
    private String assignedToName;
    private LocalDateTime createdAt;

    private String assetTag;
    private String brand;
    private String model;
    private String ipAddress;
    private String macAddress;
    private String processorModel;
    private String ramSize;
    private String storageSize;
    private String operatingSystem;
    private LocalDate warrantyExpiry;
    /*
     * Both written by the dispose action and, until now, returned by nothing - so no client could show why or when
     * a machine was written off. The write was real and the read did not exist.
     */
    private LocalDate disposalDate;
    private String disposalReason;
}
