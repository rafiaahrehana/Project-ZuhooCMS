package com.zuhoocms.modules.crm.contact;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface ClientContactRepository extends JpaRepository<ClientContact, Long> {

    Optional<ClientContact> findByIdAndCompanyId(Long id, Long companyId);

    List<ClientContact> findByClientIdAndCompanyIdOrderByPrimaryContactDescCreatedAtDesc(Long clientId, Long companyId);

    // Cross-client: the Contacts page isn't scoped to one Client, and ordering comes from the Pageable's Sort, not the method name.
    Page<ClientContact> findByCompanyId(Long companyId, Pageable pageable);

    @Query("SELECT c FROM ClientContact c WHERE c.company.id = :companyId AND " +
           "(LOWER(c.fullName) LIKE LOWER(CONCAT('%', :keyword, '%')) ESCAPE '!' OR " +
           "LOWER(c.email) LIKE LOWER(CONCAT('%', :keyword, '%')) ESCAPE '!' OR " +
           "LOWER(c.client.clientCompanyName) LIKE LOWER(CONCAT('%', :keyword, '%')) ESCAPE '!') AND " +
           "c.deleted = false")
    Page<ClientContact> searchContacts(@Param("companyId") Long companyId, @Param("keyword") String keyword, Pageable pageable);

    boolean existsByEmailAndClientIdAndCompanyIdAndDeletedFalse(String email, Long clientId, Long companyId);

    /** Case-insensitive email uniqueness within one client, optionally excluding the row being edited: {@code update} skipped it, so two contacts shared an address and duplicate detection matched an arbitrary one. */
    @Query("SELECT COUNT(c) > 0 FROM ClientContact c WHERE c.client.id = :clientId " +
           "AND c.company.id = :companyId AND c.deleted = false " +
           "AND LOWER(c.email) = LOWER(:email) AND (:excludeId IS NULL OR c.id <> :excludeId)")
    boolean existsByEmailForClient(@Param("email") String email,
                                   @Param("clientId") Long clientId,
                                   @Param("companyId") Long companyId,
                                   @Param("excludeId") Long excludeId);

    /** Duplicate-detection phone lookup on a digits-only normalisation (see PhoneMatching): raw equality missed "+966 50 123 4567" vs "0501234567". */
    @Query(value = "SELECT * FROM client_contacts c WHERE c.company_id = :companyId AND c.deleted = false "
            + "AND c.phone IS NOT NULL "
            + "AND regexp_replace(c.phone, '[^0-9]', '', 'g') <> '' "
            + "AND regexp_replace(c.phone, '[^0-9]', '', 'g') LIKE ('%' || :suffix) "
            + "ORDER BY c.id ASC LIMIT 1",
           nativeQuery = true)
    Optional<ClientContact> findFirstByNormalisedPhone(@Param("suffix") String suffix,
                                                       @Param("companyId") Long companyId);

    /** Soft-deletes a client's contacts with the client: left live they kept matching in duplicate detection, whose getClient() proxy for a @SQLRestriction-hidden row gave 500s and a 404 "Client not found" on the win path. */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("UPDATE ClientContact c SET c.deleted = true, c.deletedAt = :deletedAt " +
           "WHERE c.client.id = :clientId AND c.company.id = :companyId AND c.deleted = false")
    int softDeleteByClientId(@Param("clientId") Long clientId,
                             @Param("companyId") Long companyId,
                             @Param("deletedAt") java.time.LocalDateTime deletedAt);

    /** The client's primary contact, the address a portal invite goes to; ordered by id because nothing enforces one primary per client. */
    Optional<ClientContact> findFirstByClientIdAndCompanyIdAndPrimaryContactTrueAndDeletedFalseOrderByIdAsc(Long clientId, Long companyId);

    Optional<ClientContact> findFirstByEmailIgnoreCaseAndCompanyIdAndDeletedFalse(String email, Long companyId);

    Optional<ClientContact> findFirstByPhoneAndCompanyIdAndDeletedFalse(String phone, Long companyId);

    @Modifying
    @Query("UPDATE ClientContact c SET c.primaryContact = false WHERE c.client.id = :clientId AND c.company.id = :companyId")
    void clearPrimaryContact(@Param("clientId") Long clientId, @Param("companyId") Long companyId);
}
