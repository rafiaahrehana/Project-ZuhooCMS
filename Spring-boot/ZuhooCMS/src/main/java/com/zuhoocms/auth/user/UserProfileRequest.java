package com.zuhoocms.auth.user;

import com.zuhoocms.shared.address.AddressRequest;
import lombok.Data;

@Data
public class UserProfileRequest {
    private String firstName;
    private String lastName;
    private String email;
    // Required whenever the email changes, and verified against the account's real password first.
    private String currentPassword;
    private String phone;
    private String image;
    private String languagePreference;
    private AddressRequest location;
    private String companyEmail;
}
