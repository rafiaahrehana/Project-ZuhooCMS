/// Hiring permissions, taken from the services rather than the Angular routes.
abstract final class RecruitmentPermissions {
  static const jobView = 'JOB_POSTING_VIEW';

  /// Publishing, closing and reassigning a posting are all one permission.
  static const jobUpdate = 'JOB_POSTING_UPDATE';

  static const applicationView = 'APPLICATION_VIEW';

  /// Moving an application along, scoring it, and every interview and offer
  /// action share this one code.
  static const applicationUpdate = 'APPLICATION_UPDATE';

  static const jobCreate = 'JOB_POSTING_CREATE';

  /// Deleting an application, and deleting a candidate, are the same code —
  /// and a different one from APPLICATION_UPDATE, which covers everything else
  /// the hiring screens do.
  static const applicationDelete = 'APPLICATION_DELETE';

  /// Hiring is gated on **EMPLOYEE_CREATE**, not APPLICATION_UPDATE — it
  /// creates a person, not a status change. Named here so the distinction is
  /// visible even though the app does not offer the action.
  static const hire = 'EMPLOYEE_CREATE';
}

/// Interview rounds, in the order a candidate meets them.
const interviewRounds = <String>['SCREENING', 'TECHNICAL', 'HR', 'FINAL'];

/// How the interview happens. VIDEO is the backend's default when none is
/// sent, and the one most interviews actually are.
const interviewModes = <String>['VIDEO', 'ONSITE', 'PHONE'];

/// Where a candidate came from — the backend's `ApplicationSource`.
const applicationSources = <String>[
  'CAREER_PAGE',
  'LINKEDIN',
  'FACEBOOK',
  'JOB_PORTAL',
  'EMPLOYEE_REFERRAL',
  'AGENCY',
  'DIRECT',
  'OTHER',
];

// The employment types a posting can advertise are the backend's
// `EmploymentType` — the same list an employee record carries. It lives in
// `directory_models.dart` as `employmentTypes` and is not repeated here: one
// list tracking one enum is the only way it stays right.

abstract final class JobPostingStatus {
  static const draft = 'DRAFT';
  static const open = 'OPEN';
  static const closed = 'CLOSED';
  static const onHold = 'ON_HOLD';
}

/// The hiring pipeline, in the order an application travels.
abstract final class ApplicationStatus {
  static const applied = 'APPLIED';
  static const screening = 'SCREENING';
  static const shortlisted = 'SHORTLISTED';
  static const interviewScheduled = 'INTERVIEW_SCHEDULED';
  static const interviewed = 'INTERVIEWED';
  static const selected = 'SELECTED';
  static const offerPending = 'OFFER_PENDING';
  static const offerSent = 'OFFER_SENT';
  static const offerAccepted = 'OFFER_ACCEPTED';
  static const offerRejected = 'OFFER_REJECTED';
  static const hired = 'HIRED';
  static const rejected = 'REJECTED';
  static const withdrawn = 'WITHDRAWN';

  /// Offered as filters and as next steps, in pipeline order.
  static const pipeline = [
    applied,
    screening,
    shortlisted,
    interviewScheduled,
    interviewed,
    selected,
    offerPending,
    offerSent,
    offerAccepted,
  ];

  /// Nobody is waiting on these — the application is finished either way.
  static const terminal = {hired, rejected, withdrawn, offerRejected};
}

class JobPosting {
  const JobPosting({
    required this.id,
    required this.title,
    required this.status,
    required this.vacancies,
    this.jobTitle,
    this.location,
    this.employmentType,
    this.departmentName,
    this.deadline,
    this.remote = false,
    this.assignedRecruiterName,
    this.description,
    this.requirements,
    this.responsibilities,
    this.salaryMin,
    this.salaryMax,
  });

  final int id;
  final String title;
  final String status;
  final int vacancies;
  final String? jobTitle;
  final String? location;
  final String? employmentType;
  final String? departmentName;
  final String? deadline;
  final bool remote;
  final String? assignedRecruiterName;
  final String? description;
  final String? requirements;
  final String? responsibilities;
  final num? salaryMin;
  final num? salaryMax;

  bool get isDraft => status == JobPostingStatus.draft;
  bool get isOpen => status == JobPostingStatus.open;
  bool get isClosed => status == JobPostingStatus.closed;

  /// A draft is not visible to candidates yet; publishing is what opens it.
  bool get canPublish => isDraft || status == JobPostingStatus.onHold;
  bool get canClose => !isClosed;

  /// Past its deadline while still accepting applications — the posting is
  /// live on the careers page and shouldn't be.
  bool get deadlinePassed {
    if (!isOpen) return false;
    final date = DateTime.tryParse(deadline ?? '');
    if (date == null) return false;
    return DateTime.now().isAfter(date);
  }

  String? get whereLabel {
    if (remote) return location == null ? 'Remote' : 'Remote · $location';
    return location;
  }

  factory JobPosting.fromJson(Map<String, dynamic> json) => JobPosting(
        id: (json['id'] as num?)?.toInt() ?? 0,
        // The DTO carries both a posting title and the role's job title; the
        // posting title is the headline and the other is a fallback.
        title: json['title'] as String? ??
            json['jobTitle'] as String? ??
            'Untitled posting',
        status: json['status'] as String? ?? JobPostingStatus.draft,
        vacancies: (json['vacancies'] as num?)?.toInt() ?? 0,
        jobTitle: json['jobTitle'] as String?,
        location: json['location'] as String?,
        employmentType: json['employmentType'] as String?,
        departmentName: json['departmentName'] as String?,
        deadline: json['deadline'] as String?,
        remote: json['remote'] as bool? ?? false,
        assignedRecruiterName: json['assignedRecruiterName'] as String?,
        description: json['description'] as String?,
        requirements: json['requirements'] as String?,
        responsibilities: json['responsibilities'] as String?,
        salaryMin: json['salaryMin'] as num?,
        salaryMax: json['salaryMax'] as num?,
      );
}

class JobApplication {
  const JobApplication({
    required this.id,
    required this.status,
    this.candidateId,
    this.candidateName,
    this.candidateEmail,
    this.candidatePhone,
    this.jobPostingId,
    this.jobPostingTitle,
    this.source,
    this.notes,
    this.resumeUrl,
    this.linkedInUrl,
    this.portfolioUrl,
    this.reviewedByName,
    this.scoreEducation,
    this.scoreExperience,
    this.scoreTechnicalSkills,
    this.scoreInterview,
    this.scoreCommunication,
    this.overallScore,
    this.atsScore,
  });

  final int id;
  final String status;
  final int? candidateId;
  final String? candidateName;
  final String? candidateEmail;
  final String? candidatePhone;
  final int? jobPostingId;
  final String? jobPostingTitle;
  final String? source;
  final String? notes;
  final String? resumeUrl;
  final String? linkedInUrl;
  final String? portfolioUrl;
  final String? reviewedByName;

  /// The five manual scores, each nullable until somebody sets them.
  final int? scoreEducation;
  final int? scoreExperience;
  final int? scoreTechnicalSkills;
  final int? scoreInterview;
  final int? scoreCommunication;

  /// Averaged server-side from whichever scores are set.
  final double? overallScore;

  /// From CV parsing, not from a human. Kept visibly separate from
  /// [overallScore] because the two mean very different things.
  final int? atsScore;

  String get personLabel => candidateName?.trim().isNotEmpty == true
      ? candidateName!.trim()
      : 'Candidate #${candidateId ?? id}';

  bool get isTerminal => ApplicationStatus.terminal.contains(status);
  bool get isHired => status == ApplicationStatus.hired;

  bool get hasScores =>
      scoreEducation != null ||
      scoreExperience != null ||
      scoreTechnicalSkills != null ||
      scoreInterview != null ||
      scoreCommunication != null;

  /// The statuses worth offering next.
  ///
  /// Terminal applications offer nothing — reopening one is not a transition
  /// the backend models — and the current status is left out so the list is
  /// only ever a move, never a no-op.
  List<String> get nextStatuses {
    if (isTerminal) return const [];
    return [
      ...ApplicationStatus.pipeline.where((s) => s != status),
      ApplicationStatus.rejected,
      ApplicationStatus.withdrawn,
    ];
  }

  /// Matches `TalentPoolController.fromApplication`'s own check exactly: only
  /// someone who did not go on to join is worth keeping warm for next time.
  bool get canPoolCandidate =>
      status == ApplicationStatus.rejected ||
      status == ApplicationStatus.withdrawn ||
      status == ApplicationStatus.offerRejected;

  factory JobApplication.fromJson(Map<String, dynamic> json) => JobApplication(
        id: (json['id'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? ApplicationStatus.applied,
        candidateId: (json['candidateId'] as num?)?.toInt(),
        candidateName: json['candidateName'] as String?,
        candidateEmail: json['candidateEmail'] as String?,
        candidatePhone: json['candidatePhone'] as String?,
        jobPostingId: (json['jobPostingId'] as num?)?.toInt(),
        jobPostingTitle: json['jobPostingTitle'] as String?,
        source: json['source'] as String?,
        notes: json['notes'] as String?,
        resumeUrl: json['resumeUrl'] as String?,
        linkedInUrl: json['linkedInUrl'] as String?,
        portfolioUrl: json['portfolioUrl'] as String?,
        reviewedByName: json['reviewedByName'] as String?,
        scoreEducation: (json['scoreEducation'] as num?)?.toInt(),
        scoreExperience: (json['scoreExperience'] as num?)?.toInt(),
        scoreTechnicalSkills: (json['scoreTechnicalSkills'] as num?)?.toInt(),
        scoreInterview: (json['scoreInterview'] as num?)?.toInt(),
        scoreCommunication: (json['scoreCommunication'] as num?)?.toInt(),
        overallScore: (json['overallScore'] as num?)?.toDouble(),
        atsScore: (json['atsScore'] as num?)?.toInt(),
      );
}

abstract final class InterviewStatus {
  static const scheduled = 'SCHEDULED';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';
  static const noShow = 'NO_SHOW';
}

class Interview {
  const Interview({
    required this.id,
    required this.jobApplicationId,
    required this.status,
    this.applicantName,
    this.jobTitle,
    this.round,
    this.scheduledAt,
    this.durationMinutes,
    this.mode,
    this.meetingLink,
    this.interviewerName,
    this.rating,
    this.strengths,
    this.concerns,
    this.recommendation,
  });

  final int id;
  final int jobApplicationId;
  final String status;
  final String? applicantName;
  final String? jobTitle;
  final String? round;
  final String? scheduledAt;
  final int? durationMinutes;
  final String? mode;
  final String? meetingLink;
  final String? interviewerName;
  final int? rating;
  final String? strengths;
  final String? concerns;
  final String? recommendation;

  bool get isScheduled => status == InterviewStatus.scheduled;
  bool get hasFeedback => rating != null || recommendation != null;

  DateTime? get when => DateTime.tryParse(scheduledAt ?? '');

  /// Still scheduled but the slot has passed — somebody owes feedback.
  bool get awaitingFeedback {
    final at = when;
    return isScheduled && at != null && DateTime.now().isAfter(at);
  }

  bool get isToday {
    final at = when;
    if (at == null) return false;
    final now = DateTime.now();
    return at.year == now.year && at.month == now.month && at.day == now.day;
  }

  factory Interview.fromJson(Map<String, dynamic> json) => Interview(
        id: (json['id'] as num?)?.toInt() ?? 0,
        jobApplicationId: (json['jobApplicationId'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? InterviewStatus.scheduled,
        applicantName: json['applicantName'] as String?,
        jobTitle: json['jobTitle'] as String?,
        round: json['round'] as String?,
        scheduledAt: json['scheduledAt'] as String?,
        durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
        mode: json['mode'] as String?,
        meetingLink: json['meetingLink'] as String?,
        interviewerName: json['interviewerName'] as String?,
        rating: (json['rating'] as num?)?.toInt(),
        strengths: json['strengths'] as String?,
        concerns: json['concerns'] as String?,
        recommendation: json['recommendation'] as String?,
      );
}

abstract final class OfferStatus {
  static const draft = 'DRAFT';
  static const sent = 'SENT';
  static const accepted = 'ACCEPTED';
  static const declined = 'DECLINED';
  static const withdrawn = 'WITHDRAWN';
}

class JobOffer {
  const JobOffer({
    required this.id,
    required this.jobApplicationId,
    required this.status,
    required this.expired,
    this.applicantName,
    this.jobPostingTitle,
    this.offeredJobTitle,
    this.joiningDate,
    this.expiryDate,
    this.grossSalary,
    this.sentAt,
    this.decidedAt,
    this.declineReason,
  });

  final int id;
  final int jobApplicationId;
  final String status;

  /// Computed server-side: a SENT offer past its expiry date. Expiry is not a
  /// stored status, so this is the only thing that says so — re-deriving it
  /// from the date here would risk disagreeing with the server.
  final bool expired;

  final String? applicantName;
  final String? jobPostingTitle;
  final String? offeredJobTitle;
  final String? joiningDate;
  final String? expiryDate;
  final num? grossSalary;
  final String? sentAt;
  final String? decidedAt;
  final String? declineReason;

  bool get isDraft => status == OfferStatus.draft;
  bool get isSent => status == OfferStatus.sent;

  /// Awaiting an answer. An expired offer is still SENT server-side but is not
  /// something to keep waiting on.
  bool get isPending => isSent && !expired;

  bool get isSettled =>
      status == OfferStatus.accepted ||
      status == OfferStatus.declined ||
      status == OfferStatus.withdrawn;

  /// What the chip should say. The stored status alone would show an expired
  /// offer as merely "Sent".
  String get displayStatus => expired && isSent ? 'EXPIRED' : status;

  factory JobOffer.fromJson(Map<String, dynamic> json) => JobOffer(
        id: (json['id'] as num?)?.toInt() ?? 0,
        jobApplicationId: (json['jobApplicationId'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? OfferStatus.draft,
        expired: json['expired'] as bool? ?? false,
        applicantName: json['applicantName'] as String?,
        jobPostingTitle: json['jobPostingTitle'] as String?,
        offeredJobTitle: json['offeredJobTitle'] as String?,
        joiningDate: json['joiningDate'] as String?,
        expiryDate: json['expiryDate'] as String?,
        grossSalary: json['grossSalary'] as num?,
        sentAt: json['sentAt'] as String?,
        decidedAt: json['decidedAt'] as String?,
        declineReason: json['declineReason'] as String?,
      );
}

/// The person, independent of any one application — `JobApplication` above is
/// the per-job pipeline state; this is what stays true across all of them.
class Candidate {
  const Candidate({
    required this.id,
    required this.name,
    required this.applicationCount,
    this.email,
    this.phone,
    this.resumeUrl,
    this.linkedInUrl,
    this.portfolioUrl,
    this.currentTitle,
    this.skills,
    this.source,
  });

  final int id;
  final String name;
  final int applicationCount;
  final String? email;
  final String? phone;
  final String? resumeUrl;
  final String? linkedInUrl;
  final String? portfolioUrl;
  final String? currentTitle;
  final String? skills;
  final String? source;

  factory Candidate.fromJson(Map<String, dynamic> json) => Candidate(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'Unnamed candidate',
        applicationCount: (json['applicationCount'] as num?)?.toInt() ?? 0,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        resumeUrl: json['resumeUrl'] as String?,
        linkedInUrl: json['linkedInUrl'] as String?,
        portfolioUrl: json['portfolioUrl'] as String?,
        currentTitle: json['currentTitle'] as String?,
        skills: json['skills'] as String?,
        source: json['source'] as String?,
      );
}

abstract final class TalentPoolReason {
  static const futureFit = 'FUTURE_FIT';
  static const declinedOffer = 'DECLINED_OFFER';
  static const noVacancy = 'NO_VACANCY';
  static const withdrew = 'WITHDREW';
  static const referral = 'REFERRAL';
  static const other = 'OTHER';

  /// Roughly how often each one comes up, so the common answers are the ones
  /// you do not have to scroll for.
  static const all = [
    futureFit,
    noVacancy,
    declinedOffer,
    referral,
    withdrew,
    other,
  ];
}

/// Shorthand for [TalentPoolReason.all], matching the other option lists here.
const talentPoolReasons = TalentPoolReason.all;

/// A candidate parked for a future opening — usually someone good who did not
/// end up joining this time. `sourceApplicationId`/`sourceJobTitle` are set
/// only when they arrived via the one-click "add from application" action.
class TalentPoolCandidate {
  const TalentPoolCandidate({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.resumeUrl,
    this.linkedInUrl,
    this.desiredRole,
    this.skills,
    this.rating,
    this.reason,
    this.notes,
    this.sourceJobTitle,
  });

  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? resumeUrl;
  final String? linkedInUrl;
  final String? desiredRole;
  final String? skills;
  final int? rating;
  final String? reason;
  final String? notes;
  final String? sourceJobTitle;

  factory TalentPoolCandidate.fromJson(Map<String, dynamic> json) =>
      TalentPoolCandidate(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'Unnamed candidate',
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        resumeUrl: json['resumeUrl'] as String?,
        linkedInUrl: json['linkedInUrl'] as String?,
        desiredRole: json['desiredRole'] as String?,
        skills: json['skills'] as String?,
        rating: (json['rating'] as num?)?.toInt(),
        reason: json['reason'] as String?,
        notes: json['notes'] as String?,
        sourceJobTitle: json['sourceJobTitle'] as String?,
      );
}

/// POST /recruitment/jobs
///
/// The controller takes this body **without `@Valid`**, so the `@NotBlank` on
/// the title is never actually enforced — the service is what rejects a bad
/// posting. The title is still required here, because a posting without one is
/// useless to everyone who reads it.
class JobPostingRequest {
  const JobPostingRequest({
    required this.title,
    this.jobTitle,
    this.location,
    this.employmentType,
    this.vacancies,
    this.salaryMin,
    this.salaryMax,
    this.deadline,
    this.remote = false,
    this.description,
    this.requirements,
    this.responsibilities,
  });

  final String title;
  final String? jobTitle;
  final String? location;
  final String? employmentType;
  final int? vacancies;
  final double? salaryMin;
  final double? salaryMax;
  final String? deadline;
  final bool remote;
  final String? description;
  final String? requirements;
  final String? responsibilities;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'title': title.trim(),
      // A primitive `boolean` on the DTO, so it defaults to false server-side
      // anyway — sent explicitly because "not remote" is a real answer here,
      // not an absence.
      'remote': remote,
      if (clean(jobTitle) != null) 'jobTitle': clean(jobTitle),
      if (clean(location) != null) 'location': clean(location),
      if (employmentType != null) 'employmentType': employmentType,
      if (vacancies != null) 'vacancies': vacancies,
      if (salaryMin != null) 'salaryMin': salaryMin,
      if (salaryMax != null) 'salaryMax': salaryMax,
      if (deadline != null) 'deadline': deadline,
      if (clean(description) != null) 'description': clean(description),
      if (clean(requirements) != null) 'requirements': clean(requirements),
      if (clean(responsibilities) != null)
        'responsibilities': clean(responsibilities),
    };
  }
}

/// POST /recruitment/interviews
///
/// `scheduledAt` and `interviewerId` are both required — the controller checks
/// them by hand and answers 400 with a plain message rather than a field error,
/// so they are required here too and never sent absent.
///
/// `scheduledAt` is a `LocalDateTime`: a wall clock with no zone, seconds
/// included. Sending an instant with a `Z` or an offset would be read as a
/// different time by everyone not on UTC.
class InterviewRequest {
  const InterviewRequest({
    required this.jobApplicationId,
    required this.scheduledAt,
    required this.interviewerId,
    this.round,
    this.durationMinutes,
    this.mode,
    this.meetingLink,
  });

  final int jobApplicationId;
  final String scheduledAt;
  final int interviewerId;
  final String? round;
  final int? durationMinutes;
  final String? mode;
  final String? meetingLink;

  Map<String, dynamic> toJson() {
    final link = meetingLink?.trim();

    return {
      'jobApplicationId': jobApplicationId,
      'scheduledAt': scheduledAt,
      'interviewerId': interviewerId,
      if (round != null) 'round': round,
      if (durationMinutes != null) 'durationMinutes': durationMinutes,
      if (mode != null) 'mode': mode,
      if (link != null && link.isNotEmpty) 'meetingLink': link,
    };
  }
}

/// POST /recruitment/offers
///
/// Three fields are required and the DTO does not say so — the controller
/// checks them by hand and answers 400 with a sentence each. They are required
/// here instead, so the form can ask for them rather than the server refusing
/// after the fact:
///
/// * `offeredJobTitle` — an offer has to name the job.
/// * `expiryDate` — "an offer with no expiry never forces a decision".
/// * `grossSalary` — an offer has to name the money.
///
/// Two more refusals the form cannot prevent, only report: the application must
/// not be closed, and it may hold only one live offer at a time.
class OfferRequest {
  const OfferRequest({
    required this.jobApplicationId,
    required this.offeredJobTitle,
    required this.expiryDate,
    required this.grossSalary,
    this.joiningDate,
    this.basicSalary,
    this.houseRent,
    this.medicalAllowance,
    this.transportAllowance,
    this.notes,
  });

  final int jobApplicationId;
  final String offeredJobTitle;
  final String expiryDate;
  final double grossSalary;
  final String? joiningDate;
  final double? basicSalary;
  final double? houseRent;
  final double? medicalAllowance;
  final double? transportAllowance;
  final String? notes;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'jobApplicationId': jobApplicationId,
      'offeredJobTitle': offeredJobTitle.trim(),
      'expiryDate': expiryDate,
      'grossSalary': grossSalary,
      if (joiningDate != null) 'joiningDate': joiningDate,
      if (basicSalary != null) 'basicSalary': basicSalary,
      if (houseRent != null) 'houseRent': houseRent,
      if (medicalAllowance != null) 'medicalAllowance': medicalAllowance,
      if (transportAllowance != null)
        'transportAllowance': transportAllowance,
      if (clean(notes) != null) 'notes': clean(notes),
    };
  }
}

/// PUT /recruitment/candidates/{id}
///
/// **Almost every field here is sent whether or not it has a value.**
/// `CandidateServiceImpl.update` assigns phone, resumeUrl, linkedInUrl,
/// portfolioUrl, currentTitle, skills and notes *unconditionally* — an omitted
/// key is not "leave it alone", it is `set(null)`. Only name, email and source
/// are guarded. So the form seeds from the current record and posts the whole
/// thing back, which also makes an emptied box mean what it looks like it
/// means: clear that field.
///
/// Not to be confused with [TalentPoolRequest]. The backend has two unrelated
/// classes both called `CandidateRequest`, with different fields.
class CandidateRequest {
  const CandidateRequest({
    required this.name,
    this.email,
    this.phone,
    this.currentTitle,
    this.skills,
    this.source,
    this.resumeUrl,
    this.linkedInUrl,
    this.portfolioUrl,
    this.notes,
  });

  final String name;
  final String? email;
  final String? phone;
  final String? currentTitle;
  final String? skills;
  final String? source;
  final String? resumeUrl;
  final String? linkedInUrl;
  final String? portfolioUrl;
  final String? notes;

  factory CandidateRequest.from(Candidate candidate) => CandidateRequest(
        name: candidate.name,
        email: candidate.email,
        phone: candidate.phone,
        currentTitle: candidate.currentTitle,
        skills: candidate.skills,
        source: candidate.source,
        resumeUrl: candidate.resumeUrl,
        linkedInUrl: candidate.linkedInUrl,
        portfolioUrl: candidate.portfolioUrl,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'name': name.trim(),
      // Guarded server-side, so only sent when there is something to say.
      if (clean(email) != null) 'email': clean(email),
      if (source != null) 'source': source,
      // Unconditional: see the class comment.
      'phone': clean(phone),
      'currentTitle': clean(currentTitle),
      'skills': clean(skills),
      'resumeUrl': clean(resumeUrl),
      'linkedInUrl': clean(linkedInUrl),
      'portfolioUrl': clean(portfolioUrl),
      'notes': clean(notes),
    };
  }
}

/// POST /recruitment/talent-pool and PUT /recruitment/talent-pool/{id}
///
/// A different shape from [CandidateRequest] despite the backend calling both
/// classes `CandidateRequest`: this one carries `desiredRole`, `rating` and
/// `reason`, and has no `portfolioUrl`, `currentTitle` or `source`.
///
/// **Email is required**, unlike on a candidate — the controller validates it
/// and then calls `.trim()` on it unguarded. `rating` is refused outside 1–5.
///
/// Everything except `reason` is assigned unconditionally by `apply()`, so the
/// whole record is posted back on an edit for the same reason as above.
class TalentPoolRequest {
  const TalentPoolRequest({
    required this.name,
    required this.email,
    this.phone,
    this.resumeUrl,
    this.linkedInUrl,
    this.desiredRole,
    this.skills,
    this.rating,
    this.reason,
    this.notes,
  });

  final String name;
  final String email;
  final String? phone;
  final String? resumeUrl;
  final String? linkedInUrl;
  final String? desiredRole;
  final String? skills;
  final int? rating;
  final String? reason;
  final String? notes;

  factory TalentPoolRequest.from(TalentPoolCandidate entry) =>
      TalentPoolRequest(
        name: entry.name,
        email: entry.email ?? '',
        phone: entry.phone,
        resumeUrl: entry.resumeUrl,
        linkedInUrl: entry.linkedInUrl,
        desiredRole: entry.desiredRole,
        skills: entry.skills,
        rating: entry.rating,
        reason: entry.reason,
        notes: entry.notes,
      );

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'name': name.trim(),
      'email': email.trim(),
      if (reason != null) 'reason': reason,
      // Unconditional: see the class comment.
      'phone': clean(phone),
      'resumeUrl': clean(resumeUrl),
      'linkedInUrl': clean(linkedInUrl),
      'desiredRole': clean(desiredRole),
      'skills': clean(skills),
      'rating': rating,
      'notes': clean(notes),
    };
  }
}

/// **Hiring is deliberately not in the app.**
///
/// `POST /recruitment/applications/{id}/hire` turns a candidate into an
/// employee and creates their login in one call — and its `password` field is
/// `@NotBlank`, so whoever hires has to set the new starter's password there
/// and then. There is no invite-and-let-them-choose path on that endpoint.
///
/// Typing somebody else's initial password into a phone, in front of whoever
/// is in the room, and then having to pass it on out of band, is worse than
/// doing it at a desk. The rest of the pipeline — screening, interviewing,
/// offering — is here; the last step stays on the web.

/// GET /recruitment/kpis
///
/// How hiring is going. Every rate is nullable, and a null is not zero — an
/// offer acceptance rate with no offers made is undefined, and showing it as
/// nought would say something untrue about the recruiters.
class RecruitmentKpis {
  const RecruitmentKpis({
    required this.openPositions,
    required this.totalCandidates,
    required this.totalApplications,
    required this.hiresThisMonth,
    required this.hiresTotal,
    this.avgTimeToHireDays,
    this.avgTimeToFillDays,
    this.applicationToInterviewRate,
    this.interviewToHireRate,
    this.offerAcceptanceRate,
    this.avgAtsMatchScore,
    this.funnel = const [],
    this.sourceBreakdown = const [],
  });

  final int openPositions;
  final int totalCandidates;
  final int totalApplications;
  final int hiresThisMonth;
  final int hiresTotal;
  final double? avgTimeToHireDays;
  final double? avgTimeToFillDays;
  final double? applicationToInterviewRate;
  final double? interviewToHireRate;
  final double? offerAcceptanceRate;
  final double? avgAtsMatchScore;

  /// The hiring funnel, stage by stage, in the order the backend sends them.
  final List<KpiCount> funnel;

  /// Where applications came from.
  final List<KpiCount> sourceBreakdown;

  /// The per-job and per-recruiter breakdowns and the top-candidate list are
  /// deliberately not modelled: they are wide comparison tables, and half a
  /// comparison on a phone is worse than none.
  factory RecruitmentKpis.fromJson(Map<String, dynamic> json) {
    List<KpiCount> counts(String key, String labelField) => [
          for (final row in (json[key] as List? ?? const []))
            if (row is Map<String, dynamic>)
              KpiCount(
                label: row[labelField] as String? ?? '',
                count: (row['count'] as num?)?.toInt() ?? 0,
              ),
        ];

    return RecruitmentKpis(
      openPositions: (json['openPositions'] as num?)?.toInt() ?? 0,
      totalCandidates: (json['totalCandidates'] as num?)?.toInt() ?? 0,
      totalApplications: (json['totalApplications'] as num?)?.toInt() ?? 0,
      hiresThisMonth: (json['hiresThisMonth'] as num?)?.toInt() ?? 0,
      hiresTotal: (json['hiresTotal'] as num?)?.toInt() ?? 0,
      avgTimeToHireDays: (json['avgTimeToHireDays'] as num?)?.toDouble(),
      avgTimeToFillDays: (json['avgTimeToFillDays'] as num?)?.toDouble(),
      applicationToInterviewRate:
          (json['applicationToInterviewRate'] as num?)?.toDouble(),
      interviewToHireRate: (json['interviewToHireRate'] as num?)?.toDouble(),
      offerAcceptanceRate: (json['offerAcceptanceRate'] as num?)?.toDouble(),
      avgAtsMatchScore: (json['avgAtsMatchScore'] as num?)?.toDouble(),
      funnel: counts('funnel', 'stage'),
      sourceBreakdown: counts('sourceBreakdown', 'source'),
    );
  }
}

/// One labelled count, for the funnel and the source breakdown.
class KpiCount {
  const KpiCount({required this.label, required this.count});

  final String label;
  final int count;
}
