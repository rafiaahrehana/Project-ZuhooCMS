package com.zuhoocms.shared.notification;

import lombok.Getter;
import lombok.Setter;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;

@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class NotificationCountResponse {
    private long unreadCount;
}
