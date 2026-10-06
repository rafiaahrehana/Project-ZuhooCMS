package com.zuhoocms.modules.hrm.attendance.attendance;

public enum AttendanceMethod {
    MANUAL("Manual - Admin entry"),
    FINGERPRINT("Fingerprint - Biometric"),
    FACIAL("Facial - Face recognition"),
    RFID("RFID - Card based"),
    IRIS("Iris - Iris recognition"),
    GPS("GPS - Location based"),
    NFC("NFC - Phone tap"),
    QR_CODE("QR Code - QR scan"),
    OTHER("Other - Custom method");

    private final String description;

    AttendanceMethod(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    /**
     * True for the methods that assert a hardware check the server did not perform itself: a reader, a camera or a
     * card/phone tap at a terminal. Nothing in this app verifies such a capture (see {@code BiometricMatcher}), so the
     * label is only as good as the caller that supplied it - which is why an untrusted self-service client is not
     * allowed to claim one. {@code MANUAL}, {@code GPS}, {@code QR_CODE} and {@code OTHER} claim no device attestation,
     * so a self-service client may state them freely.
     */
    public boolean isDeviceBacked() {
        return this == FINGERPRINT || this == FACIAL || this == IRIS || this == RFID || this == NFC;
    }
}