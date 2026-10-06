package com.zuhoocms.modules.hrm.recruitment.offerletter;

import com.zuhoocms.enums.LetterType;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.Data;

import java.time.LocalDate;

@Data
public class OfferLetterRequest {
    // Recipient: employeeId for employment letters, jobApplicationId for OFFER/APPOINTMENT letters; the service validates which is required per letter type.
    private Long employeeId;
    private Long jobApplicationId;
    @NotNull(message = "Letter type is required")
    private LetterType letterType;
    @Size(max = 100)
    private String referenceNumber;
    @NotNull(message = "Issue date is required")
    private LocalDate issueDate;
    /**
     * The letter body. Deliberately NOT required: blank (or absent) content means "write it with AI", which is what
     * OfferLetterServiceImpl.create does and what POST /api/hr/letters is relied on for. The @NotBlank that used to
     * sit here never fired - the controller had no @Valid - so it documented the opposite of the actual behaviour;
     * adding @Valid without removing it would have turned the AI path into a 400.
     */
    private String content;
    @Size(max = 150)
    private String signedBy;
}
