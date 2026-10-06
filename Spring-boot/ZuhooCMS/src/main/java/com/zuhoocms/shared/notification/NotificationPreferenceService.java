package com.zuhoocms.shared.notification;

public interface NotificationPreferenceService {

    /** Auto-creates the row when missing. */
    NotificationPreferenceResponse getForCurrentUser();

    /** Full replacement, not a partial update. */
    NotificationPreferenceResponse update(UpdateNotificationPreferenceRequest request);

    NotificationPreferenceResponse resetToDefaults();

    /** Internal: called on user activation. */
    void createDefaultsForUser(Long userId);

}
