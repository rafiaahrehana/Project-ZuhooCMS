/// Money owed out: who is owed it, and against what.
///
/// A **vendor** is somebody the company buys from. A **bill** is one invoice
/// from them, which is approved, then paid down in instalments until nothing
/// is left.
abstract final class PayablesPermissions {
  static const vendorView = 'VENDOR_VIEW';
  static const vendorCreate = 'VENDOR_CREATE';

  /// Also covers the active/inactive toggle — the service checks the same
  /// code for both.
  static const vendorUpdate = 'VENDOR_UPDATE';

  static const vendorDelete = 'VENDOR_DELETE';

  static const billView = 'VENDOR_BILL_VIEW';
  static const billCreate = 'VENDOR_BILL_CREATE';
  static const billApprove = 'VENDOR_BILL_APPROVE';

  /// Not `VENDOR_BILL_PAY` — the enum spells it out.
  static const billPayment = 'VENDOR_BILL_PAYMENT';

  static const billCancel = 'VENDOR_BILL_CANCEL';
}

/// Where a bill stands. Mirrors `VendorBillStatus`.
abstract final class BillStatus {
  static const draft = 'DRAFT';
  static const approved = 'APPROVED';
  static const partiallyPaid = 'PARTIALLY_PAID';
  static const overdue = 'OVERDUE';
  static const paid = 'PAID';
  static const cancelled = 'CANCELLED';

  static const all = [
    draft,
    approved,
    partiallyPaid,
    overdue,
    paid,
    cancelled,
  ];

  /// Nothing more is owed on a bill in one of these.
  static const settled = {paid, cancelled};

  /// A payment can be recorded against these. `OVERDUE` and `PARTIALLY_PAID`
  /// are both states an approved bill passes through, so all three qualify —
  /// the service checks "approved" loosely, not the literal DRAFT/APPROVED
  /// pair.
  static const payableFrom = {approved, partiallyPaid, overdue};
}

class Vendor {
  const Vendor({
    required this.id,
    required this.name,
    required this.active,
    this.contactPerson,
    this.email,
    this.phone,
    this.taxId,
    this.address,
    this.paymentTerms,
    this.notes,
    this.outstandingBalance,
  });

  final int id;
  final String name;
  final bool active;
  final String? contactPerson;
  final String? email;
  final String? phone;
  final String? taxId;
  final String? address;
  final String? paymentTerms;
  final String? notes;

  /// What is still owed to them across every bill.
  final double? outstandingBalance;

  bool get owesMoney => (outstandingBalance ?? 0) > 0;

  factory Vendor.fromJson(Map<String, dynamic> json) => Vendor(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        active: json['active'] as bool? ?? true,
        contactPerson: json['contactPerson'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        taxId: json['taxId'] as String?,
        address: json['address'] as String?,
        paymentTerms: json['paymentTerms'] as String?,
        notes: json['notes'] as String?,
        outstandingBalance:
            (json['outstandingBalance'] as num?)?.toDouble(),
      );
}

/// POST and PUT /company/finance/vendors
///
/// `name` is `@NotBlank`; the rest are optional with length caps —
/// contact and email 150, phone 50, tax id and payment terms 100, address 500.
/// Those caps are enforced in the form rather than discovered from a 400.
class VendorRequest {
  const VendorRequest({
    required this.name,
    this.contactPerson,
    this.email,
    this.phone,
    this.taxId,
    this.address,
    this.paymentTerms,
    this.notes,
  });

  final String name;
  final String? contactPerson;
  final String? email;
  final String? phone;
  final String? taxId;
  final String? address;
  final String? paymentTerms;
  final String? notes;

  factory VendorRequest.from(Vendor vendor) => VendorRequest(
        name: vendor.name,
        contactPerson: vendor.contactPerson,
        email: vendor.email,
        phone: vendor.phone,
        taxId: vendor.taxId,
        address: vendor.address,
        paymentTerms: vendor.paymentTerms,
        notes: vendor.notes,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'name': name.trim(),
      // Sent as explicit nulls rather than omitted: the update assigns each
      // field from the request, so an absent key clears it either way, and
      // being explicit says what is meant.
      'contactPerson': clean(contactPerson),
      'email': clean(email),
      'phone': clean(phone),
      'taxId': clean(taxId),
      'address': clean(address),
      'paymentTerms': clean(paymentTerms),
      'notes': clean(notes),
    };
  }
}

/// One bill from a vendor.
class VendorBill {
  const VendorBill({
    required this.id,
    required this.billNumber,
    required this.status,
    required this.subtotal,
    required this.taxAmount,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceAmount,
    this.vendorId,
    this.vendorName,
    this.vendorReference,
    this.billDate,
    this.dueDate,
    this.description,
    this.expenseAccountName,
    this.createdBy,
    this.approvedBy,
  });

  final int id;
  final String billNumber;
  final String status;
  final double subtotal;
  final double taxAmount;
  final double totalAmount;
  final double paidAmount;
  final double balanceAmount;
  final int? vendorId;
  final String? vendorName;
  final String? vendorReference;
  final String? billDate;
  final String? dueDate;
  final String? description;
  final String? expenseAccountName;
  final String? createdBy;
  final String? approvedBy;

  bool get isSettled => BillStatus.settled.contains(status);

  bool get canApprove => status == BillStatus.draft;

  bool get canPay =>
      BillStatus.payableFrom.contains(status) && balanceAmount > 0;

  /// Cancelling is refused once anything has been paid against it — the
  /// backend says so, and so does the screen before asking.
  bool get canCancel => status != BillStatus.cancelled && paidAmount <= 0;

  /// How much of it has been settled, or null on a zero-total bill.
  double? get paidShare {
    if (totalAmount <= 0) return null;
    return (paidAmount / totalAmount).clamp(0.0, 1.0);
  }

  factory VendorBill.fromJson(Map<String, dynamic> json) => VendorBill(
        id: (json['id'] as num?)?.toInt() ?? 0,
        billNumber: json['billNumber'] as String? ?? '',
        status: json['status'] as String? ?? BillStatus.draft,
        subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
        taxAmount: (json['taxAmount'] as num?)?.toDouble() ?? 0,
        totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
        paidAmount: (json['paidAmount'] as num?)?.toDouble() ?? 0,
        balanceAmount: (json['balanceAmount'] as num?)?.toDouble() ?? 0,
        vendorId: (json['vendorId'] as num?)?.toInt(),
        vendorName: json['vendorName'] as String?,
        vendorReference: json['vendorReference'] as String?,
        billDate: json['billDate'] as String?,
        dueDate: json['dueDate'] as String?,
        description: json['description'] as String?,
        expenseAccountName: json['expenseAccountName'] as String?,
        createdBy: json['createdBy'] as String?,
        approvedBy: json['approvedBy'] as String?,
      );
}

/// POST /company/finance/vendor-bills
///
/// Four `@NotNull` fields — vendor, both dates and the subtotal — and the
/// subtotal is `@DecimalMin("0.01")`, so a bill for nothing is refused.
///
/// There is no update endpoint. A bill is entered, approved by somebody else,
/// and paid down; a wrong one is cancelled and re-entered, which is correct for
/// something the ledger has already recorded.
///
/// The expense account must be an expense-type account — the service refuses
/// anything else with a message naming the account and its type.
class VendorBillRequest {
  const VendorBillRequest({
    required this.vendorId,
    required this.billDate,
    required this.dueDate,
    required this.subtotal,
    this.taxAmount = 0,
    this.vendorReference,
    this.description,
    this.expenseAccountId,
  });

  final int vendorId;

  /// `yyyy-MM-dd`.
  final String billDate;
  final String dueDate;

  final double subtotal;
  final double taxAmount;
  final String? vendorReference;
  final String? description;
  final int? expenseAccountId;

  double get total => subtotal + taxAmount;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'vendorId': vendorId,
      'billDate': billDate,
      'dueDate': dueDate,
      'subtotal': subtotal,
      'taxAmount': taxAmount,
      if (clean(vendorReference) != null)
        'vendorReference': clean(vendorReference),
      if (clean(description) != null) 'description': clean(description),
      if (expenseAccountId != null) 'expenseAccountId': expenseAccountId,
    };
  }
}
