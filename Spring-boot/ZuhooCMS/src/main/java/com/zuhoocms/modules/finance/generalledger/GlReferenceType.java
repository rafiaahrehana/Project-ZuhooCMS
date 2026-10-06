package com.zuhoocms.modules.finance.generalledger;

/** What source document a GeneralLedger entry was posted from; replaces raw String literals whose typos silently created untracked reference types. name() is stored in the existing referenceType column, so no schema change. */
public enum GlReferenceType {
    INVOICE,
    INVOICE_CANCEL,
    INVOICE_REFUND,
    INVOICE_CREDIT_NOTE,
    PAYMENT_RECEIPT,
    EXPENSE,
    PAYROLL,
    JOURNAL_ENTRY,
    YEAR_END_CLOSE,
    VENDOR_BILL,
    VENDOR_BILL_PAYMENT,
    PAYMENT_REVERSAL,
    FIXED_ASSET_PURCHASE,
    /** Sale/write-off of a fixed asset; reusing FIXED_ASSET_PURCHASE showed two "purchase" postings and left getByReference() unable to tell acquisition from disposal. */
    FIXED_ASSET_DISPOSAL,
    DEPRECIATION,
    OPENING_BALANCE
}
