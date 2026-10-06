import { SecureFilePipe } from '../../../../shared/pipes/secure-file.pipe';
import { Component, OnInit, OnDestroy, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { Proposal, ProposalRequest, RequestComment, RequestStatusHistoryResponse, ServiceRequest, StageApproval, StageProgressResponse } from '../../models/servicedesk.model';
import { ServiceRequestService, RequestDocument } from '../../services/service-request.service';
import { ServiceFormFieldService } from '../../services/service-form-field.service';
import { ProposalService } from '../../services/proposal.service';
import { ApprovalService } from '../../services/approval.service';
import { AuthService } from '../../../../core/services/auth.service';
import { ChatSocketService } from '../../../../core/services/chat-socket.service';
import { ChatThread, ChatMessage } from '../../../../shared/components/chat-thread/chat-thread';
import { EmployeeService } from '../../../hrm/services/employee.service';
import { Employee } from '../../../hrm/models/hrm.model';
import { ApiService } from '../../../../core/services/api.service';
import { ConfirmDialog } from '../../../../shared/components/confirm-dialog/confirm-dialog';
import { HasPermissionDirective } from '../../../../shared/directives/has-permission.directive';

// Mirror of backend ServiceRequestStatus / TaskStatus enums
const REQUEST_STATUSES = ['PENDING', 'QUOTATION_PENDING', 'ASSIGNED', 'IN_PROGRESS',
  'WAITING_CLIENT', 'UNDER_REVIEW', 'COMPLETED', 'REJECTED', 'CANCELLED', 'RESUBMITTED'] as const;
const TASK_STATUSES = ['PENDING', 'IN_PROGRESS', 'COMPLETED', 'BLOCKED', 'CANCELLED'] as const;

/** Extensions worth rendering as a thumbnail when the stored URL happens to carry one; see showsImagePreview(). */
const IMAGE_EXTENSIONS = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'avif'];

@Component({
  selector: 'app-request-detail',
  imports: [SecureFilePipe, CommonModule, FormsModule, RouterLink, HasPermissionDirective, ChatThread, ConfirmDialog],
  templateUrl: './request-detail.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './request-detail.scss',
})
export class RequestDetail implements OnInit, OnDestroy {
  requestId!: number;
  request?: ServiceRequest;
  approvals: StageApproval[] = [];
  comments: RequestComment[] = [];
  // Typed, not any[]: the panel below read `actorName` and `createdAt`, which this DTO has never had, and
  // `any` is what let both names through the compiler.
  history: RequestStatusHistoryResponse[] = [];
  posting = false;

  draftNotes = '';
  draftedReply = '';
  drafting = false;
  draftError = '';

  // Client's dynamic form answers with labels resolved from the field definitions
  formAnswers: { label: string; value: string }[] = [];
  error = '';
  info = '';

  // Staff manage the lifecycle; clients can cancel their own request
  isStaff = false;
  isClient = false;
  // Quotation accept/reject is CLIENT or COMPANY_OWNER (owner acting on the client's behalf)
  canDecideQuotation = false;

  // Status / assignment (staff)
  requestStatuses = REQUEST_STATUSES;
  newStatus = '';
  statusReason = '';
  employees: Employee[] = [];
  assignEmployeeId: number | null = null;
  // An assigned request shows read-only text; this flips to true to reveal the dropdown for reassigning.
  editingAssignment = false;
  // Cancelling ends the whole request and cannot be undone from here, so it goes through app-confirm-dialog.
  cancelling = false;

  // Tasks (staff)
  tasks: any[] = [];
  taskStatuses = TASK_STATUSES;
  newTask: any = { title: '', assignedEmployeeId: null, dueDate: '', priority: 'NORMAL', estimatedHours: null, description: '' };
  showTaskForm = false;

  // Quotation (embedded on the service request - there is no standalone Quotation endpoint)
  quotationForm = { amount: 0, currency: 'BDT', notes: '', validUntil: '' };
  rejectReason = '';

  // Documents (client or staff can attach files - budget docs, requirements, deliverables)
  documents: RequestDocument[] = [];
  uploading = false;
  documentLabel = '';

  summarising = false;
  summaryError = '';

  // Pre-sales proposal (staff draft/send, client accept/request-changes)
  proposal: Proposal | null = null;
  editingProposal = false;
  proposalForm: ProposalRequest = { title: '' };
  proposalSaving = false;
  proposalError = '';
  changesFeedback = '';
  showChangesForm = false;
  uploadingProposalFile = false;

  // Staff advance a request through the service's workflow stages; clients see the same panel read-only.
  stageProgress: StageProgressResponse | null = null;
  advancingStage = false;

  // Government filing reference, recorded once staff submit the request to an authority (RJSC, City Corporation, NBR, ...).
  editingGovRef = false;
  govRefForm = { govRefNumber: '', govRefType: '' };
  savingGovRef = false;

  constructor(
    private route: ActivatedRoute,
    private requestService: ServiceRequestService,
    private approvalService: ApprovalService,
    private formFieldService: ServiceFormFieldService,
    private proposalService: ProposalService,
    private auth: AuthService,
    private employeeService: EmployeeService,
    private api: ApiService,
    private cdr: ChangeDetectorRef,
    private chatSocket: ChatSocketService,
  ) {}

  private chatUnsubscribe?: () => void;

  get chatConnected(): boolean {
    return this.chatSocket.connected;
  }

  // ChatThread wants oldest-first bubbles, but the API returns newest-first; INTERNAL comments get the "Internal note" pill.
  // Cached as a property, not a getter: remapping on every template read handed ChatThread a new array each change-detection tick, which it read as new messages and auto-scrolled the page.
  chatMessages: ChatMessage[] = [];

  private syncChatMessages(): void {
    this.chatMessages = [...this.comments].reverse().map((c) => ({
      id: c.id,
      authorId: c.authorId ?? 0,
      authorName: c.authorName || 'Unknown',
      content: c.content,
      createdAt: c.createdAt,
      internal: c.visibility === 'INTERNAL',
    }));
  }

  get currentUserId(): number | null {
    return this.auth.getCurrentUser()?.id ?? null;
  }

  // Answers are keyed by field id; labels come from the service's field definitions, and fields deleted since submission fall back to "Field {id}".
  private resolveFormAnswers(r: ServiceRequest): void {
    this.formAnswers = [];
    if (!r.formData || !Object.keys(r.formData).length || !r.hubServiceId) return;
    this.formFieldService.list(r.hubServiceId).subscribe({
      next: (fields) => {
        const labels = new Map(fields.map((f) => [String(f.id), f.label]));
        this.formAnswers = Object.entries(r.formData!).map(([id, value]) => ({
          label: labels.get(id) || `Field ${id}`,
          value,
        }));
        this.cdr.markForCheck();
      },
      error: () => {
        this.formAnswers = Object.entries(r.formData!).map(([id, value]) => ({
          label: `Field ${id}`,
          value,
        }));
        this.cdr.markForCheck();
      },
    });
  }

  /**
   * True when a form answer is a stored file rather than typed text.
   * Uploads return a relative '/api/files/{id}' (legacy rows hold '/uploads/{name}' or an absolute URL of
   * whatever host served them), so accepting only http(s) showed every recent upload as the literal text
   * "/api/files/42". SecureFilePipe resolves all four shapes; see SecureFileService.apiPath.
   */
  isUrl(value: string): boolean {
    if (!value || typeof value !== 'string') return false;
    const v = value.trim();
    return v.startsWith('http://') || v.startsWith('https://')
      || v.startsWith('/api/files/') || v.startsWith('/api/public/files/') || v.startsWith('/uploads/');
  }

  /** Answers whose <img> has already failed to decode, so they are known not to be images. */
  private notAnImage = new Set<string>();

  /**
   * True while this answer should be shown as an image thumbnail.
   *
   * It cannot be decided from the stored string alone. Uploads return '/api/files/{id}' with no extension,
   * and ServiceRequests.onFieldFileUploaded stores only result.fileUrl - the upload response's fileName and
   * the StoredFile's contentType are both dropped there and there is no metadata endpoint to ask - so the
   * old extension sniff matched nothing and every image uploaded since gave the generic file tile.
   *
   * What does know the type is the response: FileServeController serves each file with its real
   * Content-Type. So a URL that could be an image is rendered as one, and onAnswerImageError() switches it
   * to the generic tile if the browser cannot decode it. A URL that carries an extension (legacy
   * '/uploads/{name}' rows and absolute URLs) is still settled up front, so no non-image is fetched twice.
   */
  showsImagePreview(value: string): boolean {
    if (!this.isUrl(value)) return false;
    if (this.notAnImage.has(value)) return false;
    const ext = this.extensionOf(value);
    return ext === null || IMAGE_EXTENSIONS.includes(ext);
  }

  /** The browser refused to decode it, so it is not an image whatever its URL looked like. */
  onAnswerImageError(value: string): void {
    this.notAnImage.add(value);
    this.cdr.markForCheck();
  }

  /** Lower-case extension of the URL's last path segment, or null when it has none to go on. */
  private extensionOf(value: string): string | null {
    const path = value.trim().split(/[?#]/)[0];
    const name = path.substring(path.lastIndexOf('/') + 1);
    const dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot + 1).toLowerCase() : null;
  }

  ngOnInit(): void {
    this.requestId = Number(this.route.snapshot.paramMap.get('id'));
    this.isStaff = this.auth.hasAnyRole(['COMPANY_OWNER', 'EMPLOYEE']);
    this.isClient = this.auth.hasRole('CLIENT');
    this.canDecideQuotation = this.isClient || this.auth.hasRole('COMPANY_OWNER');
    this.loadAll();
    if (this.isStaff) {
      this.employeeService.list(0, 100).subscribe({ next: (res) => {
        this.employees = res.content;
        this.cdr.markForCheck();
      } });
    }

    this.chatUnsubscribe = this.chatSocket.subscribe(
      `/user/queue/service-requests/${this.requestId}/messages`,
      (message: RequestComment) => {
        // Comments load newest-first, so a live one goes at the top; the guard avoids a duplicate when this tab is also the sender and loadAll() already refetched.
        if (this.comments.some((c) => c.id === message.id)) return;
        this.comments = [message, ...this.comments];
        this.syncChatMessages();
        this.cdr.markForCheck();
      },
    );
  }

  ngOnDestroy(): void {
    this.chatUnsubscribe?.();
  }

  loadAll(): void {
    this.requestService.getById(this.requestId).subscribe({
      next: (r) => {
        this.request = r;
        this.newStatus = r.status;
        this.assignEmployeeId = r.assignedEmployeeId || null;
        this.govRefForm = { govRefNumber: r.govRefNumber || '', govRefType: r.govRefType || '' };
        this.resolveFormAnswers(r);
        this.cdr.markForCheck();
      },
      error: () => {
        this.error = 'Failed to load request';
        this.cdr.markForCheck();
      },
    });
    this.requestService.stageProgress(this.requestId).subscribe({
      // A service with no workflow (or a final stage) still resolves server-side, so on a genuine error the panel just stays hidden.
      next: (sp) => { this.stageProgress = sp; this.cdr.markForCheck(); },
      error: () => { this.stageProgress = null; this.cdr.markForCheck(); },
    });
    this.loadProposal();
    this.approvalService
      .forRequest(this.requestId)
      .subscribe({ next: (a) => {
        this.approvals = a;
        this.cdr.markForCheck();
      } });
    this.requestService.comments(this.requestId).subscribe({ next: (c) => {
      this.comments = c.content;
      this.syncChatMessages();
      this.cdr.markForCheck();
    } });
    this.loadDocuments();
    // GET /{id}/tasks is tenant-scoped but not role-restricted, so clients can read their own tasks for the progress panel; History stays staff-only via @PreAuthorize.
    this.loadTasks();
    if (this.isStaff) {
      this.requestService.history(this.requestId).subscribe({ next: (h) => {
        this.history = h;
        this.groupHistory();
        this.cdr.markForCheck();
      } });
    }
  }

  /** Percentage of tasks completed - drives the client progress bar. */
  get progressPercent(): number {
    if (!this.tasks.length) return 0;
    const done = this.tasks.filter((t) => t.status === 'COMPLETED').length;
    return Math.round((done / this.tasks.length) * 100);
  }

  get completedTaskCount(): number {
    return this.tasks.filter((t) => t.status === 'COMPLETED').length;
  }

  /** Back link target - same role split as the Requests list's row links. */
  get listPath(): string {
    return this.isClient ? '/client/requests' : '/servicedesk/requests';
  }

  /** Badge colour for the request's own status, shown beside the title. */
  statusBadgeClass(status: string): string {
    switch (status) {
      case 'COMPLETED': return 'text-bg-success';
      case 'IN_PROGRESS':
      case 'ASSIGNED': return 'text-bg-primary';
      case 'QUOTATION_PENDING':
      case 'WAITING_CLIENT':
      case 'UNDER_REVIEW':
      case 'RESUBMITTED': return 'text-bg-warning';
      case 'REJECTED':
      case 'CANCELLED': return 'text-bg-danger';
      default: return 'text-bg-secondary';
    }
  }

  taskStatusClass(status: string): string {
    switch (status) {
      case 'COMPLETED': return 'text-bg-success';
      case 'IN_PROGRESS': return 'text-bg-primary';
      case 'CANCELLED': return 'text-bg-secondary';
      default: return 'text-bg-light text-dark border';
    }
  }

  /** The task currently being worked on - "which stage are we in" for the client. */
  get currentStageName(): string | null {
    const active = this.tasks.find((t) => t.status === 'IN_PROGRESS')
      ?? this.tasks.find((t) => t.status === 'PENDING');
    return active?.workflowStageName || active?.title || null;
  }

  /**
   * Consecutive entries by the same person, so the timeline names them once.
   *
   * `changedByName`, not `actorName`: RequestStatusHistoryResponse has never carried an `actorName`, so every
   * entry grouped under `undefined` and the panel labelled all of them "System" - including changes a named
   * person made. The `|| 'System'` in the template stays: the backend now stamps that name itself on rows a
   * scheduled job writes (the unpaid-request auto-cancellation), so it is a real value rather than a default
   * that swallowed everything.
   */
  // `items` stays loose: the template still carries `fromStatus || oldStatus` / `toStatus || newStatus`
  // fallbacks for a shape this DTO never had, and under strictTemplates a precise type would reject them.
  // `history` itself is typed, which is where the wrong field names actually were.
  groupedHistory: { actorName: string | undefined; items: any[] }[] = [];

  groupHistory(): void {
    this.groupedHistory = [];
    if (!this.history?.length) return;
    let currentGroup = { actorName: this.history[0].changedByName, items: [this.history[0]] };
    for (let i = 1; i < this.history.length; i++) {
      const item = this.history[i];
      if (item.changedByName === currentGroup.actorName) {
        currentGroup.items.push(item);
      } else {
        this.groupedHistory.push(currentGroup);
        currentGroup = { actorName: item.changedByName, items: [item] };
      }
    }
    this.groupedHistory.push(currentGroup);
  }

  loadTasks(): void {
    this.requestService.getTasks(this.requestId).subscribe({ next: (t) => {
      this.tasks = t;
      this.cdr.markForCheck();
    } });
  }


  changeStatus(): void {
    if (!this.request || !this.newStatus || this.newStatus === this.request.status) return;
    this.error = '';
    this.info = '';
    this.cdr.markForCheck();
    this.requestService.changeStatus(this.requestId, this.newStatus, this.statusReason || undefined).subscribe({
      next: (r) => {
        this.request = r;
        this.statusReason = '';
        this.info = 'Status updated';
        this.loadAll();
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to change status';
        this.cdr.markForCheck();
      },
    });
  }

  assign(): void {
    if (!this.assignEmployeeId) return;
    if (!confirm('Are you sure you want to assign this request to the selected employee?')) return;
    this.error = '';
    this.info = '';
    this.cdr.markForCheck();
    this.requestService.assign(this.requestId, this.assignEmployeeId).subscribe({
      next: (r) => {
        this.request = r;
        this.info = 'Assigned successfully';
        this.editingAssignment = false;
        this.loadAll();
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to assign';
        this.cdr.markForCheck();
      },
    });
  }


  /** Opens the confirmation; the cancellation itself is confirmCancel(). */
  cancel(): void {
    this.cancelling = true;
    this.cdr.markForCheck();
  }

  confirmCancel(): void {
    this.cancelling = false;
    this.error = '';
    this.info = '';
    this.cdr.markForCheck();
    this.requestService.cancel(this.requestId).subscribe({
      next: () => {
        this.info = 'Request cancelled';
        this.loadAll();
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to cancel request';
        this.cdr.markForCheck();
      },
    });
  }


  addTask(): void {
    if (!this.newTask.title?.trim() || !this.newTask.assignedEmployeeId || !this.newTask.dueDate) return;
    this.requestService.addTask(this.requestId, this.newTask).subscribe({
      next: () => {
        this.newTask = { title: '', assignedEmployeeId: null, dueDate: '', priority: 'NORMAL', estimatedHours: null, description: '' };
        this.showTaskForm = false;
        this.loadTasks();
        this.refreshRequestOnly();
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to create task';
        this.cdr.markForCheck();
      },
    });
  }

  setTaskStatus(task: any, status: string): void {
    if (status === task.status) return;
    this.requestService.updateTask(this.requestId, task.id, { status }).subscribe({
      next: () => {
        this.loadTasks();
        this.refreshRequestOnly();
      },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to update task';
        this.cdr.markForCheck();
      },
    });
  }

  deleteTask(task: any): void {
    this.requestService.deleteTask(this.requestId, task.id).subscribe({
      next: () => {
        this.loadTasks();
        this.refreshRequestOnly();
      },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to delete task';
        this.cdr.markForCheck();
      },
    });
  }

  private refreshRequestOnly(): void {
    this.requestService.getById(this.requestId).subscribe({ next: (r) => {
      this.request = r;
      this.cdr.markForCheck();
    } });
  }


  loadDocuments(): void {
    this.requestService.documents(this.requestId).subscribe({
      next: (docs) => { this.documents = docs; this.cdr.markForCheck(); },
    });
  }

  onFileSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    this.uploading = true;
    this.error = '';
    this.cdr.markForCheck();

    this.api.uploadFile(file, 'DOCUMENT').subscribe({
      next: (uploaded) => {
        this.requestService.addDocument(this.requestId, {
          fileName: uploaded.fileName,
          fileUrl: uploaded.fileUrl,
          fileType: file.type,
          fileSizeBytes: file.size,
          label: this.documentLabel.trim() || undefined,
        }).subscribe({
          next: () => {
            this.documentLabel = '';
            this.uploading = false;
            this.loadDocuments();
            this.cdr.markForCheck();
          },
          error: (err) => {
            this.error = err?.error?.message || 'Failed to attach document';
            this.uploading = false;
            this.cdr.markForCheck();
          },
        });
      },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to upload file';
        this.uploading = false;
        this.cdr.markForCheck();
      },
    });
    input.value = '';
  }

  deleteDocument(doc: RequestDocument): void {
    this.requestService.deleteDocument(this.requestId, doc.id).subscribe({
      next: () => { this.loadDocuments(); },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to delete document';
        this.cdr.markForCheck();
      },
    });
  }

  composeDraftReply(): void {
    const notes = this.draftNotes.trim();
    if (!notes || this.drafting) return;
    this.drafting = true;
    this.draftError = '';
    this.cdr.markForCheck();
    this.requestService.draftReply(this.requestId, notes).subscribe({
      next: (res) => {
        this.draftedReply = res.reply;
        this.drafting = false;
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.draftError = err?.error?.message || 'Could not draft a reply right now.';
        this.drafting = false;
        this.cdr.markForCheck();
      },
    });
  }

  sendDraftedReply(): void {
    if (!this.draftedReply.trim()) return;
    this.postChatMessage(this.draftedReply.trim());
    this.discardDraftedReply();
  }

  discardDraftedReply(): void {
    this.draftNotes = '';
    this.draftedReply = '';
    this.draftError = '';
    this.cdr.markForCheck();
  }

  postChatMessage(text: string): void {
    this.posting = true;
    this.cdr.markForCheck();
    // pushChatMessage only reaches the other party, so refetch for this tab to see its own message.
    this.requestService.addComment(this.requestId, text).subscribe({
      next: () => {
        this.posting = false;
        this.loadAll();
      },
      error: (err) => {
        this.posting = false;
        this.error = err?.error?.message || 'Failed to add comment';
        this.cdr.markForCheck();
      },
    });
  }

  submitQuotation(): void {
    this.error = '';
    this.info = '';
    this.cdr.markForCheck();
    this.requestService.submitQuotation(this.requestId, this.quotationForm).subscribe({
      next: (r) => {
        this.request = r;
        this.info = 'Quotation submitted';
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to submit quotation';
        this.cdr.markForCheck();
      },
    });
  }

  acceptQuotation(): void {
    this.error = '';
    this.info = '';
    this.cdr.markForCheck();
    this.requestService.acceptQuotation(this.requestId).subscribe({
      next: (r) => {
        this.request = r;
        this.info = 'Quotation accepted';
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to accept quotation';
        this.cdr.markForCheck();
      },
    });
  }

  rejectQuotation(): void {
    this.error = '';
    this.info = '';
    this.cdr.markForCheck();
    this.requestService.rejectQuotation(this.requestId, this.rejectReason || undefined).subscribe({
      next: (r) => {
        this.request = r;
        this.rejectReason = '';
        this.info = 'Quotation rejected';
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to reject quotation';
        this.cdr.markForCheck();
      },
    });
  }

  hasPendingApproval(): boolean {
    return this.approvals.some((a) => a.status === 'PENDING');
  }


  advanceStage(): void {
    if (this.advancingStage) return;
    this.advancingStage = true;
    this.error = '';
    this.cdr.markForCheck();
    this.requestService.advanceStage(this.requestId).subscribe({
      next: (r) => {
        this.request = r;
        this.advancingStage = false;
        this.info = 'Advanced to next stage';
        this.loadAll();
        this.cdr.markForCheck();
      },
      error: (err) => {
        // A stage requiring approval throws with a message pointing at the approvals queue, so surface it as-is rather than a generic failure.
        this.error = err?.error?.message || 'Failed to advance stage';
        this.advancingStage = false;
        this.cdr.markForCheck();
      },
    });
  }


  saveGovRef(): void {
    if (this.savingGovRef) return;
    this.savingGovRef = true;
    this.error = '';
    this.cdr.markForCheck();
    this.requestService.update(this.requestId, this.govRefForm).subscribe({
      next: (r) => {
        this.request = r;
        this.savingGovRef = false;
        this.editingGovRef = false;
        this.info = 'Filing reference saved';
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to save filing reference';
        this.savingGovRef = false;
        this.cdr.markForCheck();
      },
    });
  }

  summarise(): void {
    if (this.summarising) return;
    this.summarising = true;
    this.summaryError = '';
    this.cdr.markForCheck();
    this.requestService.summarise(this.requestId).subscribe({
      next: (r) => {
        if (this.request) this.request.aiSummary = r.aiSummary;
        this.summarising = false;
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.summaryError = err?.error?.message || 'Failed to generate summary';
        this.summarising = false;
        this.cdr.markForCheck();
      },
    });
  }


  loadProposal(): void {
    this.proposalService.get(this.requestId).subscribe({
      next: (p) => { this.proposal = p; this.cdr.markForCheck(); },
      error: () => { this.proposal = null; this.cdr.markForCheck(); },
    });
  }

  openProposalEditor(): void {
    this.proposalForm = this.proposal
      ? {
          title: this.proposal.title,
          techStack: this.proposal.techStack,
          timeline: this.proposal.timeline,
          summary: this.proposal.summary,
          estimatedBudget: this.proposal.estimatedBudget,
        }
      : { title: '' };
    this.editingProposal = true;
  }

  saveProposal(): void {
    if (!this.proposalForm.title?.trim() || this.proposalSaving) return;
    this.proposalSaving = true;
    this.proposalError = '';
    this.cdr.markForCheck();
    this.proposalService.save(this.requestId, this.proposalForm).subscribe({
      next: (p) => {
        this.proposal = p;
        this.editingProposal = false;
        this.proposalSaving = false;
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.proposalError = err?.error?.message || 'Failed to save proposal';
        this.proposalSaving = false;
        this.cdr.markForCheck();
      },
    });
  }

  sendProposal(): void {
    if (!this.proposal || this.proposalSaving) return;
    this.proposalSaving = true;
    this.proposalError = '';
    this.cdr.markForCheck();
    this.proposalService.send(this.requestId).subscribe({
      next: (p) => {
        this.proposal = p;
        this.proposalSaving = false;
        this.info = 'Proposal sent to the client';
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.proposalError = err?.error?.message || 'Failed to send proposal';
        this.proposalSaving = false;
        this.cdr.markForCheck();
      },
    });
  }

  acceptProposal(): void {
    if (this.proposalSaving) return;
    this.proposalSaving = true;
    this.proposalError = '';
    this.cdr.markForCheck();
    this.proposalService.accept(this.requestId).subscribe({
      next: (p) => {
        this.proposal = p;
        this.proposalSaving = false;
        this.info = 'Proposal accepted - the team will follow up with a formal quotation.';
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.proposalError = err?.error?.message || 'Failed to accept proposal';
        this.proposalSaving = false;
        this.cdr.markForCheck();
      },
    });
  }

  submitRequestChanges(): void {
    if (this.proposalSaving) return;
    this.proposalSaving = true;
    this.proposalError = '';
    this.cdr.markForCheck();
    this.proposalService.requestChanges(this.requestId, this.changesFeedback).subscribe({
      next: (p) => {
        this.proposal = p;
        this.showChangesForm = false;
        this.changesFeedback = '';
        this.proposalSaving = false;
        this.info = 'Feedback sent to the team';
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.proposalError = err?.error?.message || 'Failed to send feedback';
        this.proposalSaving = false;
        this.cdr.markForCheck();
      },
    });
  }

  onProposalFileSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    this.uploadingProposalFile = true;
    this.proposalError = '';
    this.cdr.markForCheck();

    this.api.uploadFile(file, 'ATTACHMENT').subscribe({
      next: (uploaded) => {
        this.proposalService.addAttachment(this.requestId, {
          fileName: uploaded.fileName,
          fileUrl: uploaded.fileUrl,
        }).subscribe({
          next: () => {
            this.uploadingProposalFile = false;
            this.loadProposal();
          },
          error: (err) => {
            this.proposalError = err?.error?.message || 'Failed to attach file';
            this.uploadingProposalFile = false;
            this.cdr.markForCheck();
          },
        });
      },
      error: (err) => {
        this.proposalError = err?.error?.message || 'Failed to upload file';
        this.uploadingProposalFile = false;
        this.cdr.markForCheck();
      },
    });
    input.value = '';
  }

  deleteProposalAttachment(attachmentId: number): void {
    this.proposalService.deleteAttachment(this.requestId, attachmentId).subscribe({
      next: () => this.loadProposal(),
      error: (err) => {
        this.proposalError = err?.error?.message || 'Failed to remove attachment';
        this.cdr.markForCheck();
      },
    });
  }
}
