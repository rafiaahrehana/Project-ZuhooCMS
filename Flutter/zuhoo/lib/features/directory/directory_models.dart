import '../../core/config/env.dart';

abstract final class DirectoryPermissions {
  /// What the web app requires to open the employee list. The API itself does
  /// **not** check it — `EmployeeServiceImpl.listAll` performs no permission
  /// check, only the controller's `hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')`.
  ///
  /// Matched here anyway rather than left open: the same endpoint returns pay
  /// and bank details (see [Person]), the tenant configures this permission
  /// deliberately, and widening who can browse colleagues on a phone is not a
  /// decision a port should make on its own.
  static const employeeView = 'EMPLOYEE_VIEW';

  static const employeeCreate = 'EMPLOYEE_CREATE';
  static const employeeUpdate = 'EMPLOYEE_UPDATE';
}

/// Mirrors the backend's `Gender`.
const genders = <String>['MALE', 'FEMALE', 'OTHER', 'PREFER_NOT_TO_SAY'];

/// Mirrors the backend's `EmploymentType`.
const employmentTypes = <String>[
  'FULL_TIME',
  'PART_TIME',
  'CONTRACT',
  'INTERN',
  'CONSULTANT',
];

/// Mirrors the backend's `EmploymentStatus`.
///
/// The last four are terminal: picking one of them does more than change a
/// label. `updateEmployeeDetails` also clears the employee's `active` flag and
/// deactivates their portal login, because payroll eligibility and headcount
/// read `active` rather than this. Worth saying out loud in the form.
const employmentStatuses = <String>[
  'PROBATION',
  'CONFIRMED',
  'ACTIVE',
  'ON_LEAVE',
  'SUSPENDED',
  'RESIGNED',
  'TERMINATED',
  'RETIRED',
];

/// The four that stand somebody down — see [employmentStatuses].
const terminalEmploymentStatuses = <String>[
  'SUSPENDED',
  'RESIGNED',
  'TERMINATED',
  'RETIRED',
];

/// A colleague, as the directory shows them.
///
/// `GET /api/employees` returns considerably more than this: `basicSalary`,
/// `houseRent`, `medicalAllowance`, `transportAllowance`, `billableRate`,
/// `bankAccountNumber`, `bankName`, `bankRoutingNumber`, `nationalId`,
/// `taxId` and `dateOfBirth` all arrive in the same payload, for every
/// employee, unmasked.
///
/// None of them are mapped here, and that is the point. A directory answers
/// "who is this, what do they do, how do I reach them" — it has no business
/// holding a colleague's salary in memory on a phone, and a field that is
/// never parsed cannot be rendered by a later edit that forgets why.
class Person {
  const Person({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.employeeNumber,
    this.jobTitle,
    this.designationName,
    this.departmentId,
    this.departmentName,
    this.email,
    this.officialEmail,
    this.phone,
    this.workPhone,
    this.reportingManagerId,
    this.reportingManagerName,
    this.shiftName,
    this.hireDate,
    this.employmentStatus,
    this.employmentType,
    this.officeLocation,
    this.imageUrl,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String? employeeNumber;
  final String? jobTitle;
  final String? designationName;
  final int? departmentId;
  final String? departmentName;

  /// Personal address. [officialEmail] is the work one; the directory prefers
  /// the work address and falls back, because emailing a colleague's private
  /// account when a work one exists is the wrong default.
  final String? email;
  final String? officialEmail;

  final String? phone;
  final String? workPhone;
  final int? reportingManagerId;
  final String? reportingManagerName;
  final String? shiftName;
  final String? hireDate;
  final String? employmentStatus;
  final String? employmentType;
  final String? officeLocation;
  final String? imageUrl;

  String get fullName => '$firstName $lastName'.trim();

  /// What to put under the name. The job title is free text on the employee
  /// record and the designation is the structured one; either may be blank.
  String? get roleLabel {
    final title = jobTitle?.trim();
    if (title != null && title.isNotEmpty) return title;
    final designation = designationName?.trim();
    return designation == null || designation.isEmpty ? null : designation;
  }

  String? get bestEmail {
    final work = officialEmail?.trim();
    if (work != null && work.isNotEmpty) return work;
    final personal = email?.trim();
    return personal == null || personal.isEmpty ? null : personal;
  }

  String? get bestPhone {
    final work = workPhone?.trim();
    if (work != null && work.isNotEmpty) return work;
    final personal = phone?.trim();
    return personal == null || personal.isEmpty ? null : personal;
  }

  /// Someone who has left. The list still returns them, so the row says so
  /// rather than offering a phone number nobody answers.
  bool get isFormer =>
      employmentStatus == 'TERMINATED' ||
      employmentStatus == 'RESIGNED' ||
      employmentStatus == 'INACTIVE';

  String get initials {
    final f = firstName.trim();
    final l = lastName.trim();
    if (f.isEmpty && l.isEmpty) return '?';
    if (l.isEmpty) return f[0].toUpperCase();
    if (f.isEmpty) return l[0].toUpperCase();
    return (f[0] + l[0]).toUpperCase();
  }

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: (json['id'] as num?)?.toInt() ?? 0,
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        employeeNumber: json['employeeNumber'] as String?,
        jobTitle: json['jobTitle'] as String?,
        designationName: json['designationName'] as String?,
        departmentId: (json['departmentId'] as num?)?.toInt(),
        departmentName: json['departmentName'] as String?,
        email: json['email'] as String?,
        officialEmail: json['officialEmail'] as String?,
        phone: json['phone'] as String?,
        workPhone: json['workPhone'] as String?,
        reportingManagerId: (json['reportingManagerId'] as num?)?.toInt(),
        reportingManagerName: json['reportingManagerName'] as String?,
        shiftName: json['shiftName'] as String?,
        hireDate: json['hireDate'] as String?,
        employmentStatus: json['employmentStatus'] as String?,
        employmentType: json['employmentType'] as String?,
        officeLocation:
            json['officeLocation'] as String? ?? json['location'] as String?,
        // The record carries the employee's own image and the linked user
        // account's; either can be the one that was set.
        imageUrl: Env.resolveImageUrl(
          json['profileImageUrl'] as String? ?? json['image'] as String?,
        ),
      );
}

/// A department.
///
/// One class for two jobs: the name-and-code the directory filter needs, and
/// the fuller record the admin screen edits. The extra fields are nullable and
/// simply absent when the payload is the short one — a second Department class
/// would only be somewhere for the two to drift.
class Department {
  const Department({
    required this.id,
    required this.name,
    this.code,
    this.employeeCount,
    this.description,
    this.active = true,
    this.budget,
    this.parentDepartmentId,
    this.parentDepartmentName,
    this.headEmployeeId,
    this.headEmployeeName,
  });

  final int id;
  final String name;
  final String? code;
  final int? employeeCount;
  final String? description;
  final bool active;
  final double? budget;
  final int? parentDepartmentId;
  final String? parentDepartmentName;
  final int? headEmployeeId;
  final String? headEmployeeName;

  factory Department.fromJson(Map<String, dynamic> json) => Department(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        code: json['code'] as String?,
        employeeCount: (json['employeeCount'] as num?)?.toInt(),
        description: json['description'] as String?,
        // Absent on the short payload, and a department the filter offered is
        // one that exists — so missing reads as active, not inactive.
        active: json['active'] as bool? ?? true,
        budget: (json['budget'] as num?)?.toDouble(),
        parentDepartmentId: (json['parentDepartmentId'] as num?)?.toInt(),
        parentDepartmentName: json['parentDepartmentName'] as String?,
        headEmployeeId: (json['headEmployeeId'] as num?)?.toInt(),
        headEmployeeName: json['headEmployeeName'] as String?,
      );
}

/// POST /employees
///
/// Creates the person **and their login**: the request carries a password,
/// which the backend uses to provision a user account for them. That is why
/// the form asks for it twice and why nothing here is remembered — it is typed
/// by an administrator, sent once, and the person changes it themselves.
///
/// Required, per the DTO: first name, last name, email, password (at least
/// eight characters) and employment type. Everything else the endpoint accepts
/// is optional, and the ones this form does not offer — national ID, tax ID,
/// cost centre, designation, shift, parents' names, full postal address — are
/// left to the web, where the joining paperwork is done anyway.
class CreateEmployeeRequest {
  const CreateEmployeeRequest({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.password,
    required this.employmentType,
    this.jobTitle,
    this.workPhone,
    this.employmentStatus,
    this.departmentId,
    this.reportingManagerId,
    this.gender,
    this.dateOfBirth,
    this.hireDate,
    this.officeLocation,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String password;
  final String employmentType;
  final String? jobTitle;
  final String? workPhone;
  final String? employmentStatus;
  final int? departmentId;
  final int? reportingManagerId;
  final String? gender;
  final String? dateOfBirth;
  final String? hireDate;
  final String? officeLocation;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'email': email.trim(),
      // Never trimmed: leading or trailing spaces are part of a password.
      'password': password,
      'employmentType': employmentType,
      if (clean(jobTitle) != null) 'jobTitle': clean(jobTitle),
      if (clean(workPhone) != null) 'workPhone': clean(workPhone),
      if (employmentStatus != null) 'employmentStatus': employmentStatus,
      if (departmentId != null) 'departmentId': departmentId,
      if (reportingManagerId != null)
        'reportingManagerId': reportingManagerId,
      if (gender != null) 'gender': gender,
      if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
      if (hireDate != null) 'hireDate': hireDate,
      if (clean(officeLocation) != null)
        'officeLocation': clean(officeLocation),
    };
  }
}

/// PATCH /employees/{id}
///
/// A true sparse patch — `updateEmployeeDetails` null-checks every field — so
/// an omitted key is left alone.
///
/// That is what makes it safe for this form to be narrow. The endpoint also
/// accepts salary, bank details, emergency contacts and probation dates, none
/// of which [Person] carries, so the app could not show their current values.
/// A form that displayed them blank would leave an editor unable to tell
/// "unchanged" from "empty" — so they are omitted, and stay whatever the web
/// app set them to.
///
/// Setting a terminal [employmentStatus] also deactivates the employee and
/// their portal login. The form says so before it happens.
class UpdateEmployeeRequest {
  const UpdateEmployeeRequest({
    this.jobTitle,
    this.employmentType,
    this.employmentStatus,
    this.workPhone,
    this.officeLocation,
    this.departmentId,
    this.reportingManagerId,
    this.hireDate,
  });

  final String? jobTitle;
  final String? employmentType;
  final String? employmentStatus;
  final String? workPhone;
  final String? officeLocation;
  final int? departmentId;
  final int? reportingManagerId;
  final String? hireDate;

  factory UpdateEmployeeRequest.from(Person person) => UpdateEmployeeRequest(
        jobTitle: person.jobTitle,
        employmentType: person.employmentType,
        employmentStatus: person.employmentStatus,
        workPhone: person.workPhone,
        officeLocation: person.officeLocation,
        departmentId: person.departmentId,
        reportingManagerId: person.reportingManagerId,
        hireDate: person.hireDate,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      if (clean(jobTitle) != null) 'jobTitle': clean(jobTitle),
      if (employmentType != null) 'employmentType': employmentType,
      if (employmentStatus != null) 'employmentStatus': employmentStatus,
      if (clean(workPhone) != null) 'workPhone': clean(workPhone),
      if (clean(officeLocation) != null)
        'officeLocation': clean(officeLocation),
      if (departmentId != null) 'departmentId': departmentId,
      if (reportingManagerId != null)
        'reportingManagerId': reportingManagerId,
      if (hireDate != null) 'hireDate': hireDate,
    };
  }
}
