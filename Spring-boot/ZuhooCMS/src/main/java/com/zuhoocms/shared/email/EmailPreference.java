package com.zuhoocms.shared.email;

import com.zuhoocms.shared.notification.NotificationPreference;

import java.util.function.Predicate;

/** Which NotificationPreference flag gates an email. ALWAYS = transactional mail that ignores preferences. */
public enum EmailPreference {
    ALWAYS(p -> true),
    LEAVE_UPDATE(NotificationPreference::isEmailOnLeaveUpdate),
    INVOICE(NotificationPreference::isEmailOnInvoice),
    PAYMENT(NotificationPreference::isEmailOnPayment),
    TASK_ASSIGNED(NotificationPreference::isEmailOnTaskAssigned),
    SERVICE_REQUEST(NotificationPreference::isEmailOnServiceRequest),
    STATUS_CHANGE(NotificationPreference::isEmailOnStatusChange);

    private final Predicate<NotificationPreference> flag;

    EmailPreference(Predicate<NotificationPreference> flag) {
        this.flag = flag;
    }

    public boolean allows(NotificationPreference preference) {
        return preference == null || flag.test(preference);
    }
}
