import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService, PagedResponse } from '../../../core/services/api.service';
import { ApplicationStatus, Employee, EvaluateCandidateRequest, HireApplicationRequest, JobApplication, JobApplicationRequest } from '../models/hrm.model';

@Injectable({ providedIn: 'root' })
export class RecruitmentService {
  private readonly endpoint = '/recruitment';

  /** All offers made against an application - the ACCEPTED one pre-fills the hire wizard. */
  offersForApplication(applicationId: number) {
    return this.api.get<any[]>(`${this.endpoint}/offers/application/${applicationId}`);
  }

  constructor(private api: ApiService) {}

  apply(jobPostingId: number, payload: JobApplicationRequest): Observable<JobApplication> {
    return this.api.post<JobApplication>(`${this.endpoint}/jobs/${jobPostingId}/apply`, payload);
  }

  list(page = 0, size = 20, status?: ApplicationStatus): Observable<PagedResponse<JobApplication>> {
    const params: Record<string, string | number> = {};
    if (status) params['status'] = status;
    return this.api.getPaged<JobApplication>(`${this.endpoint}/applications`, page, size, params);
  }

  listForJob(jobPostingId: number, page = 0, size = 20): Observable<PagedResponse<JobApplication>> {
    return this.api.getPaged<JobApplication>(`${this.endpoint}/jobs/${jobPostingId}/applications`, page, size);
  }

  getById(id: number): Observable<JobApplication> {
    return this.api.get<JobApplication>(`${this.endpoint}/applications/${id}`);
  }

  updateStatus(id: number, status: ApplicationStatus, notes?: string): Observable<JobApplication> {
    return this.api.patch<JobApplication>(`${this.endpoint}/applications/${id}/status`, { status, notes });
  }

  // Sets whichever scores are provided; the backend recomputes overallScore.
  evaluate(id: number, payload: EvaluateCandidateRequest): Observable<JobApplication> {
    return this.api.patch<JobApplication>(`${this.endpoint}/applications/${id}/evaluate`, payload);
  }

  // Creates the Employee and portal user, and marks the application HIRED.
  hire(id: number, payload: HireApplicationRequest): Observable<Employee> {
    return this.api.post<Employee>(`${this.endpoint}/applications/${id}/hire`, payload);
  }

  delete(id: number): Observable<string> {
    // The backend answers 200 with a plain-text body, which HttpClient's default JSON parsing reports as an error.
    return this.api.deleteText(`${this.endpoint}/applications/${id}`);
  }
}
