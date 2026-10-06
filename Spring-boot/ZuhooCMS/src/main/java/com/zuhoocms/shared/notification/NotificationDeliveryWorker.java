package com.zuhoocms.shared.notification;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequest;
import com.zuhoocms.shared.notification.device.FcmPushService;
import jakarta.persistence.EntityManager;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.EnumSet;
import java.util.Set;

/** Asynchronous half of NotificationServiceImpl, in its own bean so the @Async and @Transactional proxies actually apply (called after commit, see AfterCommit). */
@Component
@RequiredArgsConstructor
@Slf4j
public class NotificationDeliveryWorker {

    /** Suppression window for identical service-request notifications. */
    static final int DEDUPE_WINDOW_MINUTES = 5;

    private static final Set<NotificationType> SERVICE_REQUEST_TYPES = EnumSet.of(
            NotificationType.REQUEST_SUBMITTED, NotificationType.REQUEST_ASSIGNED, NotificationType.REQUEST_UPDATED,
            NotificationType.COMPLETED, NotificationType.REJECTED, NotificationType.CANCELLED,
            NotificationType.SLA_WARNING, NotificationType.SLA_BREACHED);

    private static final Set<NotificationType> NEW_REQUEST_TYPES = EnumSet.of(
            NotificationType.REQUEST_SUBMITTED, NotificationType.REQUEST_ASSIGNED);

    private final NotificationRepository notificationRepository;
    private final NotificationPreferenceRepository preferenceRepository;
    private final UserRepository userRepository;
    private final SimpMessagingTemplate messagingTemplate;
    private final FcmPushService fcmPushService;
    private final EntityManager entityManager;

    /**
     * @param companyId resolved company scope (request value, or the caller's tenant as fallback)
     * @param dedupe    suppress an identical service-request notification from the last few minutes
     */
    @Async
    @Transactional
    public void deliver(CreateNotificationRequest request, Long companyId, boolean dedupe) {
        try {
            if (request.getRecipientId() == null) {
                log.warn("Notification {} dropped: no recipient", request.getType());
                return;
            }
            if (dedupe && request.getServiceRequestId() != null
                    && notificationRepository.existsRecentDuplicate(
                        request.getRecipientId(), request.getServiceRequestId(), request.getType(),
                        request.getTitle(), request.getMessage(),
                        LocalDateTime.now().minusMinutes(DEDUPE_WINDOW_MINUTES))) {
                return;
            }

            User recipient = userRepository.findById(request.getRecipientId()).orElse(null);
            if (recipient == null) {
                log.warn("Notification {} dropped: recipient {} not found", request.getType(), request.getRecipientId());
                return;
            }
            if (!inAppAllowed(recipient.getId(), request.getType())) {
                return;
            }

            Notification notification = buildNotification(request, recipient, companyId);
            notificationRepository.save(notification);
            pushWebSocket(notification, recipient.getId());
            pushMobile(notification, recipient.getId());
        } catch (Exception e) {
            // Async: nobody is waiting for this exception, so make sure it is at least logged.
            log.error("Failed to deliver {} notification to user {}: {}",
                    request.getType(), request.getRecipientId(), e.getMessage(), e);
        }
    }

    /** Missing preference row = defaults (everything on). Non service-request types always deliver. */
    private boolean inAppAllowed(Long userId, NotificationType type) {
        if (type == null || !SERVICE_REQUEST_TYPES.contains(type)) {
            return true;
        }
        return preferenceRepository.findByUserId(userId)
                .map(p -> NEW_REQUEST_TYPES.contains(type) ? p.isInAppOnServiceRequest() : p.isInAppOnStatusChange())
                .orElse(true);
    }

    private Notification buildNotification(CreateNotificationRequest request, User recipient, Long companyId) {
        ServiceRequest sr = request.getServiceRequestId() != null
                ? entityManager.getReference(ServiceRequest.class, request.getServiceRequestId())
                : null;
        // company_id is written through the association; the companyId column mirror is read-only.
        Company company = companyId != null ? entityManager.getReference(Company.class, companyId) : null;
        return Notification.builder()
                .type(request.getType())
                .title(request.getTitle())
                .message(request.getMessage())
                .actionUrl(request.getActionUrl())
                .recipient(recipient)
                .company(company)
                .companyId(companyId)
                .serviceRequest(sr)
                .build();
    }

    private void pushWebSocket(Notification n, Long userId) {
        try {
            messagingTemplate.convertAndSendToUser(
                    userId.toString(),
                    "/queue/notifications",
                    NotificationMapper.toResponse(n));
        } catch (Exception e) {
            // WebSocket push failure is non-critical - client will poll on reconnect
            log.debug("WebSocket push failed for user {}: {}", userId, e.getMessage());
        }
    }

    /** FCM reaches the phone when the app is backgrounded or killed; best-effort, since the row is already persisted. */
    private void pushMobile(Notification n, Long userId) {
        try {
            fcmPushService.push(n, userId);
        } catch (Exception e) {
            log.debug("Push notification failed for user {}: {}", userId, e.getMessage());
        }
    }
}
