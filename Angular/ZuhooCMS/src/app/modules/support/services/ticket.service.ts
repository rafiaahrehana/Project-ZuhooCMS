import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService, PagedResponse } from '../../../core/services/api.service';
import { SupportMessage, SupportTicket } from '../models/support.model';

@Injectable({ providedIn: 'root' })
export class TicketService {
  private readonly endpoint = '/v1/support/tickets';
  constructor(private api: ApiService) {}

  list(page = 0, size = 20): Observable<PagedResponse<SupportTicket>> { return this.api.getPaged<SupportTicket>(this.endpoint, page, size); }
  myTickets(userId?: number, page = 0, size = 20): Observable<PagedResponse<SupportTicket>> { return this.api.getPaged<SupportTicket>(`${this.endpoint}/my-tickets`, page, size, { userId }); }
  assignedToMe(agentId: number, page = 0, size = 20): Observable<PagedResponse<SupportTicket>> { return this.api.getPaged<SupportTicket>(`${this.endpoint}/assigned-to-me`, page, size, { agentId }); }
  listByStatus(status: string, page = 0): Observable<PagedResponse<SupportTicket>> { return this.api.getPaged<SupportTicket>(`${this.endpoint}/status/${status}`, page, 20); }
  slaBreached(): Observable<SupportTicket[]> { return this.api.get<SupportTicket[]>(`${this.endpoint}/sla-breached`); }
  criticalOpen(): Observable<SupportTicket[]> { return this.api.get<SupportTicket[]>(`${this.endpoint}/critical-open`); }
  getById(id: number): Observable<SupportTicket> { return this.api.get<SupportTicket>(`${this.endpoint}/${id}`); }
  getByNumber(number: string): Observable<SupportTicket> { return this.api.get<SupportTicket>(`${this.endpoint}/number/${number}`); }
  create(payload: any): Observable<SupportTicket> { return this.api.post<SupportTicket>(this.endpoint, payload); }
  update(id: number, payload: any): Observable<SupportTicket> { return this.api.patch<SupportTicket>(`${this.endpoint}/${id}`, payload); }
  delete(id: number): Observable<void> { return this.api.delete<void>(`${this.endpoint}/${id}`); }

  // Backend expects these as @RequestParam query params, not a JSON body
  assign(id: number, agentId: number): Observable<void> { return this.api.post<void>(`${this.endpoint}/${id}/assign?agentId=${agentId}`, {}); }
  reassign(id: number, newAgentId: number, reason: string): Observable<void> {
    return this.api.post<void>(`${this.endpoint}/${id}/reassign?newAgentId=${newAgentId}&reason=${encodeURIComponent(reason)}`, {});
  }
  escalate(id: number, reason: string): Observable<void> {
    return this.api.post<void>(`${this.endpoint}/${id}/escalate?reason=${encodeURIComponent(reason)}`, {});
  }
  recordFirstResponse(id: number): Observable<void> { return this.api.post<void>(`${this.endpoint}/${id}/first-response`, {}); }
  resolve(id: number, notes: string): Observable<void> {
    return this.api.post<void>(`${this.endpoint}/${id}/resolve?notes=${encodeURIComponent(notes)}`, {});
  }
  close(id: number): Observable<void> { return this.api.post<void>(`${this.endpoint}/${id}/close`, {}); }
  reopen(id: number, reason: string): Observable<void> {
    return this.api.post<void>(`${this.endpoint}/${id}/reopen?reason=${encodeURIComponent(reason)}`, {});
  }
  recordSatisfaction(id: number, rating: number, feedback: string): Observable<void> {
    return this.api.post<void>(`${this.endpoint}/${id}/satisfaction?rating=${rating}&feedback=${encodeURIComponent(feedback)}`, {});
  }

  // CLIENT-facing CUSTOMER_SUPPORT tickets, distinct from create()/myTickets() above, which raise PLATFORM_SUPPORT tickets to BusinessOS.
  createForClient(payload: {
    title: string;
    description: string;
    priority: string;
    attachmentUrl?: string;
    attachmentFileName?: string;
  }): Observable<SupportTicket> {
    return this.api.post<SupportTicket>(`${this.endpoint}/client`, payload);
  }
  myClientTickets(page = 0, size = 20): Observable<PagedResponse<SupportTicket>> {
    return this.api.getPaged<SupportTicket>(`${this.endpoint}/client/my`, page, size);
  }
  getClientTicketById(id: number): Observable<SupportTicket> {
    return this.api.get<SupportTicket>(`${this.endpoint}/client/${id}`);
  }

  // Staff-facing "Client Chat" inbox for this company's clients' tickets; list()/listByStatus() above return only PLATFORM_SUPPORT ones.
  companyClientTickets(page = 0, size = 20): Observable<PagedResponse<SupportTicket>> {
    return this.api.getPaged<SupportTicket>(`${this.endpoint}/company/client-tickets`, page, size);
  }
  companyClientTicketsByStatus(status: string, page = 0, size = 20): Observable<PagedResponse<SupportTicket>> {
    return this.api.getPaged<SupportTicket>(`${this.endpoint}/company/client-tickets/status/${status}`, page, size);
  }

  // Client Chat conversations need their own paths: the shared /{id}, /messages/ticket/{id}/external and POST /messages always mean a platform-support ticket.
  companyClientTicket(id: number): Observable<SupportTicket> {
    return this.api.get<SupportTicket>(`${this.endpoint}/company/client-tickets/${id}`);
  }
  companyClientTicketMessages(id: number): Observable<SupportMessage[]> {
    return this.api.get<SupportMessage[]>(`${this.endpoint}/company/client-tickets/${id}/messages`);
  }
  replyToClientTicket(
    id: number,
    payload: { message: string; attachmentUrl?: string; attachmentFileName?: string },
  ): Observable<SupportMessage> {
    return this.api.post<SupportMessage>(`${this.endpoint}/company/client-tickets/${id}/messages`, payload);
  }
}
