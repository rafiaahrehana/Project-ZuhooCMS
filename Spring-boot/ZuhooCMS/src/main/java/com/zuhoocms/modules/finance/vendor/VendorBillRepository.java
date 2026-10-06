package com.zuhoocms.modules.finance.vendor;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

public interface VendorBillRepository extends JpaRepository<VendorBill, Long> {

    Optional<VendorBill> findByIdAndCompanyId(Long id, Long companyId);

    /** findByIdAndCompanyId under SELECT ... FOR UPDATE so concurrent approve/pay/cancel serialize; the status re-check after it then sees committed state, which stops a double approval or a payment past the outstanding balance. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT b FROM VendorBill b WHERE b.id = :id AND b.companyId = :companyId")
    Optional<VendorBill> lockByIdAndCompanyId(@Param("id") Long id, @Param("companyId") Long companyId);

    Page<VendorBill> findByCompanyId(Long companyId, Pageable pageable);

    Page<VendorBill> findByCompanyIdAndStatus(Long companyId, VendorBillStatus status, Pageable pageable);

    Page<VendorBill> findByCompanyIdAndVendorId(Long companyId, Long vendorId, Pageable pageable);

    java.util.List<VendorBill> findByCompanyIdAndBalanceAmountGreaterThan(Long companyId, java.math.BigDecimal min);

    boolean existsByVendorIdAndCompanyId(Long vendorId, Long companyId);

    /** APPROVED/PARTIALLY_PAID bills = money the company still owes. */
    @Query("SELECT b FROM VendorBill b WHERE b.companyId = :companyId AND b.status IN :statuses")
    List<VendorBill> findOutstandingByCompanyId(@Param("companyId") Long companyId,
                                                 @Param("statuses") List<VendorBillStatus> statuses);

    @Query("SELECT COALESCE(SUM(b.balanceAmount), 0) FROM VendorBill b " +
           "WHERE b.companyId = :companyId AND b.vendor.id = :vendorId " +
           "AND b.status IN (com.zuhoocms.modules.finance.vendor.VendorBillStatus.APPROVED, " +
           "com.zuhoocms.modules.finance.vendor.VendorBillStatus.PARTIALLY_PAID, " +
           "com.zuhoocms.modules.finance.vendor.VendorBillStatus.OVERDUE)")
    BigDecimal sumOutstandingByVendor(@Param("companyId") Long companyId, @Param("vendorId") Long vendorId);

    @Modifying
    @Query("UPDATE VendorBill b SET b.status = :newStatus WHERE b.dueDate < :currentDate AND b.status IN :oldStatuses")
    int markOverdueBills(
        @Param("currentDate") java.time.LocalDate currentDate,
        @Param("newStatus") VendorBillStatus newStatus,
        @Param("oldStatuses") List<VendorBillStatus> oldStatuses
    );

    @Query("SELECT b FROM VendorBill b WHERE b.dueDate < :currentDate AND b.status IN :oldStatuses AND b.deleted = false")
    List<VendorBill> findNewlyOverdueBills(
        @Param("currentDate") java.time.LocalDate currentDate,
        @Param("oldStatuses") List<VendorBillStatus> oldStatuses
    );

    /**
     * The highest bill sequence in this company and prefix, counting soft-deleted rows.
     *
     * <p>Native, for the same reason as ExpenseRepository.findMaxExpenseSequenceIncludingDeleted: BaseEntity's
     * {@code @SQLRestriction("deleted = false")} applies to JPQL, so the JPQL version of this query could not see a
     * soft-deleted bill whose row still holds {@code UNIQUE (company_id, bill_number)}. Once such a row existed, every
     * later create in that company would propose its number and fail on the constraint, permanently, with no way out
     * through the API.
     */
    @Query(value = """
        SELECT MAX(CASE WHEN SUBSTRING(bill_number FROM :start) ~ '^[0-9]+$'
                        THEN CAST(SUBSTRING(bill_number FROM :start) AS BIGINT) END)
        FROM vendor_bills
        WHERE company_id = :companyId AND bill_number LIKE CONCAT(:prefix, '%')
        """, nativeQuery = true)
    Long findMaxBillSequenceIncludingDeleted(@Param("companyId") Long companyId,
                                             @Param("prefix") String prefix,
                                             @Param("start") int start);

    /** Approved vendor-bill spend against one expense account for budget tracking; totalAmount, not balanceAmount, since postToLedger recognizes at approval. DRAFT is not yet recognized and CANCELLED is reversed. */
    @Query("SELECT COALESCE(SUM(b.totalAmount), 0) FROM VendorBill b " +
           "WHERE b.companyId = :companyId AND b.expenseAccount.accountName = :accountName " +
           "AND b.billDate BETWEEN :start AND :end " +
           "AND b.status IN (com.zuhoocms.modules.finance.vendor.VendorBillStatus.APPROVED, " +
           "com.zuhoocms.modules.finance.vendor.VendorBillStatus.PARTIALLY_PAID, " +
           "com.zuhoocms.modules.finance.vendor.VendorBillStatus.OVERDUE, " +
           "com.zuhoocms.modules.finance.vendor.VendorBillStatus.PAID) " +
           "AND b.deleted = false")
    BigDecimal sumByExpenseAccountNameAndDateRange(@Param("companyId") Long companyId,
                                                    @Param("accountName") String accountName,
                                                    @Param("start") java.time.LocalDate start,
                                                    @Param("end") java.time.LocalDate end);
}
