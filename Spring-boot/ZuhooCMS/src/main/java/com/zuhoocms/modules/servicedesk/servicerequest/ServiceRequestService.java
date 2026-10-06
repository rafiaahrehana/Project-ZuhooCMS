package com.zuhoocms.modules.servicedesk.servicerequest;

import com.zuhoocms.modules.servicedesk.requestcomment.AddCommentRequest;
import com.zuhoocms.modules.servicedesk.requeststatus.ChangeRequestStatusRequest;
import com.zuhoocms.modules.servicedesk.requestcomment.RequestCommentResponse;
import com.zuhoocms.modules.servicedesk.requeststatus.RequestStatusHistoryResponse;
import com.zuhoocms.enums.ServiceRequestStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.util.List;

public interface ServiceRequestService {

    ServiceRequestResponse create(CreateServiceRequestRequest request);

    ServiceRequestResponse getById(Long id);

    Page<ServiceRequestResponse> listAll(ServiceRequestStatus status, Pageable pageable);

    Page<ServiceRequestResponse> listMyRequests(Pageable pageable);

    Page<ServiceRequestResponse> listAssignedToMe(Pageable pageable);

    ServiceRequestResponse update(Long id, UpdateServiceRequestRequest request);

    ServiceRequestResponse changeStatus(Long id, ChangeRequestStatusRequest request);

    ServiceRequestResponse assign(Long id, Long employeeId);

    void cancel(Long id, String reason);

    /**
     * Same effect as cancel(), for the payment-deadline scheduler: no SecurityContext and no CLIENT-role assignment
     * check. The history row it writes has no user actor, so it is stamped "System".
     *
     * @param deadlineHours the window that elapsed, only so the reason the client reads names the real figure
     */
    void systemCancelForNonPayment(Long id, long deadlineHours);

    RequestCommentResponse addComment(Long requestId, AddCommentRequest request);

    Page<RequestCommentResponse> getComments(Long requestId, Pageable pageable);

    List<RequestStatusHistoryResponse> getStatusHistory(Long requestId);

    ServiceRequestResponse advanceStage(Long id);

    StageProgressResponse getStageProgress(Long id);

    ServiceRequestResponse submitQuotation(Long id, SubmitQuotationRequest request);
    ServiceRequestResponse acceptQuotation(Long id);
    ServiceRequestResponse rejectQuotation(Long id, RejectQuotationRequest request);

    /** Summarise a request's real status/history with AI and suggest a next action */
    ServiceRequestResponse summarise(Long id);

    /** Drafts a reply comment from rough notes, grounded in the request's real status/history. Nothing is posted. */
    ServiceRequestReplyDraftResponse draftReply(Long id, ServiceRequestReplyDraftRequest request);
}
