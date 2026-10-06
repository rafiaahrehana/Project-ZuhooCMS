package com.zuhoocms.shared.ratelimit;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * In-memory sliding-window counter keyed by an arbitrary string (IP, user id, ...).
 * Per-instance by design: N instances multiply the effective limit by N and a restart forgets everything, so a scaled-out deployment needs a shared limiter (WAF/gateway) in front.
 */
public class SlidingWindowRateLimiter {

    /** Past this many tracked keys, stale ones are evicted so the map cannot grow without bound. */
    private static final int MAX_TRACKED_KEYS = 50_000;

    private final Map<String, Deque<Instant>> hits = new ConcurrentHashMap<>();

    /** Records a hit for {@code key}; returns false when it would exceed {@code limit} per {@code window}. */
    public boolean tryAcquire(String key, int limit, Duration window) {
        Instant now = Instant.now();
        Instant cutoff = now.minus(window);
        if (hits.size() > MAX_TRACKED_KEYS) {
            evictStale(cutoff);
        }
        Deque<Instant> q = hits.computeIfAbsent(key, k -> new ArrayDeque<>());
        synchronized (q) {
            while (!q.isEmpty() && q.peekFirst().isBefore(cutoff)) {
                q.pollFirst();
            }
            if (q.size() >= limit) {
                return false;
            }
            q.addLast(now);
            return true;
        }
    }

    private void evictStale(Instant cutoff) {
        hits.entrySet().removeIf(e -> {
            Deque<Instant> q = e.getValue();
            synchronized (q) {
                return q.isEmpty() || q.peekLast().isBefore(cutoff);
            }
        });
    }
}
