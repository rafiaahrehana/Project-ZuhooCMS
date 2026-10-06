package com.zuhoocms.modules.hrm.recruitment.offerletter;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.core.base.SoftDeletedProxies;
import com.zuhoocms.modules.hrm.employee.Employee;

public class OfferletterMapper {

    /**
     * employeeName comes from the caller: reading it here as emp.getUser().getFullName() initialized the lazy
     * Employee/User proxy, which BaseEntity's {@code @SQLRestriction("deleted = false")} makes throw
     * EntityNotFoundException once the employee's login is soft-deleted - and only worked at all inside the
     * transaction. The letter row already stores the recipient name for exactly this reason.
     */
    public static OfferLetterResponse toLetterResponse(OfferLetter ol, String employeeName) {
        Employee emp = ol.getEmployee();
        User createdBy = SoftDeletedProxies.loadable(ol.getCreatedBy());
        OfferLetterResponse r = new OfferLetterResponse();
        r.setId(ol.getId());
        r.setLetterType(ol.getLetterType());
        r.setReferenceNumber(ol.getReferenceNumber());
        r.setIssueDate(ol.getIssueDate());
        r.setContent(ol.getContent());
        r.setSignedBy(ol.getSignedBy());
        r.setFileUrl(ol.getFileUrl());
        r.setIssued(ol.isIssued());
        // Ids read off the FK: getId() on a proxy to a departed employee (or a deleted application) loads the row and
        // throws under @SQLRestriction, which 500'd get/list/issue for exactly the letters HR issues after someone leaves.
        r.setEmployeeId(SoftDeletedProxies.id(emp));
        r.setEmployeeName(emp != null ? employeeName : null);
        r.setJobApplicationId(SoftDeletedProxies.id(ol.getJobApplication()));
        r.setRecipientName(ol.getRecipientName());
        r.setRecipientEmail(ol.getRecipientEmail());
        r.setCreatedById(createdBy != null ? createdBy.getId() : null);
        r.setCreatedByName(createdBy != null ? createdBy.getFullName() : null);
        r.setCreatedAt(ol.getCreatedAt());
        return r;
    }
}
