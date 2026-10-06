package com.zuhoocms.modules.support;

import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;

/** Page-request builder shared by the support controllers: page >= 0, 1 <= size <= 100. */
public final class SupportPaging {

    public static final int MAX_PAGE_SIZE = 100;

    private SupportPaging() {
    }

    public static PageRequest of(int page, int size) {
        return PageRequest.of(Math.max(page, 0), Math.min(Math.max(size, 1), MAX_PAGE_SIZE));
    }

    public static PageRequest of(int page, int size, Sort sort) {
        return PageRequest.of(Math.max(page, 0), Math.min(Math.max(size, 1), MAX_PAGE_SIZE), sort);
    }
}
