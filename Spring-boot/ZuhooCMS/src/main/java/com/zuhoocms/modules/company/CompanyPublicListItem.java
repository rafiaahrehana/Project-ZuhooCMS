package com.zuhoocms.modules.company;

/** One entry of the public company picker: deliberately only what the picker shows - no email, phone, address or status. */
public record CompanyPublicListItem(Long id, String companyName, String subdomain, String logo) {}
