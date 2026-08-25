package com.zuhoocms.shared.address;

import lombok.Data;

@Data
public class UpdateLocationRequest {
    private String name;
    private Long parentId;
}
