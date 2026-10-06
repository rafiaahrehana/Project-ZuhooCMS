package com.zuhoocms.modules.crm.dashboard;

import com.zuhoocms.enums.LeadStatus;
import com.zuhoocms.modules.crm.activity.CrmActivity;
import com.zuhoocms.modules.crm.activity.CrmActivityRepository;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.crm.lead.LeadRepository;
import com.zuhoocms.modules.crm.opportunity.OpportunityRepository;
import com.zuhoocms.modules.crm.opportunity.OpportunityStage;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.TemporalAdjusters;
import java.util.List;

/** Standalone CRM dashboard summary, deliberately separate from DashboardServiceImpl's widget-registry framework so CRM keeps its own lightweight KPI set. */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class CrmDashboardServiceImpl implements CrmDashboardService {

    private final OpportunityRepository opportunityRepository;
    private final LeadRepository leadRepository;
    private final ClientRepository clientRepository;
    private final CrmActivityRepository crmActivityRepository;
    private final SecurityUtil securityUtil;

    @Override
    public CrmDashboardSummaryResponse getSummary() {
        Long companyId = requireCompanyId();

        LocalDate today = LocalDate.now();
        LocalDate monthStart = today.with(TemporalAdjusters.firstDayOfMonth());

        long totalLeads = leadRepository.countByCompanyId(companyId);
        long convertedLeads = leadRepository.countByCompanyIdAndConvertedTrue(companyId);
        double conversionRate = totalLeads == 0 ? 0.0 : (convertedLeads * 100.0) / totalLeads;

        // LIMIT 5 in the query, not .limit(5) after the fact: the whole follow-up backlog was otherwise hydrated to render a five-row widget.
        List<CrmActivity> upcoming = crmActivityRepository
                .findByCompanyIdAndFollowUpDoneFalseAndFollowUpAtGreaterThanEqualOrderByFollowUpAtAsc(
                        companyId, LocalDateTime.now(), org.springframework.data.domain.PageRequest.of(0, 5));

        List<OpportunityStage> closedStages = List.of(OpportunityStage.WON, OpportunityStage.LOST);

        // One grouped query, reused for the funnel and the won/lost/open figures below; this dashboard used to fire roughly 25 queries per load, one per enum constant.
        List<OpportunityRepository.PipelineStageSummary> pipeline =
                opportunityRepository.summarizePipeline(companyId);

        return CrmDashboardSummaryResponse.builder()
                .pipelineValue(opportunityRepository.sumOpenPipelineValue(companyId))
                .wonThisMonth(opportunityRepository.sumWonAmountBetween(companyId, monthStart, today))
                .qualifiedLeadsCount(leadRepository.countByCompanyIdAndStatusAndConvertedFalse(companyId, LeadStatus.QUALIFIED))
                .conversionRate(Math.round(conversionRate * 10.0) / 10.0)
                .upcomingFollowUps(upcoming.stream().map(this::toUpcomingFollowUp).toList())
                .totalClients(clientRepository.countByCompanyId(companyId))
                .totalLeads(totalLeads)
                .totalOpportunities(opportunityRepository.countByCompanyId(companyId))
                .openOpportunitiesCount(opportunityRepository.countByCompanyIdAndStageNotIn(companyId, closedStages))
                .wonCount(opportunityRepository.countByCompanyIdAndStage(companyId, OpportunityStage.WON))
                .wonValue(opportunityRepository.sumAmountByCompanyIdAndStage(companyId, OpportunityStage.WON))
                .lostCount(opportunityRepository.countByCompanyIdAndStage(companyId, OpportunityStage.LOST))
                .lostValue(opportunityRepository.sumAmountByCompanyIdAndStage(companyId, OpportunityStage.LOST))
                .stageFunnel(stageFunnel(pipeline))
                .leadSources(leadSources(companyId))
                .recentDeals(recentDeals(companyId))
                .build();
    }

    /** Open-stage funnel built from the caller's single summarizePipeline() result; stages missing from it are emitted as explicit zeroes, or the funnel's shape lies about where deals are stuck. */
    private List<CrmDashboardSummaryResponse.StageSlice> stageFunnel(
            List<OpportunityRepository.PipelineStageSummary> pipeline) {

        java.util.Map<OpportunityStage, OpportunityRepository.PipelineStageSummary> byStage =
                new java.util.EnumMap<>(OpportunityStage.class);
        for (OpportunityRepository.PipelineStageSummary row : pipeline) {
            byStage.put(row.getStage(), row);
        }

        java.math.BigDecimal total = java.math.BigDecimal.ZERO;
        for (OpportunityStage stage : OpportunityStage.values()) {
            if (stage.isClosed()) continue;
            OpportunityRepository.PipelineStageSummary row = byStage.get(stage);
            total = total.add(row != null ? orZero(row.getTotalAmount()) : java.math.BigDecimal.ZERO);
        }

        List<CrmDashboardSummaryResponse.StageSlice> slices = new java.util.ArrayList<>();
        for (OpportunityStage stage : OpportunityStage.values()) {
            if (stage.isClosed()) continue;
            OpportunityRepository.PipelineStageSummary row = byStage.get(stage);
            java.math.BigDecimal value = row != null ? orZero(row.getTotalAmount()) : java.math.BigDecimal.ZERO;
            slices.add(CrmDashboardSummaryResponse.StageSlice.builder()
                    .stage(stage.name())
                    .count(row != null ? row.getDealCount() : 0L)
                    .value(value)
                    .percent(total.signum() > 0
                            ? value.multiply(java.math.BigDecimal.valueOf(100))
                                .divide(total, 0, java.math.RoundingMode.HALF_UP).intValue()
                            : 0)
                    .build());
        }
        return slices;
    }

    /** One GROUP BY source query in place of one count per LeadSource constant. */
    private List<CrmDashboardSummaryResponse.SourceSlice> leadSources(Long companyId) {
        return leadRepository.countByCompanyIdGroupedBySource(companyId).stream()
                .filter(row -> row.getSource() != null && row.getTotal() != null && row.getTotal() > 0)
                .map(row -> CrmDashboardSummaryResponse.SourceSlice.builder()
                        .source(row.getSource().name())
                        .count(row.getTotal())
                        .build())
                .sorted((a, b) -> Long.compare(b.getCount(), a.getCount()))
                .toList();
    }

    private List<CrmDashboardSummaryResponse.DealItem> recentDeals(Long companyId) {
        return opportunityRepository.findTop5ByCompanyIdOrderByUpdatedAtDesc(companyId).stream()
                .map(o -> CrmDashboardSummaryResponse.DealItem.builder()
                        .id(o.getId())
                        .name(o.getName())
                        .clientName(o.getClient() != null ? o.getClient().getClientCompanyName() : null)
                        .amount(o.getAmount())
                        .stage(o.getStage() != null ? o.getStage().name() : null)
                        .build())
                .toList();
    }

    private java.math.BigDecimal orZero(java.math.BigDecimal v) {
        return v == null ? java.math.BigDecimal.ZERO : v;
    }

    private CrmDashboardSummaryResponse.UpcomingFollowUp toUpcomingFollowUp(CrmActivity activity) {
        String relatedName = activity.getLead() != null ? activity.getLead().getContactName()
                : activity.getOpportunity() != null ? activity.getOpportunity().getName()
                : activity.getClient() != null ? activity.getClient().getClientCompanyName()
                : null;
        return CrmDashboardSummaryResponse.UpcomingFollowUp.builder()
                .activityId(activity.getId())
                .subject(activity.getSubject())
                .followUpAt(activity.getFollowUpAt())
                .relatedName(relatedName)
                .build();
    }

    private Long requireCompanyId() {
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context found");
        }
        return companyId;
    }
}
