package com.zuhoocms.modules.finance.chartofaccounts;

import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface ChartOfAccountRepository extends JpaRepository<ChartOfAccount, Long> {

    Optional<ChartOfAccount> findByCompanyIdAndAccountCode(Long companyId, String accountCode);

    Optional<ChartOfAccount> findByIdAndCompanyId(Long id, Long companyId);

    Page<ChartOfAccount> findByCompanyIdAndTypeAndActiveTrue(Long companyId, AccountType type, Pageable pageable);

    Page<ChartOfAccount> findByCompanyIdAndActive(Long companyId, boolean active, Pageable pageable);

    Page<ChartOfAccount> findByCompanyId(Long companyId, Pageable pageable);

    List<ChartOfAccount> findByCompanyIdAndType(Long companyId, AccountType type);

    List<ChartOfAccount> findByCompanyIdAndActive(Long companyId, boolean active);

    /** Every account in the company, active or not - the Trial Balance has to foot across all of them. */
    List<ChartOfAccount> findByCompanyId(Long companyId);

    /** Row-locks the accounts a posting will touch, ordered by id: a plain read-modify-write lost one of two concurrent balance updates, and the ORDER BY keeps lock order deterministic so overlapping account sets can't deadlock. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT a FROM ChartOfAccount a WHERE a.id IN :ids AND a.companyId = :companyId ORDER BY a.id ASC")
    List<ChartOfAccount> lockByIdsAndCompanyId(@Param("ids") List<Long> ids, @Param("companyId") Long companyId);

    /** Finds an account by code <em>including soft-deleted rows</em>: the (company_id, account_code) unique constraint covers deleted rows, so DefaultAccountResolver must revive rather than re-create. Native because {@code @SQLRestriction("deleted = false")} hides them from JPQL. */
    @Query(value = "SELECT * FROM chart_of_accounts WHERE company_id = :companyId AND account_code = :code LIMIT 1",
           nativeQuery = true)
    Optional<ChartOfAccount> findByCompanyIdAndAccountCodeIncludingDeleted(
        @Param("companyId") Long companyId, @Param("code") String code);

    /** Native INSERT ... ON CONFLICT DO NOTHING so two first-time posters racing to auto-create the same account can't both insert and fail a business transaction on the unique constraint; returns rows actually inserted. */
    @Modifying
    @Query(value = "INSERT INTO chart_of_accounts " +
                   "(company_id, account_code, account_name, type, description, balance, active, " +
                   " is_header_account, is_bank_account, allow_direct_posting, version, created_at, deleted) " +
                   "VALUES (:companyId, :code, :name, :type, 'Auto-created default account', 0, true, " +
                   " false, false, true, 0, now(), false) " +
                   "ON CONFLICT DO NOTHING", nativeQuery = true)
    int insertIfAbsent(@Param("companyId") Long companyId, @Param("code") String code,
                       @Param("name") String name, @Param("type") String type);
}
