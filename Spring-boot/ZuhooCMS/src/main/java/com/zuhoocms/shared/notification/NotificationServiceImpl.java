package com.zuhoocms.shared.notification;

import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.security.SecurityUtil;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

/**
 * Persistence-first: the Notification is stored before the WebSocket push, so it survives an inactive connection and the client catches up via GET /api/notifications?unreadOnly=true.
 * Sends never block the caller: scheduled after commit (AfterCommit) and run by NotificationDeliveryWorker, a separate bean so the @Async proxy applies.
 * sendForServiceRequest() dedupes only an identical notification (recipient + request + type + title + message) from the last few minutes, so genuine repeat events still get through.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class NotificationServiceImpl implements NotificationService {

    private final NotificationRepository     notificationRepository;
    private final NotificationDeliveryWorker deliveryWorker;
    private final SecurityUtil               securityUtil;

    @Override
    public void send(CreateNotificationRequest request) {
        Long companyId = resolveCompanyId(request);
        AfterCommit.run(() -> deliveryWorker.deliver(request, companyId, false));
    }

    @Override
    public void sendForServiceRequest(CreateNotificationRequest request) {
        Long companyId = resolveCompanyId(request);
        AfterCommit.run(() -> deliveryWorker.deliver(request, companyId, true));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<NotificationResponse> getMyNotifications(boolean unreadOnly, Pageable pageable) {
        Long userId = securityUtil.getCurrentUser().getId();
        Page<Notification> page = unreadOnly
            ? notificationRepository.findByRecipientIdAndReadFalseOrderByCreatedAtDesc(userId, pageable)
            : notificationRepository.findByRecipientIdOrderByCreatedAtDesc(userId, pageable);
        return page.map(NotificationMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public NotificationCountResponse getUnreadCount() {
        Long userId = securityUtil.getCurrentUser().getId();
        return new NotificationCountResponse(
            notificationRepository.countByRecipientIdAndReadFalse(userId));
    }

    @Override
    @Transactional
    public void markAsRead(Long notificationId) {
        Long userId = securityUtil.getCurrentUser().getId();
        // Someone else's notification is reported exactly like a missing one, so ids can't be probed.
        Notification n = notificationRepository.findById(notificationId)
            .filter(found -> found.getRecipient() != null && userId.equals(found.getRecipient().getId()))
            .orElseThrow(() -> new ResourceNotFoundException("Notification not found: " + notificationId));
        if (!n.isRead()) {
            n.setRead(true);
            n.setReadAt(LocalDateTime.now());
        }
    }

    @Override
    @Transactional
    public void markAllAsRead() {
        Long userId = securityUtil.getCurrentUser().getId();
        notificationRepository.markAllReadForUser(userId, LocalDateTime.now());
    }

    /** Explicit company on the request wins; otherwise fall back to the calling tenant (null for schedulers). */
    private Long resolveCompanyId(CreateNotificationRequest request) {
        if (request.getCompanyId() != null) {
            return request.getCompanyId();
        }
        try {
            return securityUtil.getCurrentCompanyId();
        } catch (Exception e) {
            return null;
        }
    }
}
