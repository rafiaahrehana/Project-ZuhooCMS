/// Money owed in, and what happens to it after an invoice is raised.
///
/// Four things that all hang off an invoice: the **payment receipt** recording
/// that money arrived, the **credit note** reducing what is owed, the
/// **refund** sending money back, and the invoice's own send-and-cancel
/// actions.
abstract final class ReceivablesPermissions {
  static const invoiceView = 'INVOICE_VIEW';
  static const invoiceSend = 'INVOICE_SEND';
  static const invoicePayment = 'INVOICE_PAYMENT';
  static const invoiceCancel = 'INVOICE_CANCEL';

  /// Processing and rejecting a refund are the same code.
  static const invoiceRefund = 'INVOICE_REFUND';

  static const creditNote = 'INVOICE_CREDIT_NOTE';

  /// The receipt codes are spelled out in full — not `PAYMENT_VIEW`.
  static const receiptView = 'PAYMENT_RECEIPT_VIEW';
  static const receiptCreate = 'PAYMENT_RECEIPT_CREATE';

  /// One code covers confirming, depositing and reversing.
  static const receiptConfirm = 'PAYMENT_RECEIPT_CONFIRM';

  static const receiptDelete = 'PAYMENT_RECEIPT_DELETE';
}

/// Where a receipt stands. Mirrors `PaymentStatus`.
abstract final class PaymentStatus {
  static const pending = 'PENDING';
  static const confirmed = 'CONFIRMED';
  static const deposited = 'DEPOSITED';
  static const failed = 'FAILED';
  static const reversed = 'REVERSED';

  static const all = [pending, confirmed, deposited, failed, reversed];
}

/// Mirrors `RefundStatus`.
abstract final class RefundStatus {
  static const requested = 'REQUESTED';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED';
  static const processed = 'PROCESSED';

  static const all = [requested, approved, rejected, processed];

  /// Nothing more happens to a refund in one of these.
  static const settled = {rejected, processed};
}

/// Money that came in against an invoice.
class PaymentReceipt {
  const PaymentReceipt({
    required this.id,
    required this.receiptNumber,
    required this.amount,
    required this.status,
    this.invoiceId,
    this.invoiceNumber,
    this.clientId,
    this.clientName,
    this.paymentDate,
    this.paymentMethod,
    this.transactionReference,
    this.depositedToBank,
    this.reversedDate,
    this.reversalReason,
    this.notes,
  });

  final int id;
  final String receiptNumber;
  final double amount;
  final String status;
  final int? invoiceId;
  final String? invoiceNumber;
  final int? clientId;
  final String? clientName;
  final String? paymentDate;
  final String? paymentMethod;
  final String? transactionReference;
  final String? depositedToBank;
  final String? reversedDate;
  final String? reversalReason;
  final String? notes;

  /// A receipt starts pending and is confirmed once the money is known to have
  /// cleared. Only then can it be banked.
  bool get canConfirm => status == PaymentStatus.pending;

  bool get canDeposit => status == PaymentStatus.confirmed;

  /// Reversing undoes it. A reversed receipt cannot be reversed again, and a
  /// failed one has nothing to undo.
  bool get canReverse =>
      status == PaymentStatus.confirmed ||
      status == PaymentStatus.deposited ||
      status == PaymentStatus.pending;

  factory PaymentReceipt.fromJson(Map<String, dynamic> json) => PaymentReceipt(
        id: (json['id'] as num?)?.toInt() ?? 0,
        receiptNumber: json['receiptNumber'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? PaymentStatus.pending,
        invoiceId: (json['invoiceId'] as num?)?.toInt(),
        invoiceNumber: json['invoiceNumber'] as String?,
        clientId: (json['clientId'] as num?)?.toInt(),
        clientName: json['clientName'] as String?,
        paymentDate: json['paymentDate'] as String?,
        paymentMethod: json['paymentMethod'] as String?,
        transactionReference: json['transactionReference'] as String?,
        depositedToBank: json['depositedToBank'] as String?,
        reversedDate: json['reversedDate'] as String?,
        reversalReason: json['reversalReason'] as String?,
        notes: json['notes'] as String?,
      );
}

/// Money going back out to a client.
///
/// Raised elsewhere — usually against a cancelled service request — and either
/// processed or rejected here. There is no "create a refund" endpoint on this
/// controller, which is why the screen only ever decides them.
class Refund {
  const Refund({
    required this.id,
    required this.requestedAmount,
    required this.status,
    this.clientInvoiceId,
    this.invoiceNumber,
    this.clientName,
    this.serviceRequestTitle,
    this.reason,
    this.requestedAt,
    this.processedByName,
    this.processedAt,
    this.rejectionReason,
  });

  final int id;
  final double requestedAmount;
  final String status;
  final int? clientInvoiceId;
  final String? invoiceNumber;
  final String? clientName;
  final String? serviceRequestTitle;
  final String? reason;
  final String? requestedAt;
  final String? processedByName;
  final String? processedAt;
  final String? rejectionReason;

  bool get isSettled => RefundStatus.settled.contains(status);

  /// Both actions are open on anything not yet settled.
  bool get canDecide => !isSettled;

  factory Refund.fromJson(Map<String, dynamic> json) => Refund(
        id: (json['id'] as num?)?.toInt() ?? 0,
        requestedAmount: (json['requestedAmount'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? RefundStatus.requested,
        clientInvoiceId: (json['clientInvoiceId'] as num?)?.toInt(),
        invoiceNumber: json['invoiceNumber'] as String?,
        clientName: json['clientName'] as String?,
        serviceRequestTitle: json['serviceRequestTitle'] as String?,
        reason: json['reason'] as String?,
        requestedAt: json['requestedAt'] as String?,
        processedByName: json['processedByName'] as String?,
        processedAt: json['processedAt'] as String?,
        rejectionReason: json['rejectionReason'] as String?,
      );
}

/// A reduction of what an invoice is owed, without money moving.
class CreditNote {
  const CreditNote({
    required this.id,
    required this.creditNoteNumber,
    required this.amount,
    this.clientInvoiceId,
    this.invoiceNumber,
    this.clientName,
    this.reason,
    this.issuedByName,
    this.issuedAt,
  });

  final int id;
  final String creditNoteNumber;
  final double amount;
  final int? clientInvoiceId;
  final String? invoiceNumber;
  final String? clientName;
  final String? reason;
  final String? issuedByName;
  final String? issuedAt;

  factory CreditNote.fromJson(Map<String, dynamic> json) => CreditNote(
        id: (json['id'] as num?)?.toInt() ?? 0,
        creditNoteNumber: json['creditNoteNumber'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        clientInvoiceId: (json['clientInvoiceId'] as num?)?.toInt(),
        invoiceNumber: json['invoiceNumber'] as String?,
        clientName: json['clientName'] as String?,
        reason: json['reason'] as String?,
        issuedByName: json['issuedByName'] as String?,
        issuedAt: json['issuedAt'] as String?,
      );
}

/// POST /company/finance/invoices/credit-notes
///
/// Two `@NotNull` fields, and the amount is `@DecimalMin("0.01")` — a credit
/// note for nothing is refused. There is no update or delete: a credit note is
/// a document of record, and correcting one means issuing another.
class CreditNoteRequest {
  const CreditNoteRequest({
    required this.clientInvoiceId,
    required this.amount,
    this.reason,
  });

  final int clientInvoiceId;
  final double amount;
  final String? reason;

  Map<String, dynamic> toJson() {
    final trimmed = reason?.trim();
    return {
      'clientInvoiceId': clientInvoiceId,
      'amount': amount,
      if (trimmed != null && trimmed.isNotEmpty) 'reason': trimmed,
    };
  }
}
