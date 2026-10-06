package com.zuhoocms.modules.ai.prompt;

import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDate;


@Setter
@Accessors(chain = true)
public class EmploymentLetterPromptBuilder {

    private String companyName;
    private String employeeName;
    private String designation;
    private String department;
    private LocalDate joiningDate;
    private String letterType;

    public static EmploymentLetterPromptBuilder builder() {
        return new EmploymentLetterPromptBuilder();
    }

    /*
     * A missing joining date omits the line and tells the model so, instead of defaulting to a date.
     *
     * Any stand-in here (today, the employee's creation date) would be printed as the date of joining on a legal
     * document that HR then signs - a fabricated fact, and the harder kind to spot because it looks plausible. The
     * date is also not equally relevant per letter type: OFFER/APPOINTMENT always carry one (the caller supplies
     * today as the proposed joining date, so this branch never fires for them); EXPERIENCE, CONFIRMATION, PROMOTION,
     * TRANSFER, TERMINATION, RESIGNATION_ACCEPTANCE and SALARY_CERTIFICATE want one but must describe the tenure
     * without it rather than invent it; NOC, WARNING and APPRECIATION do not need it at all.
     */
    private static final String JOINING_DATE_UNKNOWN_INSTRUCTION =
        "- The employee's date of joining is not on record: do not state, imply or invent any joining date, "
        + "and leave no placeholder for one - refer to their employment or tenure without a start date.";

    public String build() {
        validateFields();
        return """
            Generate a professional, legally compliant employment %s letter.

            Company Name     : %s
            Employee Name    : %s
            Designation      : %s
            Department       : %s
            %s
            Output instructions:
            - Use formal language throughout.
            - Include standard HR clauses for this letter type.
            - Leave a signature block at the bottom for the authorised signatory.
            - Return only the letter body — no preamble, no explanation.%s
            """.formatted(
                letterType,
                companyName,
                employeeName,
                // Defaulted like department below, rather than required: designation is optional on an employee and
                // buildLetterPrompt's fallback (jobTitle) is optional too, so an employee with neither got a 400
                // instead of the draft - and an EXPERIENCE/relieving/NOC letter is exactly what such a record needs.
                PromptSupport.orDefault(designation, "Employee"),
                PromptSupport.orDefault(department, "General"),
                joiningDate != null ? "Date of Joining  : " + joiningDate + "\n" : "",
                joiningDate != null ? "" : "\n" + JOINING_DATE_UNKNOWN_INSTRUCTION
            );
    }

    private void validateFields() {
        PromptSupport.requireNonBlank(companyName, "companyName", "employment letter");
        PromptSupport.requireNonBlank(employeeName, "employeeName", "employment letter");
        // joiningDate is deliberately optional - see JOINING_DATE_UNKNOWN_INSTRUCTION. An employee whose hireDate was
        // never recorded got a 400 on every letter type, including the ones that do not mention a joining date at all.
        PromptSupport.requireNonBlank(letterType, "letterType", "employment letter");
    }
}
