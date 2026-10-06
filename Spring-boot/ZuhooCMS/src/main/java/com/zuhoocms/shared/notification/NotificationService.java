package com.zuhoocms.shared.notification;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

public interface NotificationService {
    /** Internal: persists then pushes via WebSocket, fire and forget. */
    void send(CreateNotificationRequest request);

    /** Internal: send with duplicate suppression for service-request status events. */
    void sendForServiceRequest(CreateNotificationRequest request);

    Page<NotificationResponse> getMyNotifications(boolean unreadOnly, Pageable pageable);

    NotificationCountResponse getUnreadCount();

    void markAsRead(Long notificationId);

    void markAllAsRead();}
