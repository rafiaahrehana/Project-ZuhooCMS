package com.zuhoocms.modules.hrm.attendance.biometric.data;

import java.util.List;

public interface EmployeeBiometricService {

    BiometricDataResponse enrollEmployee(BiometricEnrollmentRequest request);
    BiometricDataResponse getEnrollment(Long employeeId, Long deviceId);
    // Lookup by the enrollment record's own id, unlike getEnrollment which keys on employeeId+deviceId; backs GET /{id}.
    BiometricDataResponse getById(Long id);
    List<BiometricDataResponse> getByEmployee(Long employeeId);

    boolean verifyBiometric(Long employeeId, Long deviceId, String template, double threshold);
    // Overload keyed by the enrollment id, for POST /{id}/verify, which has no employeeId+deviceId.
    boolean verifyBiometric(Long id, String template, double threshold);

    void updateEnrollmentStatus(Long id, boolean enrolled);
    void updateLastVerified(Long id);
    void recordSuccessfulMatch(Long id);
    void recordFailedMatch(Long id);

    BiometricDataResponse delete(Long id);
}