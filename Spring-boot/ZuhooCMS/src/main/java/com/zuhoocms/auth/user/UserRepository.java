package com.zuhoocms.auth.user;

import com.zuhoocms.auth.role.enums.Role;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface UserRepository extends JpaRepository<User, Long> {

    Optional<User> findByEmail(String email);

    boolean existsByEmail(String email);

    /** Case-insensitive, and counts soft-deleted rows too - they still hold the unique email. */
    @Query(value = "select exists(select 1 from users where lower(email) = lower(:email))", nativeQuery = true)
    boolean existsAnyByEmailIgnoreCase(@org.springframework.data.repository.query.Param("email") String email);

    Optional<User> findByIdAndDeletedFalse(Long id);

    Page<User> findByRole(Role role, Pageable pageable);

    Page<User> findByRoleIn(List<Role> roles, Pageable pageable);

    long countByRoleIn(List<Role> roles);

    @Query("SELECT u FROM User u WHERE u.deleted = true AND u.deletedAt < :cutoff")
    List<User> findDeletedBefore(LocalDateTime cutoff);

    /** Must be called before soft-deleting a CustomRole; stands in for the CascadeType.SET_NULL that JPA does not have. */
    @org.springframework.data.jpa.repository.Modifying
    @Query("UPDATE User u SET u.customRole = null WHERE u.customRole.id = :roleId")
    void clearCustomRoleForAllUsers(@org.springframework.data.repository.query.Param("roleId") Long roleId);

    long countByCustomRoleId(Long customRoleId);
}
