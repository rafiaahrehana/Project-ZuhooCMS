package com.zuhoocms.auth.password;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

// Pre-check only (see AuthServiceImpl.verifyResetCode()): the code is not consumed here, and is re-validated at resetPassword() time.
@Data
public class VerifyResetCodeRequest {
    @NotBlank(message = "Email is required")
    private String email;
    @NotBlank(message = "Code is required")
    private String code;
}
