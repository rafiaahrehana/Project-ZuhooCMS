package com.zuhoocms.modules.finance.fixedasset;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount;
import com.zuhoocms.modules.finance.chartofaccounts.DefaultAccountResolver;
import com.zuhoocms.modules.finance.generalledger.GeneralLedgerService;
import com.zuhoocms.modules.finance.generalledger.GlReferenceType;
import com.zuhoocms.modules.finance.generalledger.LedgerLine;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class FixedAssetService {

    private final FixedAssetRepository assetRepository;
    private final DepreciationRunRepository runRepository;
    private final GeneralLedgerService glService;
    // Read-only: used to tell whether an asset's purchase actually reached the ledger.
    private final com.zuhoocms.modules.finance.generalledger.GeneralLedgerRepository glRepository;
    private final DefaultAccountResolver accountResolver;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Transactional
    public FixedAssetDtos.FixedAssetResponse create(FixedAssetDtos.FixedAssetRequest request) {
        authorizationService.checkPermission(PermissionCode.FIXED_ASSET_MANAGE);
        Long companyId = requireCompanyId();

        BigDecimal salvage = request.getSalvageValue() != null ? request.getSalvageValue() : BigDecimal.ZERO;
        if (salvage.compareTo(request.getCost()) >= 0) {
            throw new BadRequestException("Salvage value must be less than cost");
        }

        FixedAsset asset = FixedAsset.builder()
                .companyId(companyId)
                .name(request.getName().trim())
                .assetTag(request.getAssetTag())
                .category(request.getCategory())
                .cost(request.getCost())
                .salvageValue(salvage)
                .usefulLifeMonths(request.getUsefulLifeMonths())
                .acquisitionDate(request.getAcquisitionDate())
                .notes(request.getNotes())
                .status(FixedAssetStatus.ACTIVE)
                .build();
        asset = assetRepository.save(asset);

        // Capitalize the purchase: Dr Fixed Assets / Cr Cash, dated the acquisition date.
        boolean postPurchase = request.getPostPurchaseToLedger() == null || request.getPostPurchaseToLedger();
        if (postPurchase) {
            ChartOfAccount fixedAssets = accountResolver.fixedAssets(companyId);
            ChartOfAccount cash = accountResolver.cash(companyId);
            glService.recordBalancedTransaction(companyId, List.of(
                            LedgerLine.debit(fixedAssets.getId(), asset.getCost()),
                            LedgerLine.credit(cash.getId(), asset.getCost())),
                    "Fixed asset purchase: " + asset.getName(),
                    GlReferenceType.FIXED_ASSET_PURCHASE, asset.getId(), asset.getAssetTag(),
                    asset.getAcquisitionDate() != null ? asset.getAcquisitionDate() : LocalDate.now());
        }

        return FixedAssetDtos.toResponse(asset);
    }

    @Transactional(readOnly = true)
    public Page<FixedAssetDtos.FixedAssetResponse> list(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.FIXED_ASSET_VIEW);
        return assetRepository.findByCompanyId(requireCompanyId(), pageable)
                .map(FixedAssetDtos::toResponse);
    }

    @Transactional
    public FixedAssetDtos.FixedAssetResponse dispose(Long id) {
        authorizationService.checkPermission(PermissionCode.FIXED_ASSET_MANAGE);
        FixedAsset asset = findInTenant(id);
        if (asset.getStatus() == FixedAssetStatus.DISPOSED) {
            throw new BadRequestException("Asset is already disposed");
        }
        // Simple disposal at zero proceeds: write the remaining book value off the books.
        BigDecimal accumulated = asset.getAccumulatedDepreciation() != null ? asset.getAccumulatedDepreciation() : BigDecimal.ZERO;
        BigDecimal bookValue = asset.bookValue();

        Long companyId = asset.getCompanyId();
        ChartOfAccount accumDep = accountResolver.accumulatedDepreciation(companyId);
        ChartOfAccount depExpense = accountResolver.depreciationExpense(companyId);

        // An asset registered with postPurchaseToLedger = false never debited Fixed Assets, so crediting it here would invent a credit that was never debited and unbalance the books.
        boolean purchaseWasPosted = !glRepository.findByCompanyIdAndReferenceTypeAndReferenceId(
                companyId, GlReferenceType.FIXED_ASSET_PURCHASE.name(), asset.getId()).isEmpty();

        List<LedgerLine> lines = new java.util.ArrayList<>();
        if (purchaseWasPosted) {
            // Dr Accumulated Depreciation (this asset's balance) + Dr Depreciation Expense (remaining book value as a loss) / Cr Fixed Assets (full cost).
            ChartOfAccount fixedAssets = accountResolver.fixedAssets(companyId);
            if (accumulated.compareTo(BigDecimal.ZERO) > 0) lines.add(LedgerLine.debit(accumDep.getId(), accumulated));
            if (bookValue.compareTo(BigDecimal.ZERO) > 0) lines.add(LedgerLine.debit(depExpense.getId(), bookValue));
            lines.add(LedgerLine.credit(fixedAssets.getId(), asset.getCost()));
        } else if (accumulated.compareTo(BigDecimal.ZERO) > 0) {
            // Cost was never capitalized but depreciation runs did post, so the only balance to unwind is accumulated depreciation: Dr Accumulated Depreciation / Cr Depreciation Expense, with no loss to recognize.
            lines.add(LedgerLine.debit(accumDep.getId(), accumulated));
            lines.add(LedgerLine.credit(depExpense.getId(), accumulated));
        }
        // Nothing posted and nothing depreciated: the asset never touched the ledger, so a disposal entry would be a no-op batch.
        if (!lines.isEmpty()) {
            glService.recordBalancedTransaction(companyId, lines,
                    "Disposal of fixed asset: " + asset.getName(),
                    // Not FIXED_ASSET_PURCHASE: that showed two "purchase" postings with no way to tell acquisition from disposal.
                    GlReferenceType.FIXED_ASSET_DISPOSAL, asset.getId(), asset.getAssetTag(), LocalDate.now());
        }

        asset.setStatus(FixedAssetStatus.DISPOSED);
        asset = assetRepository.save(asset);
        return FixedAssetDtos.toResponse(asset);
    }

    /** Straight-line depreciation for one calendar month across every ACTIVE asset acquired on or before that month's end; idempotent, a month can only run once. */
    @Transactional
    public FixedAssetDtos.DepreciationRunResponse runDepreciation(int year, int month) {
        authorizationService.checkPermission(PermissionCode.FIXED_ASSET_MANAGE);
        Long companyId = requireCompanyId();
        if (month < 1 || month > 12) throw new BadRequestException("Month must be 1-12");
        // Guard the year before YearMonth.of() so a typo like "20024" is a clear 400, not a 500 deeper in.
        requireValidYear(year);
        if (runRepository.existsByCompanyIdAndYearAndMonth(companyId, year, month)) {
            throw new BadRequestException("Depreciation for " + year + "-" + String.format("%02d", month) + " has already been run");
        }
        YearMonth target = YearMonth.of(year, month);
        if (target.isAfter(YearMonth.now())) {
            throw new BadRequestException("Cannot depreciate a future month");
        }
        // Runs must be consecutive: skipping a month permanently loses its charge and an earlier month applies out of sequence, neither of which the per-month uniqueness constraint catches.
        DepreciationRun lastRun = runRepository.findFirstByCompanyIdOrderByYearDescMonthDesc(companyId).orElse(null);
        if (lastRun != null) {
            YearMonth expected = YearMonth.of(lastRun.getYear(), lastRun.getMonth()).plusMonths(1);
            if (!target.equals(expected)) {
                throw new BadRequestException("Depreciation must be run in order: the next month to run is "
                        + expected.getYear() + "-" + String.format("%02d", expected.getMonthValue())
                        + " (last completed run was " + lastRun.getYear() + "-"
                        + String.format("%02d", lastRun.getMonth()) + ")");
            }
        }
        LocalDate monthEnd = target.atEndOfMonth();

        BigDecimal total = BigDecimal.ZERO;
        int count = 0;
        List<LedgerLine> lines = new java.util.ArrayList<>();
        ChartOfAccount depExpense = accountResolver.depreciationExpense(companyId);
        ChartOfAccount accumDep = accountResolver.accumulatedDepreciation(companyId);

        for (FixedAsset asset : assetRepository.findByCompanyIdAndStatus(companyId, FixedAssetStatus.ACTIVE)) {
            if (asset.getAcquisitionDate() != null && asset.getAcquisitionDate().isAfter(monthEnd)) continue;
            BigDecimal charge = asset.monthlyDepreciation();
            if (charge.compareTo(BigDecimal.ZERO) <= 0) continue;

            asset.setAccumulatedDepreciation(
                    (asset.getAccumulatedDepreciation() != null ? asset.getAccumulatedDepreciation() : BigDecimal.ZERO)
                            .add(charge));
            if (asset.getAccumulatedDepreciation().compareTo(asset.depreciableBase()) >= 0) {
                asset.setStatus(FixedAssetStatus.FULLY_DEPRECIATED);
            }
            assetRepository.save(asset);

            total = total.add(charge);
            count++;
        }

        if (total.compareTo(BigDecimal.ZERO) > 0) {
            lines.add(LedgerLine.debit(depExpense.getId(), total));
            lines.add(LedgerLine.credit(accumDep.getId(), total));
            glService.recordBalancedTransaction(companyId, lines,
                    "Monthly depreciation " + year + "-" + String.format("%02d", month),
                    GlReferenceType.DEPRECIATION, null, year + "-" + String.format("%02d", month), monthEnd);
        }

        DepreciationRun run = DepreciationRun.builder()
                .companyId(companyId)
                .year(year)
                .month(month)
                .totalAmount(total)
                .assetsDepreciated(count)
                .runBy(securityUtil.getCurrentUser().getUsername())
                .runAt(LocalDateTime.now())
                .build();
        run = runRepository.save(run);
        return FixedAssetDtos.toResponse(run);
    }

    @Transactional(readOnly = true)
    public List<FixedAssetDtos.DepreciationRunResponse> listRuns() {
        authorizationService.checkPermission(PermissionCode.FIXED_ASSET_VIEW);
        return runRepository.findByCompanyIdOrderByYearDescMonthDesc(requireCompanyId())
                .stream()
                .map(FixedAssetDtos::toResponse)
                .collect(Collectors.toList());
    }

    private FixedAsset findInTenant(Long id) {
        return assetRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Fixed asset not found: " + id));
    }

    /** Any caller-supplied year must be a plausible accounting year, not a typo'd one. */
    private void requireValidYear(int year) {
        if (year < 2000 || year > 2100) {
            throw new BadRequestException("Year must be between 2000 and 2100");
        }
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }
}
