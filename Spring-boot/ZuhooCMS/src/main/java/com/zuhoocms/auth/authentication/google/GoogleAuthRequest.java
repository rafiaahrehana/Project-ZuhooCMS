package com.zuhoocms.auth.authentication.google;

import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.Setter;

/** Deliberately carries only the Firebase ID token - no email or name: accepting an email from the client would let anyone sign in as anyone. */
@Getter
@Setter
public class GoogleAuthRequest {

    @NotBlank(message = "Google ID token is required")
    private String idToken;
}
