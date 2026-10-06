package com.zuhoocms.modules.finance.expense;
import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount;
import com.zuhoocms.modules.finance.chartofaccounts.DefaultAccountResolver;
import com.zuhoocms.modules.finance.generalledger.DocumentNumberService;
import com.zuhoocms.modules.finance.generalledger.GeneralLedgerService;
import com.zuhoocms.modules.finance.generalledger.GlReferenceType;
import com.zuhoocms.modules.finance.generalledger.LedgerLine;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.modules.ai.enums.AiFeature;
import com.zuhoocms.modules.ai.prompt.ExpenseEntryPromptBuilder;
import com.zuhoocms.modules.ai.service.AiService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Service("financeExpenseService")
@RequiredArgsConstructor
public class ExpenseServiceImpl implements ExpenseService {

    private static final ObjectMapper COMPOSE_MAPPER = new ObjectMapper();

    private final ExpenseRepository expenseRepository;
    private final EmployeeRepository employeeRepository;
    private final UserRepository userRepository;
    private final SecurityUtil securityUtil;
    private final GeneralLedgerService glService;
    private final DocumentNumberService documentNumberService;
    private final DefaultAccountResolver accountResolver;
    private final AuthorizationService authorizationService;
    private final com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccountRepository coaRepository;
    private final com.zuhoocms.modules.finance.budget.BudgetService budgetService;
    private final com.zuhoocms.modules.finance.period.PeriodLockChecker periodLockChecker;
    private final AiService aiService;

    /** Resolves + validates an optional COA expense account (must exist in-tenant and be EXPENSE type). */
    private ChartOfAccount resolveExpenseAccount(Long companyId, Long accountId) {
        if (accountId == null) return null;
        ChartOfAccount account = coaRepository.findByIdAndCompanyId(accountId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Expense account not found: " + accountId));
        if (account.getType() != com.zuhoocms.modules.finance.chartofaccounts.AccountType.EXPENSE) {
            throw new BadRequestException("Account " + account.getAccountCode() + " is " + account.getType()
                    + " - expenses must post to an EXPENSE account");
        }
        return account;
    }

    /** The DTO's @DecimalMin only runs behind a controller's @Valid; internal callers like the AI agent's submit_expense tool build the DTO directly, so enforce it here too. */
    private static void requirePositiveAmount(java.math.BigDecimal amount) {
        if (amount == null || amount.signum() <= 0) {
            throw new BadRequestException("Expense amount must be greater than zero");
        }
    }

    @Override
    @Transactional
    public ExpenseResponse create(ExpenseRequest request) {
        // Without this check anyone merely authenticated into the tenant could post an expense claim.
        authorizationService.checkPermission(PermissionCode.EXPENSE_CREATE);
        requirePositiveAmount(request.getAmount());
        Long companyId = securityUtil.getCurrentCompanyId();
        User currentUser = securityUtil.getCurrentUser();
        if (currentUser == null) {
            throw new ResourceNotFoundException("User not authenticated");
        }
        Long currentUserId = currentUser.getId();

        Employee employee = null;
        Long reqEmployeeId = request.getEmployeeId();
        if (reqEmployeeId != null) {
            employee = employeeRepository.findByIdAndCompanyId(reqEmployeeId, companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Employee not found"));
        } else if (currentUser.isTenantUser()) {
            // Only the record for the ACTIVE company: a user with an employee record in two tenants would
            // otherwise file a company-A claim against their company-B employee row.
            employee = employeeRepository.findByUserId(currentUserId)
                    .filter(e -> e.getCompany() != null && e.getCompany().getId().equals(companyId))
                    .orElse(null);
        }



        String expenseNumber = generateExpenseNumber(companyId);

        Expense expense = Expense.builder()
                .companyId(companyId)
                .expenseNumber(expenseNumber)
                .title(request.getTitle() != null ? request.getTitle() : "Expense " + expenseNumber)
                .currency(request.getCurrency() != null ? request.getCurrency() : "BDT")
                .submittedBy(employee)
                // Recorded so maker-checker can also bar whoever keyed the expense in from approving it - see approveExpense().
                .createdBy(currentUser)
                .description(request.getDescription())
                .amount(request.getAmount())
                .vendorName(request.getVendorName())
                .category(request.getCategory())
                .expenseAccount(resolveExpenseAccount(companyId, request.getExpenseAccountId()))
                .expenseDate(request.getExpenseDate())
                .receiptUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getReceiptUrl()))
                .status(ExpenseStatus.PENDING)
                .submittedAt(LocalDateTime.now())
                .notes(request.getNotes())
                .referenceNumber(request.getReferenceNumber())
                .build();

        expense = expenseRepository.save(expense);
        return ExpenseMapper.toResponse(expense);
    }

    @Override
    @Transactional(readOnly = true)
    public ExpenseResponse getById(Long id) {
        Expense expense = findInTenant(id);
        // Platform expenses have no CustomRole to check EXPENSE_VIEW against; the controller's role-based @PreAuthorize gates that branch.
        if (isPlatformCaller()) {
            return ExpenseMapper.toResponse(expense);
        }
        if (!authorizationService.hasPermission(PermissionCode.EXPENSE_VIEW)) {
            requireOwnExpense(expense);
        }
        return ExpenseMapper.toResponse(expense);
    }

    private boolean isPlatformCaller() {
        User current = securityUtil.getCurrentUser();
        return current != null && current.isPlatformUser();
    }

    // Platform expenses (the SaaS provider's own costs) have a null companyId, so they are looked up separately rather than by the caller's company id.
    private Expense findInTenant(Long id) {
        if (isPlatformCaller()) {
            return expenseRepository.findByIdAndCompanyIdIsNull(id)
                    .orElseThrow(() -> new ResourceNotFoundException("Expense not found"));
        }
        return expenseRepository.findByIdAndCompanyId(id, securityUtil.getCurrentCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Expense not found"));
    }

    private void requireOwnExpense(Expense expense) {
        User currentUser = securityUtil.getCurrentUser();
        Employee currentEmployee = currentUser != null
                ? employeeRepository.findByUserId(currentUser.getId()).orElse(null)
                : null;
        if (currentEmployee == null || expense.getSubmittedBy() == null
                || !expense.getSubmittedBy().getId().equals(currentEmployee.getId())) {
            throw new ForbiddenException("Access denied: you can only access your own expenses");
        }
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ExpenseResponse> getAll(Pageable pageable) {
        if (isPlatformCaller()) {
            return expenseRepository.findByCompanyIdIsNull(pageable)
                    .map(ExpenseMapper::toResponse);
        }
        authorizationService.checkPermission(PermissionCode.EXPENSE_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return expenseRepository.findByCompanyId(companyId, pageable)
                .map(ExpenseMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ExpenseResponse> getByStatus(ExpenseStatus status, Pageable pageable) {
        if (isPlatformCaller()) {
            return expenseRepository.findByCompanyIdIsNullAndStatus(status, pageable)
                    .map(ExpenseMapper::toResponse);
        }
        authorizationService.checkPermission(PermissionCode.EXPENSE_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return expenseRepository.findByCompanyIdAndStatus(companyId, status, pageable)
                .map(ExpenseMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ExpenseResponse> getByVendorName(String vendorName, Pageable pageable) {
        if (isPlatformCaller()) {
            return expenseRepository.findByCompanyIdIsNullAndVendorName(vendorName, pageable)
                    .map(ExpenseMapper::toResponse);
        }
        authorizationService.checkPermission(PermissionCode.EXPENSE_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return expenseRepository.findByCompanyIdAndVendorName(companyId, vendorName, pageable)
                .map(ExpenseMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ExpenseResponse> getMyExpenses(Long employeeId, Pageable pageable) {
        Long companyId = securityUtil.getCurrentCompanyId();
        User currentUser = securityUtil.getCurrentUser();
        if (currentUser == null) {
            throw new ResourceNotFoundException("User not authenticated");
        }
        Long ownEmployeeId = employeeRepository.findByUserId(currentUser.getId())
                .map(Employee::getId).orElse(null);
        if (employeeId == null) {
            if (ownEmployeeId == null) {
                throw new ResourceNotFoundException("Employee profile not found");
            }
            employeeId = ownEmployeeId;
        } else if (!employeeId.equals(ownEmployeeId) && !isPlatformCaller()) {
            // "my-expenses" with someone else's employeeId read any colleague's claims; that is an EXPENSE_VIEW operation, while asking for your own stays permission-free.
            // Platform callers have no CustomRole to check against - same carve-out as getAll.
            authorizationService.checkPermission(PermissionCode.EXPENSE_VIEW);
        }
        return expenseRepository.findByCompanyIdAndSubmittedById(companyId, employeeId, pageable)
                .map(ExpenseMapper::toResponse);
    }

    @Override
    @Transactional
    public ExpenseResponse update(Long id, ExpenseRequest request) {
        Expense expense = findInTenant(id);

        if (!isPlatformCaller() && !authorizationService.hasPermission(PermissionCode.EXPENSE_UPDATE)) {
            requireOwnExpense(expense);
        }

        if (expense.getStatus() != ExpenseStatus.PENDING) {
            throw new BadRequestException("Can only update pending expenses");
        }
        requirePositiveAmount(request.getAmount());

        // Every optional field is null-skipped. Four of these used to be assigned unconditionally - category,
        // notes, the expense account and the receipt - so a PATCH carrying only what the user touched plus the
        // three the DTO requires silently wiped the rest. Category mattered most: it is what the budget check
        // aggregates on approval, so an edited expense could miss its budget warning with no trace that a
        // category had ever been set.
        //
        // description, amount and expenseDate are @NotNull on the request, so they are always present and need no
        // guard. The receipt is guarded on the request value rather than inside requireOwn, because requireOwn
        // treats a null as "clear the column", which is right for an explicit clear and wrong for an absent key.
        if (request.getTitle() != null) expense.setTitle(request.getTitle());
        if (request.getCurrency() != null) expense.setCurrency(request.getCurrency());
        expense.setDescription(request.getDescription());
        expense.setAmount(request.getAmount());
        if (request.getCategory() != null) expense.setCategory(request.getCategory());
        if (request.getExpenseAccountId() != null) {
            expense.setExpenseAccount(resolveExpenseAccount(expense.getCompanyId(), request.getExpenseAccountId()));
        }
        expense.setExpenseDate(request.getExpenseDate());
        if (request.getReceiptUrl() != null) {
            expense.setReceiptUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(
                    request.getReceiptUrl(), expense.getReceiptUrl()));
        }
        if (request.getNotes() != null) expense.setNotes(request.getNotes());

        if (request.getVendorName() != null) {
            expense.setVendorName(request.getVendorName());
        }

        expense = expenseRepository.save(expense);
        return ExpenseMapper.toResponse(expense);
    }

    @Override
    @Transactional
    public String approveExpense(Long id, String approvalNotes) {
        if (!isPlatformCaller()) {
            authorizationService.checkPermission(PermissionCode.EXPENSE_APPROVE);
        }
        Expense expense = findInTenant(id);

        // Re-approving would post the same Dr Expense / Cr Payable liability a second time for one expense.
        if (expense.getStatus() != ExpenseStatus.PENDING) {
            throw new BadRequestException(
                    "This expense is " + expense.getStatus() + " - only a pending expense can be approved");
        }

        User currentUser = securityUtil.getCurrentUser();
        if (currentUser == null) {
            throw new ResourceNotFoundException("User not authenticated");
        }
        Long currentUserId = currentUser.getId();
        User approver = userRepository.findById(currentUserId)
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        // Maker-checker: you can't approve your own expense claim.
        if (expense.getSubmittedBy() != null && expense.getSubmittedBy().getUser() != null
                && expense.getSubmittedBy().getUser().getId().equals(currentUserId)) {
            throw new BadRequestException("You submitted this expense - a different user must approve it");
        }
        // Checking only submittedBy let a user raise an expense on a colleague's behalf and then approve it themselves.
        if (expense.getCreatedBy() != null && expense.getCreatedBy().getId().equals(currentUserId)) {
            throw new BadRequestException("You created this expense - a different user must approve it");
        }

        expense.approve(approver);
        expense.setApprovalNotes(approvalNotes);
        expenseRepository.save(expense);

        // Post Dr Expense / Cr Payable at approval, mirroring VendorBillService.approve(): posting only at payment understated period-end liabilities for this spend channel.
        // Guarded on companyId: platform expenses have no company chart of accounts, so posting would fail or land in the wrong tenant's books.
        if (expense.getCompanyId() != null) {
            Long companyId = expense.getCompanyId();
            String description = "Expense approved: " + expense.getTitle()
                    + (expense.getCategory() != null ? " (" + expense.getCategory() + ")" : "")
                    + " - " + expense.getExpenseNumber();
            LocalDate transactionDate = expense.getExpenseDate() != null ? expense.getExpenseDate() : LocalDate.now();
            ChartOfAccount expenseAccount = expense.getExpenseAccount() != null
                    ? expense.getExpenseAccount()
                    : accountResolver.operatingExpenses(companyId);
            ChartOfAccount ap = accountResolver.accountsPayable(companyId);
            glService.recordBalancedTransaction(companyId, java.util.List.of(
                            LedgerLine.debit(expenseAccount.getId(), expense.getAmount()),
                            LedgerLine.credit(ap.getId(), expense.getAmount())),
                    description, GlReferenceType.EXPENSE, expense.getId(), expense.getExpenseNumber(), transactionDate);
        }

        // Non-blocking by design: the approver is warned when this pushes the category over budget, but the approval stands. Platform expenses have no company and so no budgets.
        if (expense.getCompanyId() != null) {
            return budgetService.warningFor(expense.getCompanyId(), expense.getCategory(),
                    expense.getExpenseDate(), expense.getAmount());
        }
        return null;
    }

    @Override
    @Transactional
    public void rejectExpense(Long id, String reason) {
        if (!isPlatformCaller()) {
            authorizationService.checkPermission(PermissionCode.EXPENSE_REJECT);
        }
        Expense expense = findInTenant(id);
        if (expense.getStatus() == ExpenseStatus.PAID) {
            throw new BadRequestException("Cannot reject a paid expense");
        }
        boolean wasApproved = expense.getStatus() == ExpenseStatus.APPROVED;
        expense.reject();
        expense.setApprovalNotes(reason);
        expenseRepository.save(expense);

        // Rejecting an already-approved expense must reverse approval's Dr Expense / Cr Payable, or the liability sits in AP forever - same shape as VendorBillService.cancel()'s wasPosted branch.
        // Guarded on companyId: platform expenses never posted anything at approval.
        if (wasApproved && expense.getCompanyId() != null) {
            Long companyId = expense.getCompanyId();
            String description = "Expense " + expense.getExpenseNumber() + " rejected after approval - reversal";
            // Date the reversal on the expense date so both legs net to zero in the same period; falls back to today when that period is closed, since the ledger rejects closed-period postings.
            LocalDate reversalDate = expense.getExpenseDate() != null
                    && !periodLockChecker.isDateInClosedPeriod(companyId, expense.getExpenseDate())
                    ? expense.getExpenseDate()
                    : LocalDate.now();
            ChartOfAccount expenseAccount = expense.getExpenseAccount() != null
                    ? expense.getExpenseAccount()
                    : accountResolver.operatingExpenses(companyId);
            ChartOfAccount ap = accountResolver.accountsPayable(companyId);
            glService.recordBalancedTransaction(companyId, java.util.List.of(
                            LedgerLine.credit(expenseAccount.getId(), expense.getAmount()),
                            LedgerLine.debit(ap.getId(), expense.getAmount())),
                    description, GlReferenceType.EXPENSE, expense.getId(), expense.getExpenseNumber(), reversalDate);
        }
    }

    @Override
    @Transactional
    public void markAsPaid(Long id, String reimbursementMethod, String referenceNumber) {
        if (!isPlatformCaller()) {
            authorizationService.checkPermission(PermissionCode.EXPENSE_APPROVE);
        }
        Expense expense = findInTenant(id);

        // Without this, calling mark-as-paid twice on the same expense posts
        // Dr Accounts Payable / Cr Cash a second time - cash paid out twice for
        // one reimbursement, and AP driven negative by the phantom second clear.
        if (expense.getStatus() != ExpenseStatus.APPROVED) {
            throw new BadRequestException(
                    "This expense is " + expense.getStatus() + " - only an approved expense can be marked paid");
        }

        expense.markAsPaid(reimbursementMethod, referenceNumber);
        expenseRepository.save(expense);

        // Approval already recognized Dr Expense / Cr Payable, so paying clears the liability instead of re-recognizing: Dr AP / Cr Cash, as in VendorBillService.recordPayment().
        // Platform expenses (companyId == null) are records only, never posted: resolving AP/Cash for a null company would book platform spend into a tenant's books.
        Long companyId = expense.getCompanyId();
        if (companyId == null) {
            return;
        }
        String description = "Expense reimbursed: " + expense.getTitle()
                + (expense.getCategory() != null ? " (" + expense.getCategory() + ")" : "")
                + " - " + expense.getExpenseNumber();

        ChartOfAccount ap = accountResolver.accountsPayable(companyId);
        ChartOfAccount cash = accountResolver.cash(companyId);
        glService.recordBalancedTransaction(companyId, java.util.List.of(
                        LedgerLine.debit(ap.getId(), expense.getAmount()),
                        LedgerLine.credit(cash.getId(), expense.getAmount())),
                description, GlReferenceType.EXPENSE, expense.getId(), expense.getExpenseNumber(), expense.getReimbursedDate());
    }

    @Override
    @Transactional
    public void delete(Long id) {
        Expense expense = findInTenant(id);
        if (!isPlatformCaller() && !authorizationService.hasPermission(PermissionCode.EXPENSE_DELETE)) {
            requireOwnExpense(expense);
        }
        if (expense.getStatus() == ExpenseStatus.PAID || expense.getStatus() == ExpenseStatus.APPROVED) {
            // APPROVED has posted a Dr Expense / Cr Payable liability; deleting would leave that GL entry dangling.
            throw new BadRequestException("Cannot delete a " + expense.getStatus()
                    + " expense - it has GL entries. Reject it first if it needs to be undone.");
        }
        expense.softDelete();
        expenseRepository.save(expense);
    }

    @Override
    public ExpenseComposeResponse composeEntry(ExpenseComposeRequest request) {
        String prompt = ExpenseEntryPromptBuilder.builder()
            .setVendorName(request.getVendorName())
            .setAmount(request.getAmount())
            .setCategory(request.getCategory())
            .setRoughNotes(request.getRoughNotes())
            .build();

        String raw = aiService.generateRaw(AiFeature.EXPENSE_ENTRY, prompt);
        return parseCompose(raw, request.getRoughNotes());
    }

    private ExpenseComposeResponse parseCompose(String raw, String fallbackNotes) {
        ExpenseComposeResponse response = new ExpenseComposeResponse();
        try {
            String cleaned = raw.trim();
            if (cleaned.startsWith("```")) {
                cleaned = cleaned.replaceFirst("^```[a-zA-Z]*\\n?", "").replaceFirst("```\\s*$", "");
            }
            JsonNode node = COMPOSE_MAPPER.readTree(cleaned);
            response.setTitle(node.path("title").asText(null));
            response.setDescription(node.path("description").asText(null));
        } catch (Exception ignored) {
            // Model didn't return valid JSON - fall back to the raw text as the description rather than failing the request.
        }
        if (response.getTitle() == null || response.getTitle().isBlank()) {
            response.setTitle(fallbackNotes.length() > 60
                ? fallbackNotes.substring(0, 57) + "..." : fallbackNotes);
        }
        if (response.getDescription() == null || response.getDescription().isBlank()) {
            response.setDescription(raw);
        }
        return response;
    }

    /** EXP-YYYY-NNNNNN from the locked DocumentNumberService counter; the unlocked MAX+1 let two concurrent creators read the same maximum and build the same number. */
    private String generateExpenseNumber(Long companyId) {
        int year = LocalDate.now().getYear();
        String prefix = "EXP-" + year + "-";
        return documentNumberService.next(companyId, DocumentNumberService.EXPENSE, year, prefix, () -> {
            // The tenant query's "= :companyId" never matches the NULL companyId of platform expenses, so they need an IS NULL lookup or every one collides on 000001.
            Long max = companyId == null
                    ? expenseRepository.findMaxPlatformExpenseSequenceIncludingDeleted(prefix, prefix.length() + 1)
                    : expenseRepository.findMaxExpenseSequenceIncludingDeleted(companyId, prefix, prefix.length() + 1);
            return max == null ? 1L : max + 1L;
        });
    }
}