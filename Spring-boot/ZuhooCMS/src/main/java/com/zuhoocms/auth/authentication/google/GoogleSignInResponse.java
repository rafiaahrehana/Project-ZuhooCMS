package com.zuhoocms.auth.authentication.google;

import com.zuhoocms.auth.authentication.LoginResponse;
import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * registered = true  -> `login` holds the usual tokens.
 * registered = false -> the Google account is genuine but unknown, so the app collects a company and calls /api/auth/google/register; email and name come from the verified token only to prefill that form.
 */
@Getter
@AllArgsConstructor
public class GoogleSignInResponse {

    private boolean registered;
    private LoginResponse login;
    private String email;
    private String firstName;
    private String lastName;

    public static GoogleSignInResponse loggedIn(LoginResponse login) {
        return new GoogleSignInResponse(true, login, login.getEmail(), null, null);
    }

    public static GoogleSignInResponse needsRegistration(String email, String firstName, String lastName) {
        return new GoogleSignInResponse(false, null, email, firstName, lastName);
    }
}
