package com.zuhoocms.modules.hrm.payroll;

/** A rendered payslip plus its filename; the name needs the loaded entity, so returning it here saves the controller a second lookup. */
public record PayslipDocument(byte[] content, String fileName) {
}
