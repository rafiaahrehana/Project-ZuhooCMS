package com.zuhoocms.modules.hrm.attendance.biometric.data;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface EmployeeBiometricDataRepository extends JpaRepository<EmployeeBiometricData, Long> {

    Optional<EmployeeBiometricData> findByEmployeeIdAndDeviceIdAndBiometricType(Long employeeId, Long deviceId, String type);

    List<EmployeeBiometricData> findByEmployeeId(Long employeeId);

    List<EmployeeBiometricData> findByDeviceIdAndEnrolled(Long deviceId, boolean enrolled);

    long countByDeviceId(Long deviceId);

    /** Un-deletes a soft-deleted row so enrollment can reuse it instead of hitting the unique constraint. */
    @Modifying
    @Query(nativeQuery = true, value = "update employee_biometric_data set deleted = false, deleted_at = null "
            + "where employee_id = :employeeId and device_id = :deviceId and biometric_type = :biometricType and deleted = true")
    int reviveDeleted(@Param("employeeId") Long employeeId,
                      @Param("deviceId") Long deviceId,
                      @Param("biometricType") String biometricType);
}