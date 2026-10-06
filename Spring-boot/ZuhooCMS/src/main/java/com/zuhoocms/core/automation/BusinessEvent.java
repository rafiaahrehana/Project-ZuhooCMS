package com.zuhoocms.core.automation;

import lombok.Getter;
import org.springframework.context.ApplicationEvent;

/** Base cross-module event: every business event carries companyId and handlers must filter on it for tenant isolation. */
@Getter
public abstract class BusinessEvent extends ApplicationEvent {

    private final Long companyId;
    private final String eventType;

    protected BusinessEvent(Object source, Long companyId, String eventType) {
        super(source);
        this.companyId = companyId;
        this.eventType = eventType;
    }
}
