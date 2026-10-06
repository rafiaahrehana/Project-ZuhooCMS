import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { DashboardService, ClientSummary } from '../../../../core/services/dashboard.service';
import { AuthService } from '../../../../core/services/auth.service';
import { ClientService } from '../../../crm/services/client.service';
import { Client } from '../../../crm/models/crm.model';
import { Loader } from '../../../../shared/components/loader/loader';
import { ServiceRequestService } from '../../../servicedesk/services/service-request.service';
import { ServiceRequest } from '../../../servicedesk/models/servicedesk.model';

import { BosCurrencyPipe } from '../../../../shared/pipes/bos-currency.pipe';

// Tokens the backend puts in ClientSummary.unavailableSections, and how this page names them to the client.
const SECTION_LABELS: Record<string, string> = {
  servicedesk: 'Service Requests',
  finance: 'Invoices',
};

@Component({
  selector: 'app-client-dashboard',
  imports: [BosCurrencyPipe, CommonModule, RouterLink, Loader],
  templateUrl: './client-dashboard.html',
  styleUrl: './client-dashboard.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ClientDashboard implements OnInit {
  summary?: ClientSummary;
  profile?: Client;
  recentRequests: ServiceRequest[] = [];
  loading = true;
  firstName = '';

  constructor(
    private dashboardService: DashboardService,
    private clientService: ClientService,
    private auth: AuthService,
    private requestService: ServiceRequestService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.firstName = (this.auth.getCurrentUser()?.fullName || '').split(' ')[0];
    this.dashboardService.getClientSummary().subscribe({
      next: (s) => { this.summary = s; this.loading = false; this.cdr.markForCheck(); },
      error: () => { this.loading = false; this.cdr.markForCheck(); },
    });
    this.clientService.getMyProfile().subscribe({
      next: (p) => { this.profile = p; this.cdr.markForCheck(); },
      error: () => {},
    });
    this.requestService.my(0, 5).subscribe({
      next: (res) => {
        this.recentRequests = res.content || [];
        this.cdr.markForCheck();
      },
      error: () => {}
    });
  }

  /**
   * Sections the backend could not read, named for the user. The cards above them show zero either way, so without
   * this a down service is indistinguishable from an account with nothing in it. Unknown tokens are shown as-is.
   */
  get unavailableSections(): string[] {
    return (this.summary?.unavailableSections ?? []).map(s => SECTION_LABELS[s] ?? s);
  }

  fmt(n: number | undefined): string {
    return n == null ? '-' : n.toLocaleString();
  }
}
