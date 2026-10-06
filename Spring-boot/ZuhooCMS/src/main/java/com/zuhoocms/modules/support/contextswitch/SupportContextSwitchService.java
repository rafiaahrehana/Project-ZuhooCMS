package com.zuhoocms.modules.support.contextswitch;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.time.LocalDateTime;
import java.util.List;

public interface SupportContextSwitchService {
    SupportContextSwitchResponse switchContext(SupportContextSwitchRequest request, String ipAddress, String userAgent);
    void endContextSwitch(Long contextSwitchId);
    SupportContextSwitchResponse getActiveContextSwitch(Long supportAgentId);
    Page<SupportContextSwitchResponse> getContextSwitchHistory(Long supportAgentId, Pageable pageable);
    List<SupportContextSwitchResponse> getActiveContextSwitches();
    SupportContextSwitchResponse getById(Long id);

    // Auto-expiry (SupportContextSwitchExpiryScheduler): list stale ids, end each in its own transaction.
    List<Long> findStaleActiveIds(LocalDateTime cutoff);
    boolean expireIfStale(Long contextSwitchId, LocalDateTime cutoff);
}
