package com.zuhoocms.modules.dashboard;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDate;

/** One row per calendar day from PlatformMetricsScheduler, feeding the platform KPI sparklines; upserted (see repository) so a re-run never duplicates today. */
@Entity
@Table(name = "platform_metrics_snapshots",
       indexes = @Index(name = "idx_pms_snapshot_date", columnList = "snapshotDate", unique = true))
@Getter @Setter @Builder
@NoArgsConstructor @AllArgsConstructor
public class PlatformMetricsSnapshot {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private LocalDate snapshotDate;

    private long totalCompanies;
    private long activeCompanies;
    private long trialCompanies;
    private long suspendedCompanies;
    private long pendingVerificationCompanies;
}
