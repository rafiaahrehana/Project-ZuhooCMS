package com.zuhoocms.modules.ai.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/** One fixed-window AI quota counter, e.g. scope "company:42" for a day or "user:7" for an hour; only AiRateCounterRepository#tryIncrement changes it, so check and increment stay one atomic statement. */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(
    name = "ai_rate_counters",
    uniqueConstraints = @UniqueConstraint(name = "uq_ai_rate_counter_scope_window",
        columnNames = {"scope_key", "window_start"})
)
public class AiRateCounter {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "scope_key", nullable = false, length = 64)
    private String scopeKey;

    @Column(name = "window_start", nullable = false)
    private LocalDateTime windowStart;

    @Column(name = "request_count", nullable = false)
    private int requestCount;
}
