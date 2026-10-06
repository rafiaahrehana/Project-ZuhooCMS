package com.zuhoocms.shared.email;

import com.zuhoocms.shared.notification.AfterCommit;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Builds email content and hands delivery to EmailDeliveryWorker; every path except sendClientPortalInviteEmail sends after commit (AfterCommit) via the worker's @Async retries.
 * Values passed in here are plain text; EmailTemplate escapes them.
 */
@Service
public class EmailServiceImpl implements EmailService {

    private final EmailTemplate template;
    private final EmailBranding brandingHelper;
    private final EmailDeliveryWorker worker;
    private final String frontendUrl;

    public EmailServiceImpl(
            EmailTemplate template,
            EmailBranding brandingHelper,
            EmailDeliveryWorker worker,
            @Value("${app.frontend-url}") String frontendUrl) {
        this.template = template;
        this.brandingHelper = brandingHelper;
        this.worker = worker;
        this.frontendUrl = EmailBranding.primaryFrontendUrl(frontendUrl);
    }

    private String link(String path) {
        return frontendUrl + path;
    }

    private void enqueue(String to, String subject, String html, String templateName,
                         Long companyId, EmailPreference preference) {
        AfterCommit.run(() -> worker.deliverAsync(to, subject, html, templateName, companyId, preference));
    }

    private static String nz(String s) {
        return s == null ? "" : s;
    }

    @Override
    public void send(String to, String subject, String html) {
        // Caller supplies the finished HTML; it is responsible for escaping its own content.
        enqueue(to, subject, html, "Custom", null, EmailPreference.ALWAYS);
    }

    @Override
    public void sendVerificationEmail(String to, String name, String code) {
        // 15 is display text only and must match AuthServiceImpl.EMAIL_VERIFY_CODE_MINUTES; expiry is enforced against emailVerificationCodeExpiresAt.
        String html = EmailTemplate.buildVerificationCodeTemplate(name, code, 15, brandingHelper.getPlatformBranding());
        enqueue(to, "Verify your businessos account", html, "VerificationEmail", null, EmailPreference.ALWAYS);
    }

    @Override
    public void sendPasswordResetEmail(String to, String name, String code) {
        // 15 is display text only and must match AuthServiceImpl.PASSWORD_RESET_MINS; expiry is enforced against passwordResetCodeExpiresAt.
        String html = EmailTemplate.buildPasswordResetCodeTemplate(name, code, 15, brandingHelper.getPlatformBranding());
        enqueue(to, "Reset your businessos password", html, "PasswordResetEmail", null, EmailPreference.ALWAYS);
    }

    @Override
    public void sendWelcomeCompanyEmail(String to, String name, String companyName) {
        String html = template.build(brandingHelper.getPlatformBranding(), "Welcome to businessos",
                "Welcome, " + nz(name) + "! " + nz(companyName) + " is now active on businessos.",
                "Go to Dashboard", link("/dashboard"));
        enqueue(to, "Welcome to businessos — " + nz(companyName) + " is live!", html, "WelcomeCompanyEmail", null, EmailPreference.ALWAYS);
    }

    @Override
    public void sendSubscriptionPurchasedEmail(String to, String name, String companyName) {
        String html = template.build(brandingHelper.getPlatformBranding(), "Subscription activated",
                "Hi " + nz(name) + ", your subscription for " + nz(companyName) + " is active.",
                "View Billing", link("/settings/billing"));
        enqueue(to, "Subscription activated for " + nz(companyName), html, "SubscriptionPurchased", null, EmailPreference.ALWAYS);
    }

    @Override
    public void sendSubscriptionExpiryReminder(String to, String name, String companyName, int daysLeft) {
        String message = daysLeft == 0
                ? "Your subscription for " + nz(companyName) + " expires today."
                : "Your subscription for " + nz(companyName) + " expires in " + daysLeft + " days.";
        String html = template.build(brandingHelper.getPlatformBranding(), "Subscription expiring soon",
                message, "Upgrade Now", link("/settings/billing"));
        enqueue(to, "Your businessos subscription expires soon", html, "SubscriptionExpiryReminder", null, EmailPreference.ALWAYS);
    }

    @Override
    public void sendSubscriptionSuspendedEmail(String to, String name, String companyName) {
        String html = template.build(brandingHelper.getPlatformBranding(), "Account suspended",
                "Hi " + nz(name) + ", your account for " + nz(companyName) + " has been suspended.",
                "Reactivate Now", link("/settings/billing"));
        enqueue(to, "Your businessos account is suspended", html, "SubscriptionSuspended", null, EmailPreference.ALWAYS);
    }

    @Override
    public void sendLicenseExpiryReminder(String to, String name, String softwareName, java.time.LocalDate expiryDate, long daysLeft) {
        String message = "Hi " + nz(name) + ", your " + nz(softwareName) + " license expires on " + expiryDate
                + " (" + daysLeft + " day" + (daysLeft == 1 ? "" : "s") + " left). Renew or cancel before it lapses.";
        String html = template.build(brandingHelper.getPlatformBranding(), "License expiring soon",
                message, "Review License", link("/itam/software"));
        enqueue(to, nz(softwareName) + " license expires soon", html, "LicenseExpiryReminder", null, EmailPreference.ALWAYS);
    }

    @Override
    public void sendLicenseExpiredEmail(String to, String name, String softwareName, java.time.LocalDate expiryDate, int seatsUsed) {
        String message = "Hi " + nz(name) + ", your " + nz(softwareName) + " license expired on " + expiryDate
                + ". " + seatsUsed + " assigned seat(s) may lose access until it's renewed.";
        String html = template.build(brandingHelper.getPlatformBranding(), "License expired",
                message, "Renew Now", link("/itam/software"));
        enqueue(to, nz(softwareName) + " license has expired", html, "LicenseExpired", null, EmailPreference.ALWAYS);
    }

    @Override
    public void sendWarrantyExpiryReminder(String to, String name, String assetName, java.time.LocalDate expiryDate, long daysLeft) {
        String message = "Hi " + nz(name) + ", the warranty on " + nz(assetName) + " expires on " + expiryDate
                + " (" + daysLeft + " day" + (daysLeft == 1 ? "" : "s") + " left). Arrange a replacement or extended coverage before it lapses.";
        String html = template.build(brandingHelper.getPlatformBranding(), "Warranty expiring soon",
                message, "Review Hardware", link("/itam/hardware"));
        enqueue(to, nz(assetName) + " warranty expires soon", html, "WarrantyExpiryReminder", null, EmailPreference.ALWAYS);
    }

    @Override
    public void sendWarrantyExpiredEmail(String to, String name, String assetName, java.time.LocalDate expiryDate) {
        String message = "Hi " + nz(name) + ", the warranty on " + nz(assetName) + " expired on " + expiryDate
                + ". Repairs or replacements will no longer be covered.";
        String html = template.build(brandingHelper.getPlatformBranding(), "Warranty expired",
                message, "Review Hardware", link("/itam/hardware"));
        enqueue(to, nz(assetName) + " warranty has expired", html, "WarrantyExpired", null, EmailPreference.ALWAYS);
    }

    @Override
    public void sendEmployeeWelcomeEmail(String to, String name, EmailBranding.Data branding) {
        String html = template.build(branding, "Welcome aboard",
                "Welcome to " + nz(branding.getCompanyName()) + ", " + nz(name) + "!", "Login to Portal", link("/login"));
        enqueue(to, "Welcome to " + nz(branding.getCompanyName()), html, "EmployeeWelcome", branding.getCompanyId(), EmailPreference.ALWAYS);
    }

    @Override
    public void sendOfferLetterEmail(String to, String name, EmailBranding.Data branding) {
        String html = EmailTemplate.buildOfferLetterTemplate(name, branding);
        enqueue(to, "Offer Letter from " + nz(branding.getCompanyName()), html, "OfferLetter", branding.getCompanyId(), EmailPreference.ALWAYS);
    }

    @Override
    public void sendInterviewScheduledEmail(String to, String name, String interviewDetails, EmailBranding.Data branding) {
        String message = "Hi " + nz(name) + ", your interview with " + nz(branding.getCompanyName()) + " has been scheduled. " + nz(interviewDetails);
        String html = template.build(branding, "Interview Scheduled", message, "View Details", link(""));
        enqueue(to, "Interview Scheduled - " + nz(branding.getCompanyName()), html, "InterviewScheduled", branding.getCompanyId(), EmailPreference.ALWAYS);
    }

    @Override
    public void sendLeaveApprovalEmail(String to, String name, EmailBranding.Data branding) {
        String html = template.build(branding, "Leave Approved",
                "Hi " + nz(name) + ", your leave request has been approved.", "View Leaves", link("/leaves"));
        enqueue(to, "Leave Approved", html, "LeaveApproval", branding.getCompanyId(), EmailPreference.LEAVE_UPDATE);
    }

    @Override
    public void sendLeaveRejectionEmail(String to, String name, String reason, EmailBranding.Data branding) {
        String message = "Hi " + nz(name) + ", your leave request has been rejected."
                + (reason != null && !reason.isBlank() ? " Reason: " + reason : "");
        String html = template.build(branding, "Leave Request Rejected", message, "View Leaves", link("/leaves"));
        enqueue(to, "Leave Request Rejected", html, "LeaveRejection", branding.getCompanyId(), EmailPreference.LEAVE_UPDATE);
    }

    @Override
    public void sendSalaryRevisionEmail(String to, String name, EmailBranding.Data branding) {
        String html = EmailTemplate.buildSalaryRevisionTemplate(name, branding);
        enqueue(to, "Salary Revision Notification", html, "salary-revision", branding.getCompanyId(), EmailPreference.STATUS_CHANGE);
    }

    @Override
    public void sendPayrollEmail(String to, String name, EmailBranding.Data branding) {
        String html = template.build(branding, "Your Payslip is Ready",
                "Hi " + nz(name) + ", your payslip is ready.", "View Payslip", link("/payroll"));
        enqueue(to, "Your Payslip is Ready", html, "Payroll", branding.getCompanyId(), EmailPreference.STATUS_CHANGE);
    }

    @Override
    public void sendInvoiceEmail(String to, String name, EmailBranding.Data branding) {
        String html = template.build(branding, "New Invoice",
                "Hi " + nz(name) + ", a new invoice has been generated.", "View Invoice", link("/invoices"));
        enqueue(to, "New Invoice from " + nz(branding.getCompanyName()), html, "Invoice", branding.getCompanyId(), EmailPreference.INVOICE);
    }

    @Override
    public void sendTicketAssignedEmail(String to, String name, String ticketTitle, EmailBranding.Data branding) {
        String html = EmailTemplate.buildTicketAssignedTemplate(name, ticketTitle, branding);
        enqueue(to, "Ticket Assigned: " + nz(ticketTitle), html, "ticket-assigned", branding.getCompanyId(), EmailPreference.TASK_ASSIGNED);
    }

    @Override
    public void sendClientWelcomeEmail(String to, String name, EmailBranding.Data branding) {
        String html = template.build(branding, "Welcome to the client portal",
                "Hi " + nz(name) + ", welcome to the " + nz(branding.getCompanyName()) + " client portal.",
                "Access Portal", link("/client-login"));
        enqueue(to, "Welcome to " + nz(branding.getCompanyName()), html, "ClientWelcome", branding.getCompanyId(), EmailPreference.ALWAYS);
    }

    // Deliberately synchronous: on the @Async path the failure is lost on another thread and staff are told the client was emailed when nothing was sent.
    @Override
    public void sendClientPortalInviteEmail(String to, String name, String token, EmailBranding.Data branding) {
        // Reuses the reset-password screen: the action is identical, only the wording differs.
        String inviteLink = link("/auth/reset-password?token=" + java.net.URLEncoder.encode(nz(token), java.nio.charset.StandardCharsets.UTF_8));
        String body = "Hi " + nz(name) + ", " + nz(branding.getCompanyName())
                + " has invited you to the client portal. Set your password to activate your account. "
                + "This link expires in 7 days.";
        String html = template.build(branding, "You're invited", body, "Set Your Password", inviteLink);
        worker.deliverNow(to, "You're invited to the " + nz(branding.getCompanyName()) + " client portal", html,
                "ClientPortalInvite", branding.getCompanyId());
    }

    @Override
    public void sendTerminationEmail(String to, String name, EmailBranding.Data branding) {
        String html = EmailTemplate.buildTerminationTemplate(name, branding);
        enqueue(to, "Offboarding Notification", html, "termination", branding.getCompanyId(), EmailPreference.ALWAYS);
    }

    @Override
    public void sendPerformanceReviewEmail(String to, String name, EmailBranding.Data branding) {
        String html = EmailTemplate.buildPerformanceReviewTemplate(name, branding);
        enqueue(to, "Performance Review Scheduled", html, "performance-review", branding.getCompanyId(), EmailPreference.ALWAYS);
    }

    @Override
    public void sendPaymentReceiptEmail(String to, String name, String invoiceNumber, String amount, EmailBranding.Data branding) {
        String html = EmailTemplate.buildPaymentReceiptTemplate(name, invoiceNumber, amount, branding);
        enqueue(to, "Payment Receipt: " + nz(invoiceNumber), html, "payment-receipt", branding.getCompanyId(), EmailPreference.PAYMENT);
    }

    @Override
    public void sendExpenseStatusEmail(String to, String name, String expenseTitle, String status, EmailBranding.Data branding) {
        String html = EmailTemplate.buildExpenseStatusTemplate(name, expenseTitle, status, branding);
        enqueue(to, "Expense Request " + nz(status) + ": " + nz(expenseTitle), html, "expense-status", branding.getCompanyId(), EmailPreference.ALWAYS);
    }

    @Override
    public void sendTicketCreatedEmail(String to, String name, String ticketTitle, EmailBranding.Data branding) {
        String html = EmailTemplate.buildTicketCreatedTemplate(name, ticketTitle, branding);
        enqueue(to, "Support Ticket Received: " + nz(ticketTitle), html, "ticket-created", branding.getCompanyId(), EmailPreference.SERVICE_REQUEST);
    }

    @Override
    public void sendTicketResolvedEmail(String to, String name, String ticketTitle, EmailBranding.Data branding) {
        String html = EmailTemplate.buildTicketResolvedTemplate(name, ticketTitle, branding);
        enqueue(to, "Support Ticket Resolved: " + nz(ticketTitle), html, "ticket-resolved", branding.getCompanyId(), EmailPreference.STATUS_CHANGE);
    }

    @Override
    public void sendServiceRequestPaymentReminderEmail(String to, String name, String requestTitle, EmailBranding.Data branding) {
        String html = template.build(branding, "Payment Reminder",
                "Hi " + nz(name) + ", this is a reminder to complete the payment for your service request '" + nz(requestTitle)
                        + "'. Your request will be automatically cancelled if not paid within 24 hours.",
                "Pay Now", link("/invoices"));
        enqueue(to, "Action Required: Payment Reminder for Service Request - " + nz(requestTitle), html,
                "service-request-reminder", branding.getCompanyId(), EmailPreference.PAYMENT);
    }

    @Override
    public void sendServiceRequestCancelledEmail(String to, String name, String requestTitle, EmailBranding.Data branding) {
        String html = template.build(branding, "Service Request Cancelled",
                "Hi " + nz(name) + ", your service request '" + nz(requestTitle)
                        + "' has been automatically cancelled because payment was not received in time. Please submit a new request if you'd still like this work done.",
                "View Requests", link("/service-requests"));
        enqueue(to, "Service Request Cancelled - " + nz(requestTitle), html,
                "service-request-cancelled", branding.getCompanyId(), EmailPreference.STATUS_CHANGE);
    }

    @Override
    public void sendAnnouncementEmail(String to, String name, String title, String body, EmailBranding.Data branding) {
        String safeBody = nz(body);
        String message = "Hi " + nz(name) + ", " + nz(branding.getCompanyName()) + " posted a new announcement: \"" + nz(title) + "\". "
                + (safeBody.length() > 300 ? safeBody.substring(0, 297) + "..." : safeBody);
        String html = template.build(branding, "New Announcement", message, "View Announcement", link("/hrm/announcements"));
        enqueue(to, "Announcement: " + nz(title), html, "Announcement", branding.getCompanyId(), EmailPreference.ALWAYS);
    }
}
