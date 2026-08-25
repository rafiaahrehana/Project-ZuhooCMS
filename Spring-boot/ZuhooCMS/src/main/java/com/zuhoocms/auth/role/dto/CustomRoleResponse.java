package com.zuhoocms.auth.role.dto;

import lombok.Builder;
import lombok.Getter;

@Getter
@Builder
public class CustomRoleResponse {

    private Long id;

    private String name;

    private String description;

    private Boolean active;

    private Boolean systemRole;
}