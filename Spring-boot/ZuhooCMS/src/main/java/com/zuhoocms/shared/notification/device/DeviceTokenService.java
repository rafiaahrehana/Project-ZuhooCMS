package com.zuhoocms.shared.notification.device;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
@Slf4j
public class DeviceTokenService {

    private final DeviceTokenRepository repository;
    private final SecurityUtil securityUtil;

    /** Upsert, not insert: FCM reissues tokens and the same token can belong to another account after a reinstall, so an existing row is reassigned to the current user. */
    @Transactional
    public void register(RegisterDeviceTokenRequest request) {

        User user = securityUtil.getCurrentUser();
        Long companyId = securityUtil.getCurrentCompanyId();

        DeviceToken deviceToken = repository.findByToken(request.getToken())
                .orElseGet(DeviceToken::new);

        deviceToken.setToken(request.getToken());
        deviceToken.setPlatform(request.getPlatform());
        deviceToken.setUser(user);
        deviceToken.setCompanyId(companyId);
        deviceToken.setLastSeenAt(LocalDateTime.now());

        repository.save(deviceToken);
    }

    /** Sign-out: someone else's token is reported exactly like a missing one (404), so tokens can't be probed or used to silence another user's device. */
    @Transactional
    public void unregister(String token) {
        Long userId = securityUtil.getCurrentUser().getId();
        DeviceToken deviceToken = repository.findByToken(token)
                .filter(t -> t.getUser() != null && userId.equals(t.getUser().getId()))
                .orElseThrow(() -> new ResourceNotFoundException("Device token not found"));
        repository.delete(deviceToken);
    }

    @Transactional(readOnly = true)
    public List<DeviceToken> tokensFor(Long userId) {
        return repository.findByUserId(userId);
    }

    /** Drops tokens FCM has told us are dead — see FcmPushService. */
    @Transactional
    public void prune(List<String> tokens) {
        for (String token : tokens) {
            repository.deleteByToken(token);
        }
        log.debug("Pruned {} dead device token(s)", tokens.size());
    }
}
