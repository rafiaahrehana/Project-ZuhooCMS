package com.zuhoocms.shared.notification.device;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.Getter;
import lombok.Setter;

/** No userId field on purpose: the owner comes from the JWT, or any caller could register a device against someone else's account and receive their notifications. */
@Getter
@Setter
public class RegisterDeviceTokenRequest {

    @NotBlank(message = "Device token is required")
    @Size(max = 512, message = "Device token is too long")
    private String token;

    @NotNull(message = "Platform is required")
    private DevicePlatform platform;
}
