package com.zuhoocms.config;

import java.security.Principal;

/** STOMP session Principal whose name MUST be the numeric user id: pushes go via convertAndSendToUser(userId.toString(), ...), which Spring matches against getName(), not the email. */
public class StompPrincipal implements Principal {

    private final String name;

    public StompPrincipal(String name) {
        this.name = name;
    }

    @Override
    public String getName() {
        return name;
    }
}
