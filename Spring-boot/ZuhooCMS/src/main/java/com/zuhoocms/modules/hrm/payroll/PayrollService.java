package com.zuhoocms.modules.hrm.payroll;

import com.zuhoocms.enums.PaymentMethod;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.time.LocalDate;

public interface PayrollService {
    PayrollResponse create(CreatePayrollRequest request);
    PayrollResponse getById(Long id);
    Page<PayrollResponse> listByPeriod(int month, int year, Pageable pageable);
    Page<PayrollResponse> listForEmployee(Long employeeId, Pageable pageable);

    /** Single approve - rejected for lines that belong to a payroll run. */
    PayrollResponse approve(Long id);

    /** Approve path used by PayrollRunService for one of the run's own lines. */
    PayrollResponse approveForRun(Long id, Long runId);

    /** CSV of APPROVED payrolls for a period, for bank bulk-salary upload. */
    String buildDisbursementCsv(int month, int year);

    /** Single pay - rejected for lines that belong to a payroll run. Runs in its own transaction. */
    PayrollResponse markPaid(Long id, String paymentReference, PaymentMethod paymentMethod);

    /** Pays one run line in its own REQUIRES_NEW transaction, dated paidAt; the employee is notified only after it commits. */
    PayrollResponse payForRun(Long id, Long runId, String paymentReference, PaymentMethod paymentMethod, LocalDate paidAt);

    void delete(Long id);

    /** Creates a DRAFT payroll for every active employee with a salary structure who doesn't already have one for this period. */
    BulkPayrollResult generateForAllEmployees(int month, int year);

    /** Recomputes every DRAFT line of the run from fresh inputs. */
    void recalculateDraftLines(Long runId);

    /** Payslip PDF; PAYROLL_VIEW sees anyone's, everyone else only their own, checked in the service so no other caller can bypass it. */
    PayslipDocument generatePayslipPdf(Long id);
}
