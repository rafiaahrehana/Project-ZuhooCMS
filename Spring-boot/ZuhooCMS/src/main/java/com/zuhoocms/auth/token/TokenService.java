package com.zuhoocms.auth.token;

import com.zuhoocms.auth.user.User;

public interface TokenService {

    String createRefreshToken(User user);

    User validateRefreshToken(String token);

    void revokeRefreshToken(String token);

    void revokeAllRefreshTokens(User user);

    void deleteExpiredTokens();
}

