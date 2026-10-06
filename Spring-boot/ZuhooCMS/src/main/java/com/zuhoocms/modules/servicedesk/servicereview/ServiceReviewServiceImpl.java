package com.zuhoocms.modules.servicedesk.servicereview;

import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.crm.client.ClientRepository;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequest;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestRepository;
import com.zuhoocms.enums.ServiceRequestStatus;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

@Service
@RequiredArgsConstructor

public class ServiceReviewServiceImpl implements ServiceReviewService {

    private final ServiceReviewRepository reviewRepository;
    private final ServiceRequestRepository serviceRequestRepository;
    private final ClientRepository clientRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    @Transactional
    public ServiceReviewResponse submitOrUpdate(ServiceReviewRequest request) {
        Long companyId = requireCompanyId();

        // Must be company-scoped: findById() alone let a client review another company's request.
        ServiceRequest sr = serviceRequestRepository
                .findByIdAndCompanyId(request.getServiceRequestId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Service request not found: " + request.getServiceRequestId()));

        if (sr.getStatus() != ServiceRequestStatus.COMPLETED)
            throw new BadRequestException("Reviews can only be submitted for completed requests");

        Client client = clientRepository.findByUserId(securityUtil.getCurrentUser().getId())
                .orElseThrow(() -> new BadRequestException("Only clients can submit reviews"));

        if (!sr.getClient().getId().equals(client.getId()))
            throw new BadRequestException("You can only review your own service requests");

        ServiceReview review = reviewRepository
                .findByServiceRequestIdAndClientId(sr.getId(), client.getId())
                .orElse(null);

        if (review != null) {
            // The 7-day edit window runs from the last edit, not the original creation.
            LocalDateTime editBase = review.getUpdatedAt() != null
                    ? review.getUpdatedAt() : review.getCreatedAt();
            if (editBase.isBefore(LocalDateTime.now().minusDays(7)))
                throw new BadRequestException("Reviews can no longer be edited after 7 days");

            review.setRating(request.getRating());
            review.setComment(request.getComment());
        } else {
            review = ServiceReview.builder()
                    .serviceRequest(sr)
                    .hubService(sr.getCompanyService())
                    .client(client)
                    .company(companyRef(companyId))
                    .rating(request.getRating())
                    .comment(request.getComment())
                    .published(true)
                    .publishedAt(LocalDateTime.now())
                    .build();
        }

        reviewRepository.save(review);
        return ServiceReviewMapper.toServiceReviewResponse(review);
    }

    @Override
    @Transactional(readOnly = true)
    public ServiceReviewResponse getById(Long id) {
        Long companyId = requireCompanyId();
        // Must be tenant-scoped: findById(id) let any user read another company's review by id.
        return ServiceReviewMapper.toServiceReviewResponse(
                reviewRepository.findByIdAndCompanyId(id, companyId)
                        .orElseThrow(() -> new ResourceNotFoundException(
                                "Service review not found: " + id)));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ServiceReviewResponse> listAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.REVIEW_VIEW);
        Long companyId = requireCompanyId();
        // Must be tenant-scoped: findAll(pageable) returned every tenant's reviews.
        return reviewRepository.findByCompanyId(companyId, pageable)
                .map(ServiceReviewMapper::toServiceReviewResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ServiceReviewResponse> listByService(Long hubServiceId, Pageable pageable) {
        // Scoped to the caller's company: unscoped, any logged-in user could read every tenant's reviews.
        return reviewRepository.findByCompanyIdAndHubServiceId(requireCompanyId(), hubServiceId, pageable)
                .map(ServiceReviewMapper::toServiceReviewResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Double getAverageRatingByService(Long hubServiceId) {
        return reviewRepository.findAverageRatingByCompanyIdAndServiceId(requireCompanyId(), hubServiceId).orElse(null);
    }

    @Override
    @Transactional(readOnly = true)
    public Double getAverageRatingByCompany() {
        return reviewRepository.findAverageRatingByCompanyId(requireCompanyId()).orElse(null);
    }

    @Override
    @Transactional
    public void delete(Long id) {
        authorizationService.checkPermission(PermissionCode.REVIEW_DELETE);
        Long companyId = requireCompanyId();
        // Tenant-scoped so admins delete only their own company's reviews.
        // No isPublished() guard on purpose: moderation must be able to delete published reviews, and the controller's @PreAuthorize is the gate.
        ServiceReview review = reviewRepository.findByIdAndCompanyId(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Service review not found: " + id));
        review.softDelete();
        reviewRepository.save(review);
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    private Company companyRef(Long companyId) {
        Company c = new Company();
        c.setId(companyId);
        return c;
    }
}
