package com.zuhoocms.auth.token;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.Optional;

public interface TokenRepository extends JpaRepository<UserToken, Long> {

    Optional<UserToken> findByToken(String token);

    @Query("SELECT t FROM UserToken t WHERE t.token = :token AND t.tokenType = :type")
    Optional<UserToken> findByTokenAndType(@Param("token") String token, @Param("type") TokenType type);

    @Transactional
    @Modifying
    @Query("DELETE FROM UserToken t WHERE t.user.id = :userId")
    void deleteByUserId(@Param("userId") Long userId);

    @Transactional
    @Modifying
    @Query("""
        UPDATE UserToken t
        SET t.revoked = true
        WHERE t.user.id = :userId
        AND t.revoked = false
    """)
    void revokeAllByUserId(@Param("userId") Long userId);

    @Transactional
    @Modifying
    @Query("""
        UPDATE UserToken t
        SET t.revoked = true
        WHERE t.user.id = :userId
        AND t.tokenType = :type
        AND t.revoked = false
    """)
    void revokeAllByUserIdAndType(@Param("userId") Long userId, @Param("type") TokenType type);

    @Transactional
    @Modifying
    @Query("""
        DELETE FROM UserToken t
        WHERE t.expiresAt < :cutoff
    """)
    void deleteExpiredBefore(@Param("cutoff") LocalDateTime cutoff);

    /** Bulk-revokes REFRESH tokens when a company is suspended/deactivated (see CompanyServiceImpl.changeStatus); otherwise its users keep calling /refresh and bypass the suspension. */
    @Transactional
    @Modifying
    @Query("""
        UPDATE UserToken t
        SET t.revoked = true
        WHERE t.user.id IN :userIds
        AND t.tokenType = :type
        AND t.revoked = false
    """)
    void revokeAllByUserIdInAndType(@Param("userIds") Collection<Long> userIds, @Param("type") TokenType type);

}
