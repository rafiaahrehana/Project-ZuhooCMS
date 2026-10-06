package com.zuhoocms.auth.user;

import com.zuhoocms.auth.role.enums.Role;
import lombok.Builder;
import lombok.Data;

import java.time.LocalDateTime;

/** Deliberately not {@link UserResponse}: adds {@code membership} and the custom role name, and carries nothing the company owner has no business seeing. */
@Data
@Builder
public class CompanyUserResponse {

    private Long id;
    private String firstName;
    private String lastName;
    private String email;
    private String phone;
    private String image;
    private Role role;
    private boolean active;
    private boolean emailVerified;

    /** Name of the assigned custom role, when the user has one. */
    private String customRoleName;

    /** How this user belongs to the company: OWNER, EMPLOYEE or CLIENT. */
    private String membership;

    private LocalDateTime createdAt;
}
