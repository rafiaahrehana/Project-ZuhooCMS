package com.zuhoocms.shared.notification.device;

import com.zuhoocms.shared.firebase.FirebaseInitializer;
import com.zuhoocms.shared.notification.Notification;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.MessagingErrorCode;
import com.google.firebase.messaging.Message;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

/**
 * Sends a notification to a user's registered devices.
 * Firebase is optional: with no service-account file every send is a no-op falling back to the in-app STOMP push, so a checkout without credentials still runs the backend.
 * Nothing here may fail a caller: push is best-effort and the Notification row is already persisted.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class FcmPushService {

    private final DeviceTokenService deviceTokenService;

    // Injected, not initialised here: Google sign-in needs Firebase too, so startup is owned by FirebaseInitializer.
    private final FirebaseInitializer firebase;

    private boolean enabled() {
        return firebase.isAvailable();
    }

    public void push(Notification notification, Long userId) {

        if (!enabled()) {
            return;
        }

        try {
            List<DeviceToken> devices = deviceTokenService.tokensFor(userId);

            if (devices.isEmpty()) {
                return;
            }

            List<String> dead = new ArrayList<>();

            for (DeviceToken device : devices) {
                if (!send(device, notification)) {
                    dead.add(device.getToken());
                }
            }

            if (!dead.isEmpty()) {
                deviceTokenService.prune(dead);
            }

        } catch (Exception e) {
            log.debug("FCM push failed for user {}: {}", userId, e.getMessage());
        }
    }

    /** @return false when the token is dead and should be pruned. */
    private boolean send(DeviceToken device, Notification notification) {

        // Data-only message: the client builds the system notification itself, so it behaves the same foregrounded or not.
        Message message = Message.builder()
                .setToken(device.getToken())
                .putData("type", notification.getType() != null ? notification.getType().name() : "GENERAL")
                .putData("title", nullSafe(notification.getTitle()))
                .putData("body", nullSafe(notification.getMessage()))
                .putData("actionUrl", nullSafe(notification.getActionUrl()))
                .putData("notificationId", notification.getId() != null
                        ? String.valueOf(notification.getId()) : "")
                .putData("serviceRequestId", notification.getServiceRequest() != null
                        ? String.valueOf(notification.getServiceRequest().getId()) : "")
                .build();

        try {
            FirebaseMessaging.getInstance().send(message);
            return true;

        } catch (FirebaseMessagingException e) {

            MessagingErrorCode code = e.getMessagingErrorCode();

            // The app was uninstalled, or the token was reissued — the row is now junk.
            if (code == MessagingErrorCode.UNREGISTERED || code == MessagingErrorCode.INVALID_ARGUMENT) {
                return false;
            }

            log.debug("FCM send failed ({}): {}", code, e.getMessage());
            return true;

        } catch (Exception e) {
            log.debug("FCM send failed: {}", e.getMessage());
            return true;
        }
    }

    private String nullSafe(String value) {
        return value != null ? value : "";
    }
}
