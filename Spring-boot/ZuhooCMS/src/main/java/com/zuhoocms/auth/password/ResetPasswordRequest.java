package com.zuhoocms.auth.password;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Data;

// Two mutually-exclusive proofs, checked in AuthServiceImpl.resetPassword(): email+code for "forgot password", or token for the JWT link ClientServiceImpl.invite() emails.
// The token path must stay: an invited client never went through "forgot password", so it has no code.
@Data
public class ResetPasswordRequest {
    private String email;
    private String code;
    private String token;
    @NotBlank(message = "New password is required")
    @Size(min = 8, message = "Password must be at least 8 characters")
    private String newPassword;
    @NotBlank(message = "Password confirmation is required")
    private String confirmPassword;
}
