package com.zuhoocms.auth.token;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;

import com.fasterxml.jackson.annotation.JsonIgnore;
import java.time.LocalDateTime;

@Entity
@Table(name = "refresh_tokens")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class UserToken extends BaseEntity {

    /**
     * 512, not the default 255. A signed JWT with the claims this app puts in a refresh token was already 227
     * characters, leaving 28 of headroom - so adding a single uuid claim pushed it to about 287 and every insert
     * failed with "value too long for type character varying(255)". That surfaces through the same handler as a
     * duplicate key, i.e. a 409 telling the caller to use a different value, which is indistinguishable from the
     * collision the claim was added to prevent.
     *
     * Widened rather than shrinking the claim: a shorter nonce would fit under 255 today, leave the same cliff for
     * whatever claim is added next, and buy less uniqueness. A unique index over a 512-character varchar is fine.
     */
    @JsonIgnore
    @Column(nullable = false, unique = true, length = 512)
    private String token;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private TokenType tokenType;

    @Column(nullable = false)
    @Builder.Default
    private boolean revoked = false;

    @Column(nullable = false)
    private LocalDateTime expiresAt;

    public boolean isValid() {
        return !revoked && !isExpired();
    }

    public boolean isExpired() {
        return LocalDateTime.now().isAfter(expiresAt);
    }

}
